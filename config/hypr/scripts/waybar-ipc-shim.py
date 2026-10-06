#!/usr/bin/env python3
"""waybar-ipc-shim — puente IPC entre waybar 0.12 y Hyprland 0.55 (config Lua).

Motivo: al hacer clic en un icono de workspace, waybar 0.12 envia por el socket
de comandos de Hyprland la sintaxis antigua ("dispatch workspace N"), pero
Hyprland 0.55 configurado en Lua solo entiende dispatchers Lua
("dispatch hl.dsp.focus({ ... })"). waybar lo corrigio en su rama master
(PR #5013 + PR #5231), pero ningun release lo incluye todavia: trixie trae
0.12.0 y la ultima version publicada (0.15.0, feb 2026) sigue afectada.

Solucion: este proceso crea una instancia Hyprland "falsa" (un directorio
$XDG_RUNTIME_DIR/hypr/<firma-falsa> con los dos sockets) y reenvia todo a la
instancia real:

    - socket de comandos: traduce unicamente los dispatches legacy que envia
      waybar (workspace, focusworkspaceoncurrentmonitor, togglespecialworkspace)
      a su equivalente Lua; las consultas j/... y cualquier comando que ya sea
      Lua pasan intactos;
    - socket de eventos (.socket2): reenvia el flujo tal cual y reconecta si la
      instancia real lo corta (waybar 0.12 no reconecta por su cuenta).

Asi clicar en waybar funciona sin recompilar ni instalar nada.

Uso normal (lo hace scripts/waybar-start.sh, no llamar a mano):

    waybar-ipc-shim.py --real-sig <firma-real> [--fake-sig waybar-lua-shim]

Pruebas:

    waybar-ipc-shim.py --translate 'dispatch workspace 3'   # imprime la traduccion

Reversion: parar el proceso, borrar $XDG_RUNTIME_DIR/hypr/waybar-lua-shim y
lanzar waybar sin pasar por el wrapper.
"""

import argparse
import logging
import os
import re
import signal
import socket
import socketserver
import sys
import threading
import time

LOG = logging.getLogger("waybar-ipc-shim")

_WORKSPACE_RE = re.compile(r"^workspace\s+(\S+)$")
_FOCUS_ON_CURRENT_RE = re.compile(r"^focusworkspaceoncurrentmonitor\s+(\S+)$")
_TOGGLE_SPECIAL_RE = re.compile(r"^togglespecialworkspace(?:\s+(\S+))?$")


def _lua_string(value):
    """Devuelve `value` como literal de cadena Lua."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def translate_dispatch(text):
    """Traduce un dispatch legacy al equivalente Lua; el resto tal cual.

    Mapeo basado en el fix oficial de waybar (PR #5013), corregido: en la API
    Lua de Hyprland 0.55 `monitor` tiene prioridad sobre `workspace` en
    hl.dsp.focus, asi que el equivalente de focusworkspaceoncurrentmonitor
    usa on_current_monitor en lugar de monitor = "current":

        workspace N                      -> hl.dsp.focus({ workspace = "N" })
        workspace name:foo               -> hl.dsp.focus({ workspace = "name:foo" })
        focusworkspaceoncurrentmonitor N -> hl.dsp.focus({ workspace = "N", on_current_monitor = true })
        togglespecialworkspace [foo]     -> hl.dsp.workspace.toggle_special("foo")

    Si el comando ya es Lua (empieza por hl.dsp.) o no es una de esas formas,
    se devuelve sin tocar: asi los dispatchers Lua que ya usan los atajos y los
    handlers on-scroll de waybar siguen funcionando igual.
    """
    match = _WORKSPACE_RE.match(text)
    if match:
        return "hl.dsp.focus({ workspace = %s })" % _lua_string(match.group(1))

    match = _FOCUS_ON_CURRENT_RE.match(text)
    if match:
        return "hl.dsp.focus({ workspace = %s, on_current_monitor = true })" % _lua_string(match.group(1))

    match = _TOGGLE_SPECIAL_RE.match(text)
    if match:
        name = (match.group(1) or "").strip()
        if name:
            return "hl.dsp.workspace.toggle_special(%s)" % _lua_string(name)
        return "hl.dsp.workspace.toggle_special()"

    return text


def translate_request(request):
    """Traduce la peticion completa (con o sin prefijo '/'); el resto intacto."""
    body = request.strip()
    if body.startswith("/"):
        body = body[1:].lstrip()
    if body.startswith("dispatch "):
        return "dispatch " + translate_dispatch(body[len("dispatch "):].strip())
    return request


class _CommandServer(socketserver.ThreadingUnixStreamServer):
    """Socket de comandos falso: recibe, traduce, reenvia y devuelve la respuesta."""

    daemon_threads = True

    def __init__(self, path, real_path):
        self.real_path = real_path
        super().__init__(path, _CommandHandler)

    def forward(self, payload):
        """Equivale a hyprctl: conexion nueva, enviar, leer hasta el cierre."""
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(5.0)
            conn.connect(self.real_path)
            if payload:
                conn.sendall(payload)
            chunks = []
            while True:
                try:
                    chunk = conn.recv(65536)
                except socket.timeout:
                    break
                if not chunk:
                    break
                chunks.append(chunk)
        return b"".join(chunks)


class _CommandHandler(socketserver.BaseRequestHandler):
    def handle(self):
        # waybar escribe la peticion de una vez; una lectura basta.
        self.request.settimeout(1.0)
        try:
            raw = self.request.recv(65536)
        except socket.timeout:
            return
        if not raw:
            return

        request = raw.decode("utf-8", "surrogateescape")
        translated = translate_request(request)
        if translated != request:
            LOG.info("traducido: %r -> %r", request.strip(), translated.strip())

        try:
            reply = self.server.forward(translated.encode("utf-8", "surrogateescape"))
        except OSError as exc:
            LOG.warning("no se pudo hablar con la instancia real: %s", exc)
            reply = ("error: puente IPC no disponible (%s)" % exc).encode()

        try:
            self.request.sendall(reply)
        except OSError as exc:
            LOG.debug("cliente desconectado antes de la respuesta: %s", exc)


class _EventRelay:
    """Socket .socket2 falso: reenvia eventos y reconecta ante cortes."""

    def __init__(self, listen_path, real_path):
        self.real_path = real_path
        self._stop = threading.Event()
        self._server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server.bind(listen_path)
        self._server.listen(8)

    def start(self):
        threading.Thread(target=self._accept_loop, name="eventos-aceptar", daemon=True).start()

    def _accept_loop(self):
        while not self._stop.is_set():
            try:
                client, _ = self._server.accept()
            except OSError:
                break
            threading.Thread(target=self._serve_client, args=(client,),
                             name="eventos-cliente", daemon=True).start()

    def _serve_client(self, client):
        LOG.debug("cliente de eventos conectado")
        try:
            while not self._stop.is_set():
                real = None
                try:
                    real = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    real.connect(self.real_path)
                    while not self._stop.is_set():
                        data = real.recv(65536)
                        if not data:
                            break  # la instancia real corta; reconectamos
                        client.sendall(data)
                except OSError as exc:
                    LOG.debug("stream de eventos interrumpido (%s); reintento", exc)
                finally:
                    if real is not None:
                        real.close()
                if self._stop.wait(0.3):
                    break
        except OSError as exc:
            LOG.debug("cliente de eventos caido: %s", exc)
        finally:
            client.close()

    def stop(self):
        self._stop.set()
        try:
            self._server.close()
        except OSError:
            pass


def _parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Puente IPC waybar 0.12 -> Hyprland 0.55 (Lua)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--real-sig", default=os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"),
                        help="firma de la instancia real (por defecto, $HYPRLAND_INSTANCE_SIGNATURE)")
    parser.add_argument("--fake-sig", default="waybar-lua-shim",
                        help="nombre de la instancia falsa (por defecto: waybar-lua-shim)")
    parser.add_argument("--translate", metavar="COMANDO",
                        help="imprime la traduccion de un comando y sale (para pruebas)")
    return parser.parse_args(argv)


def main(argv=None):
    args = _parse_args(argv if argv is not None else sys.argv[1:])

    if args.translate is not None:
        print(translate_request(args.translate))
        return 0

    logging.basicConfig(stream=sys.stderr, level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")

    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        LOG.error("XDG_RUNTIME_DIR no esta definido")
        return 1
    if not args.real_sig:
        LOG.error("falta --real-sig (o HYPRLAND_INSTANCE_SIGNATURE)")
        return 1

    real_dir = os.path.join(runtime, "hypr", args.real_sig)
    real_cmd = os.path.join(real_dir, ".socket.sock")
    real_evt = os.path.join(real_dir, ".socket2.sock")
    for path in (real_cmd, real_evt):
        if not os.path.exists(path):
            LOG.error("no existe la instancia real de Hyprland: %s", path)
            return 1

    fake_dir = os.path.join(runtime, "hypr", args.fake_sig)
    fake_cmd = os.path.join(fake_dir, ".socket.sock")
    fake_evt = os.path.join(fake_dir, ".socket2.sock")
    pidfile = os.path.join(fake_dir, "shim.pid")
    os.makedirs(fake_dir, exist_ok=True)

    # Si ya hay un puente vivo, no arrancar otro.
    if os.path.exists(pidfile):
        old_pid = None
        try:
            with open(pidfile) as fh:
                old_pid = int(fh.read().strip())
        except (OSError, ValueError):
            pass
        if old_pid and old_pid != os.getpid():
            try:
                os.kill(old_pid, 0)
            except ProcessLookupError:
                old_pid = None
            except PermissionError:
                pass  # existe y no es nuestro: lo tratamos como vivo
            if old_pid:
                LOG.error("ya hay un puente en marcha (pid %d); salgo", old_pid)
                return 1
        try:
            os.unlink(pidfile)
        except OSError:
            pass

    # Restos de un cierre brusco anterior.
    for path in (fake_cmd, fake_evt):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    command_server = _CommandServer(fake_cmd, real_cmd)
    event_relay = _EventRelay(fake_evt, real_evt)
    event_relay.start()
    threading.Thread(target=command_server.serve_forever,
                     name="servidor-comandos", daemon=True).start()

    with open(pidfile, "w") as fh:
        fh.write("%d\n" % os.getpid())

    LOG.info("puente en marcha: %s -> %s (pid %d)", fake_dir, real_dir, os.getpid())

    def _cleanup():
        try:
            command_server.shutdown()
        except Exception:
            pass
        command_server.server_close()
        event_relay.stop()
        for path in (fake_cmd, fake_evt, pidfile):
            try:
                os.unlink(path)
            except OSError:
                pass
        try:
            os.rmdir(fake_dir)
        except OSError:
            pass

    def _on_signal(signum, _frame):
        LOG.info("senal %d: cerrando el puente", signum)
        _cleanup()
        os._exit(0)

    signal.signal(signal.SIGTERM, _on_signal)
    signal.signal(signal.SIGINT, _on_signal)

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    sys.exit(main())
