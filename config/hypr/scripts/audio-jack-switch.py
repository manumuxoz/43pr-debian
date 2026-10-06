#!/usr/bin/env python3
"""audio-jack-switch — gestiona la salida interna de la tarjeta de audio
(altavoces internos vs auriculares) segun el jack 3.5 mm.

Motivo: en el ASUS Zenbook UX3402VA (ALC294 + UCM sof-hda-dsp) los altavoces
internos y los auriculares viven en perfiles UCM mutuamente excluyentes:

    perfil 1 (Headphones): "HiFi (HDMI1, HDMI2, HDMI3, Headphones, Mic1, Mic2)"
    perfil 2 (Speaker):    "HiFi (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)"

Detalles:
- lee el estado del jack directamente de ALSA via libasound (ctypes), sin
  lanzar procesos, cada 0,25 s; si libasound fallara, usa `amixer` de respaldo;
- los cambios de objetivo se confirman tras varias lecturas seguidas
  (antirrebote ~1 s), para que un jack ruidoso no haga rebotar el perfil;
- tras cambiar de perfil espera activa (cada 0,1 s) a que aparezca el sink
  destino y fija el default en cuanto existe;
- si el sink por defecto queda en una salida HDMI/DP sin nada conectado, se
  restaura la salida interna que toque;
- si el nodo no esta muteado pero el interruptor ALSA correspondiente quedo en
  off (desincronizado tipico tras un cambio de perfil UCM), lo enciende;
- conserva el volumen de cada salida (altavoces/auriculares) en un estado
  propio, porque el cambio de perfil UCM recrea el sink a 1.00 y se perderia;
- si WirePlumber pierde la ruta de salida [Out] (enlace nodo->hardware roto,
  tipico de su version 0.5.8 con UCM dividido), deja los controles ALSA al
  maximo para que el volumen audible coincida con el del nodo;
- si un sink recien recreado ignora `wpctl set-volume` (sigue suspendido con
  el enlace roto), le conecta un stream de silencio muy corto para despertarlo
  y reintenta fijar el volumen una vez;
- resuelve el indice de perfil por nombre (robusto ante cambios de UCM).

Uso:
    python3 audio-jack-switch.py          # servicio (bucle)
    python3 audio-jack-switch.py --status # estado (jack/default)
"""

import ctypes
import ctypes.util
import json
import os
import pathlib
import subprocess
import sys
import time
import wave

# Identificadores estables (los IDs numericos cambian al recrear los nodos).
DEVICE_NAME = "alsa_card.pci-0000_00_1f.3-platform-skl_hda_dsp_generic"
CARD_ID = "sofhdadsp"  # id ALSA de la tarjeta (amixer -c sofhdadsp)

# Palabras clave para localizar cada perfil dentro de EnumProfile.
PROFILE_KEYWORD_JACK = "Headphones"
PROFILE_KEYWORD_SPEAKERS = "Speaker"
PROFILE_FALLBACK_JACK = 1
PROFILE_FALLBACK_SPEAKERS = 2

NODE_JACK = (
    "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic."
    "HiFi__Headphones__sink"
)
NODE_SPEAKERS = (
    "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink"
)

JACK_CONTROL_NAME = "Headphone Jack"
JACK_CONTROL = "iface=CARD,name=Headphone Jack"

# Estado propio de volumen por salida (el sink se recrea a 1.00 en cada cambio
# de perfil UCM, asi que lo recordamos aqui).
STATE_DIR = pathlib.Path.home() / ".local" / "state" / "audio-jack-switch"
VOLUMES_FILE = STATE_DIR / "volumes.json"
SILENCE_FILE = STATE_DIR / "silence.wav"  # despierta sinks suspendidos
SILENCE_SECONDS = 0.25
WARN_VOLUME_EVERY = 120.0  # limita el aviso de volumen no aplicable
VOLUME_TOLERANCE = 0.02  # margen para considerar dos volumenes iguales
POLL_SECONDS = 0.25
REASSERT_EVERY = 120  # ~30 s con POLL_SECONDS = 0,25
DEBOUNCE_TICKS = 4  # cambios de objetivo solo tras 4 lecturas seguidas iguales

# Salidas digitales del codigo: fragmento del node.name -> pcm del jack ALSA.
HDMI_PCM = {"HiFi__HDMI1__": 3, "HiFi__HDMI2__": 4, "HiFi__HDMI3__": 5}

SND_CTL_ELEM_IFACE_CARD = 0


class AlsaJack:
    """Lee un control booleano ALSA directamente via libasound (ctypes).

    Evita lanzar un proceso `amixer` en cada sondeo (mucho menos CPU). Si algo
    falla devuelve None y el llamante usa el respaldo por amixer.
    """

    def __init__(self, name):
        self.name = name
        self._lib = None
        self._ctl = None
        self._elem_id = None
        self._value = None

    def _load(self):
        if self._lib is not None:
            return self._lib
        path = ctypes.util.find_library("asound")
        if not path:
            raise OSError("libasound no disponible")
        lib = ctypes.CDLL(path)
        lib.snd_card_get_index.argtypes = [ctypes.c_char_p]
        lib.snd_card_get_index.restype = ctypes.c_int
        lib.snd_ctl_open.argtypes = [
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_char_p,
            ctypes.c_int,
        ]
        lib.snd_ctl_open.restype = ctypes.c_int
        lib.snd_ctl_close.argtypes = [ctypes.c_void_p]
        lib.snd_ctl_close.restype = ctypes.c_int
        lib.snd_ctl_elem_id_malloc.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
        lib.snd_ctl_elem_id_malloc.restype = ctypes.c_int
        lib.snd_ctl_elem_id_free.argtypes = [ctypes.c_void_p]
        lib.snd_ctl_elem_id_set_interface.argtypes = [ctypes.c_void_p, ctypes.c_uint]
        lib.snd_ctl_elem_id_set_device.argtypes = [ctypes.c_void_p, ctypes.c_uint]
        lib.snd_ctl_elem_id_set_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.snd_ctl_elem_id_set_index.argtypes = [ctypes.c_void_p, ctypes.c_uint]
        lib.snd_ctl_elem_value_malloc.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
        lib.snd_ctl_elem_value_malloc.restype = ctypes.c_int
        lib.snd_ctl_elem_value_free.argtypes = [ctypes.c_void_p]
        lib.snd_ctl_elem_value_set_id.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        lib.snd_ctl_elem_read.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        lib.snd_ctl_elem_read.restype = ctypes.c_int
        lib.snd_ctl_elem_value_get_boolean.argtypes = [ctypes.c_void_p, ctypes.c_uint]
        lib.snd_ctl_elem_value_get_boolean.restype = ctypes.c_int
        self._lib = lib
        return lib

    def _prepare(self):
        lib = self._load()
        if self._ctl is None:
            card = lib.snd_card_get_index(CARD_ID.encode())
            if card < 0:
                return False
            ctl = ctypes.c_void_p()
            if lib.snd_ctl_open(ctypes.byref(ctl), f"hw:{card}".encode(), 0) < 0:
                return False
            self._ctl = ctl
        if self._elem_id is None:
            elem_id = ctypes.c_void_p()
            if lib.snd_ctl_elem_id_malloc(ctypes.byref(elem_id)) < 0:
                return False
            lib.snd_ctl_elem_id_set_interface(elem_id, SND_CTL_ELEM_IFACE_CARD)
            lib.snd_ctl_elem_id_set_name(elem_id, self.name.encode())
            self._elem_id = elem_id
        if self._value is None:
            value = ctypes.c_void_p()
            if lib.snd_ctl_elem_value_malloc(ctypes.byref(value)) < 0:
                return False
            lib.snd_ctl_elem_value_set_id(value, self._elem_id)
            self._value = value
        return True

    def read(self):
        try:
            lib = self._load()
            if not self._prepare():
                return None
            lib.snd_ctl_elem_value_set_id(self._value, self._elem_id)
            if lib.snd_ctl_elem_read(self._ctl, self._value) < 0:
                # El handle puede haber quedado obsoleto: reabrir en el proximo
                # intento.
                lib.snd_ctl_close(self._ctl)
                self._ctl = None
                return None
            return bool(lib.snd_ctl_elem_value_get_boolean(self._value, 0))
        except Exception:
            self._ctl = None
            return None


_jack = None


def run(cmd):
    """Ejecuta un comando y devuelve su stdout (cadena vacia si falla)."""
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=15
        ).stdout
    except Exception:
        return ""


def jack_plugged():
    """True si hay algo en el jack; False si no; None si no se pudo leer."""
    global _jack
    if _jack is None:
        _jack = AlsaJack(JACK_CONTROL_NAME)

    value = _jack.read()
    if value is not None:
        return value

    # Respaldo: leerlo con amixer (mismo dato, pero lanzando un proceso).
    out = run(["amixer", "-c", CARD_ID, "cget", JACK_CONTROL])
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(": values="):
            return line.split("=", 1)[1].strip() == "on"
    return None


def pw_dump():
    """Lista de objetos de pw-dump (o [] si falla)."""
    try:
        return json.loads(run(["pw-dump"]))
    except Exception:
        return []


def find_device_id(objects):
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Device":
            continue
        props = obj.get("info", {}).get("props", {})
        if props.get("device.name") == DEVICE_NAME:
            return obj.get("id")
    return None


def find_device_object(objects):
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Device":
            continue
        props = obj.get("info", {}).get("props", {})
        if props.get("device.name") == DEVICE_NAME:
            return obj
    return None


def find_sink_id(objects, node_name):
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = obj.get("info", {}).get("props", {})
        if (
            props.get("media.class") == "Audio/Sink"
            and props.get("node.name") == node_name
        ):
            return obj.get("id")
    return None


def profile_index_for(objects, keyword, fallback):
    device = find_device_object(objects)
    if device is not None:
        for prof in device.get("info", {}).get("params", {}).get("EnumProfile", []):
            name = prof.get("name", "")
            if keyword.lower() in name.lower() and prof.get("index") is not None:
                return int(prof["index"])
    return fallback


def wpctl(*args):
    subprocess.run(["wpctl", *args], capture_output=True, text=True, timeout=15)


def read_volumes():
    """Estado propio de volumen por salida ({'speakers': V, 'headphones': V}).

    Devuelve {} si no existe o no se puede leer; nunca lanza excepciones.
    """
    try:
        data = json.loads(VOLUMES_FILE.read_text())
    except Exception:
        return {}
    volumes = {}
    for key in ("speakers", "headphones"):
        value = data.get(key)
        if isinstance(value, (int, float)):
            volumes[key] = float(value)
    return volumes


def write_volumes(volumes):
    """Escribe el estado de volumen por salida (atomico; nunca lanza)."""
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = VOLUMES_FILE.parent / (VOLUMES_FILE.name + ".tmp")
        tmp.write_text(json.dumps(volumes))
        os.replace(tmp, VOLUMES_FILE)
    except Exception:
        pass


def displayed_volume(sink_id):
    """Volumen mostrado por wpctl (0-1) o None si no se pudo leer."""
    out = run(["wpctl", "get-volume", str(sink_id)])
    for token in out.replace("[MUTED]", " ").split():
        try:
            return float(token)
        except ValueError:
            continue
    return None


def save_current_volumes(objects):
    """Guarda el volumen actual de cada sink interno (escribe solo si cambia).

    Se llama antes de cambiar de perfil, para no perder el volumen de la
    salida que se abandona.
    """
    volumes = read_volumes()
    changed = False
    for node_name, key in ((NODE_SPEAKERS, "speakers"), (NODE_JACK, "headphones")):
        sink_id = find_sink_id(objects, node_name)
        if sink_id is None:
            continue
        value = displayed_volume(sink_id)
        if value is None:
            continue
        if volumes.get(key) != value:
            volumes[key] = value
            changed = True
    if changed:
        write_volumes(volumes)


def output_route_lost(device_id):
    """True si el dispositivo ya no expone ninguna ruta de salida [Out].

    WirePlumber 0.5.8 con UCM dividido pierde la ruta de salida al cambiar de
    perfil: el enlace nodo->hardware queda roto y wpctl deja de mover el
    hardware. Devuelve None si no se pudo leer (p. ej. dispositivo recreado),
    para no concluir en falso.
    """
    out = run(["pw-cli", "enum-params", str(device_id), "Route"])
    if not out.strip():
        return None
    # Las rutas de salida se imprimen como '"[Out] Speaker"', no como
    # '"[Out]"' pelado: exigir el cierre de comillas daba True siempre y el
    # "reparador" subia el hardware a 100% en cada reafirmacion (con el
    # consiguiente vaiven de volumen y OSD espurio). Basta con ver la
    # direccion Output o el prefijo '"[Out]'.
    return '"[Out]' not in out and "Direction:Output" not in out


def ensure_silence_file():
    """Crea, una sola vez, el WAV de silencio usado para despertar el sink.

    Devuelve True si el fichero queda disponible. Usa solo la libreria
    estandar (modulo wave): 0,25 s, 48 kHz, 16 bit, estereo, todo ceros.
    """
    try:
        with wave.open(str(SILENCE_FILE)) as w:
            if (
                w.getnchannels() == 2
                and w.getsampwidth() == 2
                and w.getframerate() == 48000
                and w.getnframes() > 0
            ):
                return True
    except Exception:
        pass
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        frames = int(48000 * SILENCE_SECONDS)
        with wave.open(str(SILENCE_FILE), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(48000)
            w.writeframes(b"\x00" * frames * 2 * 2)
        return True
    except Exception:
        return False


def wake_sink(sink_id, node_name):
    """Conecta un stream de silencio al sink para que acepte el volumen.

    Un sink recien recreado con el enlace nodo->hw roto (WP 0.5.8) ignora
    `wpctl set-volume` mientras esta suspendido; al conectarle un stream deja
    de estarlo y el volumen se aplica. Se apunta por node.name (el id numerico
    recien creado puede no resolverse aun: "no target node available") y se
    cae a pw-cat si pw-play no esta. Devuelve True si el reproductor termino
    bien.
    """
    if not ensure_silence_file():
        return False
    for target in (node_name, str(sink_id)):
        for player in (["pw-play"], ["pw-cat", "--playback"]):
            cmd = [*player, "--target", target, str(SILENCE_FILE)]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            except Exception:
                continue
            if proc.returncode == 0:
                return True
    return False


_last_volume_warning = 0.0
# Controles cuyo aviso de "al maximo" ya se mostro (una sola vez por proceso:
# WirePlumber vuelve a bajar el control entre reafirmaciones y repetir el
# aviso no aporta nada).
_hw_warned = set()


def ensure_output_volume(objects, sink_id, plugged, device_id):
    """Restaura el volumen propio de la salida y repara el enlace nodo->hw.

    El cambio de perfil recrea el sink a 1.00, asi que se recupera el volumen
    recordado de esa salida (o, si no hay, el de la otra salida, el mostrado
    por wpctl, o 1.0 como ultimo recurso). Si WirePlumber perdio la ruta
    [Out], el hardware queda congelado: se dejan los controles ALSA al maximo
    para que el volumen audible pase a ser el del nodo. Si el volumen
    mostrado ya coincide con el objetivo no se escribe nada: cada escritura
    de wpctl cambia un parametro real del nodo y Quickshell abriria su OSD.
    """
    global _last_volume_warning
    key = "headphones" if plugged else "speakers"
    other = "speakers" if plugged else "headphones"
    volumes = read_volumes()
    value = volumes.get(key)
    if value is None:
        value = volumes.get(other)
    if value is None:
        value = displayed_volume(sink_id)
    if value is None:
        value = 1.0

    if output_route_lost(device_id) is True:
        control = "Headphone" if plugged else "Speaker"
        for ctl in (control, "Master"):
            cur = run(["amixer", "-c", CARD_ID, "sget", ctl])
            if "[100%]" not in cur:
                run(["amixer", "-c", CARD_ID, "sset", ctl, "100%"])
                if ctl not in _hw_warned:
                    _hw_warned.add(ctl)
                    print(f"enlace nodo->hw roto; control '{ctl}' al máximo", flush=True)

    # Si el sink ya muestra el volumen objetivo, no se toca: cada escritura
    # de wpctl genera un cambio real de parametro en el nodo y Quickshell
    # abre su OSD de volumen aunque el cambio no venga del usuario (la
    # reafirmacion periodica provocaba un falso OSD cada ~30 s).
    shown = displayed_volume(sink_id)
    if shown is not None and abs(shown - value) <= VOLUME_TOLERANCE:
        return

    wpctl("set-volume", str(sink_id), str(round(value, 4)))

    # Un sink recien recreado con el enlace roto ignora wpctl mientras sigue
    # suspendido: si el valor mostrado no cuadra, lo despertamos con un stream
    # de silencio y reintentamos una sola vez.
    shown = displayed_volume(sink_id)
    if shown is None or abs(shown - value) > VOLUME_TOLERANCE:
        wake_sink(sink_id, NODE_JACK if plugged else NODE_SPEAKERS)
        wpctl("set-volume", str(sink_id), str(round(value, 4)))
        shown = displayed_volume(sink_id)
        if shown is None or abs(shown - value) > VOLUME_TOLERANCE:
            now = time.time()
            if now - _last_volume_warning >= WARN_VOLUME_EVERY:
                _last_volume_warning = now
                print(
                    f"aviso: el volumen del sink {sink_id} sigue en {shown} "
                    f"(esperado {round(value, 4)}) tras despertarlo",
                    flush=True,
                )


def apply_profile(plugged, force_default):
    """Aplica el perfil acorde al objetivo. Devuelve True si cambio algo."""
    objects = pw_dump()
    # Antes de tocar el perfil, guarda el volumen de la salida que se abandona.
    save_current_volumes(objects)
    device_id = find_device_id(objects)
    if device_id is None:
        return False

    if plugged:
        target_node = NODE_JACK
        keyword = PROFILE_KEYWORD_JACK
        fallback = PROFILE_FALLBACK_JACK
        which = "auriculares"
    else:
        target_node = NODE_SPEAKERS
        keyword = PROFILE_KEYWORD_SPEAKERS
        fallback = PROFILE_FALLBACK_SPEAKERS
        which = "altavoces"

    sink_id = find_sink_id(objects, target_node)
    profile_changed = False

    if sink_id is None:
        index = profile_index_for(objects, keyword, fallback)
        print(f"cambiando al perfil de {which} (indice {index})", flush=True)
        wpctl("set-profile", str(device_id), str(index))
        profile_changed = True
        # Espera activa: en cuanto PipeWire cree el sink destino, se fija.
        deadline = time.time() + 5.0
        while time.time() < deadline:
            objects = pw_dump()
            sink_id = find_sink_id(objects, target_node)
            if sink_id is not None:
                break
            time.sleep(0.1)

    if sink_id is not None:
        # El cambio de perfil UCM puede dejar el interruptor del mezclador en
        # off aunque el nodo no este muteado: lo corregimos (respetando el mute,
        # p. ej. si el usuario silencio desde el OSD el nodo aparece MUTED).
        out = run(["wpctl", "get-volume", str(sink_id)])
        if "MUTED" not in out:
            # La API "simple" de amixer expone 'Speaker'/'Headphone'/'Master'
            # (volumen e interruptor en el mismo control); los nombres completos
            # del mezclador ('Speaker Playback Switch') NO existen como
            # controles simples y sget/sset fallan con ellos.
            profile_switch = "Headphone" if plugged else "Speaker"
            for switch in (profile_switch, "Master"):
                cur = run(["amixer", "-c", CARD_ID, "sget", switch])
                if "[off]" in cur:
                    run(["amixer", "-c", CARD_ID, "sset", switch, "on"])
                    after = run(["amixer", "-c", CARD_ID, "sget", switch])
                    if "[off]" not in after:
                        print(f"interruptor ALSA '{switch}' estaba off; corregido", flush=True)
                    else:
                        print(f"interruptor ALSA '{switch}' sigue off tras corregir", flush=True)

        # Con el sink ya asegurado, restaura el volumen propio de la salida y
        # repara el enlace nodo->hardware si WirePlumber perdio la ruta [Out].
        ensure_output_volume(objects, sink_id, plugged, device_id)

    if sink_id is not None and (force_default or profile_changed):
        wpctl("set-default", str(sink_id))
        print(f"salida por defecto: {which} (id {sink_id})", flush=True)
        return True

    return False


_hdmi_jacks = {}


def hdmi_jack_plugged(pcm):
    """True/False si el jack HDMI/DP tiene algo conectado; None si no se pudo leer."""
    jack = _hdmi_jacks.get(pcm)
    if jack is None:
        jack = AlsaJack(f"HDMI/DP,pcm={pcm} Jack")
        _hdmi_jacks[pcm] = jack
    return jack.read()


def current_default_sink_name():
    """node.name del sink por defecto ('' si no se pudo obtener)."""
    for line in run(["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"]).splitlines():
        line = line.strip().lstrip("*").strip()
        if line.startswith("node.name"):
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def dead_digital_default():
    """True si el sink por defecto es una salida HDMI/DP sin conectar."""
    name = current_default_sink_name()
    for fragment, pcm in HDMI_PCM.items():
        if fragment in name:
            return hdmi_jack_plugged(pcm) is False
    return False


def main():
    # Espera de arranque: hasta 60 s a que WirePlumber exponga la tarjeta.
    for _ in range(60):
        if find_device_id(pw_dump()) is not None:
            break
        time.sleep(1)

    last_target = None
    pending = None
    pending_count = 0
    tick = 0
    hold_until = 0.0
    hold_target = None

    def ensure_default(node_name):
        """Si el default no es el nodo esperado, lo re-fija (ventana post-cambio).

        WirePlumber puede mover el default al cambiar de perfil (p. ej. si el
        nodo destino aun no esta disponible): durante unos segundos tras cada
        transicion lo reafirmamos.
        """
        if current_default_sink_name() == node_name:
            return
        objects = pw_dump()
        sink_id = find_sink_id(objects, node_name)
        if sink_id is None:
            return
        wpctl("set-default", str(sink_id))
        print(f"reafirmo default -> {node_name.split('.')[-1]} (id {sink_id})", flush=True)

    while True:
        jack = jack_plugged()
        if jack is not None:
            target = jack
            if target != pending:
                pending = target
                pending_count = 1
            else:
                pending_count += 1
            if pending_count >= DEBOUNCE_TICKS and pending != last_target:
                apply_profile(pending, force_default=True)
                last_target = pending
                hold_target = pending
                hold_until = time.time() + 10.0
                tick = 0
            else:
                if hold_target is not None and time.time() < hold_until and tick % 2 == 0:
                    ensure_default(NODE_JACK if hold_target else NODE_SPEAKERS)
                if tick % REASSERT_EVERY == 0:
                    # Deriva: perfil incorrecto (WirePlumber reiniciado) o el
                    # default quedo en una salida HDMI/DP sin conexion.
                    if last_target is not None and dead_digital_default():
                        print(
                            "default en salida HDMI/DP sin conexion; restaurando",
                            flush=True,
                        )
                        apply_profile(last_target, force_default=True)
                    else:
                        apply_profile(target, force_default=False)
        time.sleep(POLL_SECONDS)
        tick += 1


def cli(argv):
    if not argv:
        return None
    if argv[0] == "--status":
        jack = jack_plugged()
        name = current_default_sink_name()
        print(f"jack={'on' if jack else 'off' if jack is not None else 'unknown'}")
        print(f"default={name.split('.')[-1] if name else ''}")
        return 0
    print("uso: audio-jack-switch.py [--status]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        rc = cli(sys.argv[1:])
        if rc is None:
            main()
        else:
            sys.exit(rc)
    except KeyboardInterrupt:
        sys.exit(0)
