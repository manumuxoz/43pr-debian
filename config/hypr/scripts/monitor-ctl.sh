#!/usr/bin/env bash
# monitor-ctl.sh — gestion de monitores en Hyprland 0.55 (config Lua).
#
# Uso:
#   monitor-ctl.sh mode <salida> <WxH@RR|preferred|highrr|highres>
#                                           -> p.ej. mode eDP-1 2880x1800@90.00
#   monitor-ctl.sh scale <salida> <factor>  -> p.ej. scale DP-1 1.0
#   monitor-ctl.sh primary <salida>         -> hace principal esa salida (0x0, escritorios fijos del principal)
#   monitor-ctl.sh primary                  -> imprime SOLO la salida principal actual
#   monitor-ctl.sh reconcile [--quiet]      -> adopta salidas nuevas y corrige modos no soportados
#
# Aplica en vivo con `hyprctl eval` (hl.monitor) usando el modo/posicion/escala
# vigentes de cada salida, y persiste el bloque gestionado en:
#   ~/.config/hypr/monitors.lua        (obligatorio)
#
# Cualquier salida conectada que no este en el bloque se adopta
# automaticamente (al cambiar de puerto, p.ej. DP-3 <-> HDMI-A-1, no hay que
# editar nombres a mano). La adopcion conserva el modo vivo solo si aparece
# en availableModes; si no, usa "preferred".
#
# Los modos exactos se validan contra availableModes (hyprctl -j monitors).
# Hyprland acepta modos que el EDID no anuncia, pero el panel puede quedar
# encendido y en negro; por eso tambien se revisan los modos ya aplicados.
# Idempotente (si ya esta asi no reescribe nada) y atomico (tmp + rename).
# Salida 0 = ok; errores a stderr con codigo != 0.

set -euo pipefail
exec python3 - "$@" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
MONITORS_LUA = os.path.join(HOME, ".config/hypr/monitors.lua")

BEGIN = "-- ==== INICIO gestionado por monitor-ctl.sh (no editar a mano) ===="
END = "-- ==== FIN gestionado por monitor-ctl.sh ===="
BLOCK_RE = re.compile(re.escape(BEGIN) + r"\n.*?\n" + re.escape(END), re.DOTALL)
PRIMARY_RE = re.compile(r'^[ \t]*PRIMARY_MONITOR\s*=\s*"([^"]+)"[ \t]*$', re.MULTILINE)
SECONDARY_RE = re.compile(r'^[ \t]*SECONDARY_MONITOR\s*=\s*"([^"]+)"[ \t]*$', re.MULTILINE)
WORKSPACES_RE = re.compile(r'^[ \t]*PRIMARY_WORKSPACES\s*=\s*(\d+)[ \t]*$', re.MULTILINE)
SYMBOLIC_MODES = ("preferred", "highres", "highrr", "maxwidth")
MODE_VALUE = r"(?:preferred|highres|highrr|maxwidth|\d+x\d+@\d+(?:\.\d+)?)"
RULE_RE = re.compile(
    r'^[ \t]*hl\.monitor\(\{\s*output\s*=\s*"([^"]+)"\s*,\s*mode\s*=\s*"(' + MODE_VALUE + r')"\s*,\s*'
    r'position\s*=\s*"([^"]+)"\s*,\s*scale\s*=\s*([0-9.]+)\s*\}\)[ \t]*$',
    re.MULTILINE,
)
MODE_ARG_RE = re.compile(r"^(\d+)x(\d+)@(\d+(?:\.\d+)?)$")
AVAIL_MODE_RE = re.compile(r"^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz$")
SCALE_RE = re.compile(r"^\d+(?:\.\d+)?$")
SCALE_MIN, SCALE_MAX = 0.25, 4.0


def die(msg):
    print("monitor-ctl: " + msg, file=sys.stderr)
    sys.exit(1)


def note(msg):
    print("monitor-ctl: " + msg)


def fmt_scale(value):
    # 1.75 -> "1.75"; 1.0 -> "1.0" (literal Lua valido)
    text = "%.2f" % value
    text = text.rstrip("0")
    if text.endswith("."):
        text += "0"
    return text


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def parse_managed(path):
    if not os.path.isfile(path):
        die("no existe " + path)
    content = read_text(path)
    blocks = BLOCK_RE.findall(content)
    if len(blocks) != 1:
        die("no encontre exactamente 1 bloque gestionado en %s (encontrados: %d)" % (path, len(blocks)))
    block = blocks[0]
    primary_match = PRIMARY_RE.search(block)
    secondary_match = SECONDARY_RE.search(block)
    if not primary_match or not secondary_match:
        die("el bloque gestionado de %s no define PRIMARY_MONITOR/SECONDARY_MONITOR" % path)
    ws_match = WORKSPACES_RE.search(block)
    primary_ws = max(1, int(ws_match.group(1))) if ws_match else 5
    rules = {}
    for name, mode, position, scale in RULE_RE.findall(block):
        rules[name] = {"mode": mode, "position": position, "scale": float(scale)}
    if not rules:
        die("el bloque gestionado de %s no contiene ninguna regla de monitor" % path)
    return rules, primary_match.group(1), secondary_match.group(1), primary_ws


def render_managed(primary, secondary, rules, primary_ws):
    lines = [
        BEGIN,
        'PRIMARY_MONITOR = "%s"' % primary,
        'SECONDARY_MONITOR = "%s"' % secondary,
    ]
    order = []
    for name in (primary, secondary):
        if name in rules and name not in order:
            order.append(name)
    for name in rules:
        if name not in order:
            order.append(name)
    for name in order:
        rule = rules[name]
        lines.append(
            'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s })'
            % (name, rule["mode"], rule["position"], fmt_scale(rule["scale"]))
        )
    # Escritorios fijos persistentes: 1..PRIMARY_WORKSPACES en el principal.
    # El monitor secundario recibe un escritorio temporal NO persistente
    # (PRIMARY_WORKSPACES + 1): al conectarlo se abre por ser su default y,
    # al desconectarlo (o quedar vacio e inactivo), desaparece. Para anadir
    # mas escritorios fijos sube PRIMARY_WORKSPACES: el temporal pasara
    # automaticamente al siguiente numero.
    lines.append("PRIMARY_WORKSPACES = %d" % primary_ws)
    lines.append("for i = 1, PRIMARY_WORKSPACES do hl.workspace_rule({ workspace = tostring(i), monitor = PRIMARY_MONITOR, default = true, persistent = true }) end")
    lines.append("hl.workspace_rule({ workspace = tostring(PRIMARY_WORKSPACES + 1), monitor = SECONDARY_MONITOR, default = true })")
    lines.append(END)
    return "\n".join(lines)


def prepare_changes(primary, secondary, rules, primary_ws):
    block = render_managed(primary, secondary, rules, primary_ws)
    if not os.path.isfile(MONITORS_LUA):
        die("no existe " + MONITORS_LUA)
    content = read_text(MONITORS_LUA)
    if len(BLOCK_RE.findall(content)) != 1:
        die("no encontre exactamente 1 bloque gestionado en " + MONITORS_LUA)
    new_content = BLOCK_RE.sub(lambda _m: block, content, count=1)
    if new_content == content:
        return []
    return [(MONITORS_LUA, new_content)]


def write_changes(changes):
    for path, new_content in changes:
        file_mode = os.stat(path).st_mode
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".monitor-ctl-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(new_content)
            os.chmod(tmp, file_mode)
            os.replace(tmp, path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise


def write_or_rollback(changes, prev, what):
    try:
        write_changes(changes)
    except OSError as exc:
        try:
            for output, mode, position, scale in prev:
                eval_monitor(output, mode, position, scale)
        except SystemExit:
            pass
        die("no pude persistir %s: %s" % (what, exc))
    return ", ".join(os.path.basename(path) for path, _ in changes)


# --- entorno hyprctl ------------------------------------------------------

env = dict(os.environ)
if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
    runtime = env.get("XDG_RUNTIME_DIR")
    candidates = [os.path.join(runtime, "hypr") if runtime else None, "/tmp/hypr"]
    for base in filter(None, candidates):
        if not os.path.isdir(base):
            continue
        for sig in sorted(os.listdir(base)):
            # Hyprland >= 0.55 usa .socket.sock; las versiones antiguas .hyprland.sock
            if os.path.exists(os.path.join(base, sig, ".socket.sock")) or os.path.exists(
                os.path.join(base, sig, ".hyprland.sock")
            ):
                env["HYPRLAND_INSTANCE_SIGNATURE"] = sig
                break
        if env.get("HYPRLAND_INSTANCE_SIGNATURE"):
            break

hyprctl = shutil.which("hyprctl", path=env.get("PATH")) or "/usr/bin/hyprctl"


def hyprctl_run(*args):
    return subprocess.run([hyprctl, *args], capture_output=True, text=True, env=env)


def read_live():
    result = hyprctl_run("monitors", "-j")
    if result.returncode != 0:
        die("hyprctl no responde: " + (result.stderr.strip() or "¿Hyprland activo?"))
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        die("respuesta JSON invalida de hyprctl: " + str(exc))
    return {m["name"]: m for m in data if isinstance(m, dict) and m.get("name")}


def wait_for(check, timeout, live=None):
    deadline = time.monotonic() + timeout
    live = live if live is not None else read_live()
    while True:
        if check(live):
            return live
        if time.monotonic() >= deadline:
            return live
        time.sleep(0.15)
        live = read_live()


def live_mode(mon):
    return "%dx%d@%.2f" % (mon["width"], mon["height"], float(mon["refreshRate"]))


def live_position(mon):
    return "%dx%d" % (mon["x"], mon["y"])


def available_modes(mon):
    modes = []
    for entry in mon.get("availableModes") or []:
        parsed = AVAIL_MODE_RE.match(entry)
        if not parsed:
            continue
        modes.append((int(parsed.group(1)), int(parsed.group(2)), float(parsed.group(3))))
    return modes


def mode_is_supported(mon, mode):
    # Los modos simbolicos los resuelve Hyprland contra el EDID.
    if mode in SYMBOLIC_MODES:
        return True
    parsed = MODE_ARG_RE.match(mode or "")
    if not parsed:
        return False
    want_w, want_h, want_rr = int(parsed.group(1)), int(parsed.group(2)), float(parsed.group(3))
    return any(width == want_w and height == want_h and abs(rate - want_rr) <= 0.02
               for width, height, rate in available_modes(mon))


def live_mode_supported(mon):
    return mode_is_supported(mon, live_mode(mon))


def mode_matches(mon, mode):
    if mode in SYMBOLIC_MODES:
        return live_mode_supported(mon)
    parsed = MODE_ARG_RE.match(mode or "")
    if not parsed:
        return False
    return mode_is_supported(mon, mode) and (
        mon["width"] == int(parsed.group(1))
        and mon["height"] == int(parsed.group(2))
        and abs(float(mon["refreshRate"]) - float(parsed.group(3))) <= 0.02
    )


def find_available_mode(mon, want_w, want_h, want_rr):
    candidates = []
    for width, height, rate in available_modes(mon):
        if width == want_w and height == want_h and abs(rate - want_rr) <= 0.005:
            candidates.append((width, height, rate))
    if not candidates:
        return None
    candidates.sort(key=lambda item: (abs(item[2] - want_rr), item[2]))
    width, height, rate = candidates[0]
    return "%dx%d@%.2f" % (width, height, rate)


def best_safe_mode(mon, wanted=None):
    """Modo aplicable sin arriesgar un panel negro.

    Respeta el modo pedido si existe en availableModes; si no, conserva el
    modo vivo cuando es valido y, como ultimo recurso, usa "preferred".
    """
    if wanted in SYMBOLIC_MODES:
        return wanted
    parsed = MODE_ARG_RE.match(wanted or "")
    if parsed:
        found = find_available_mode(mon, int(parsed.group(1)), int(parsed.group(2)), float(parsed.group(3)))
        if found:
            return found
    if live_mode_supported(mon):
        return live_mode(mon)
    return "preferred"


def adopt_output(rules, live, output):
    # Salida conectada que no esta en el bloque gestionado: se adopta sin mover
    # nada, pero nunca se persiste un modo que el EDID no anuncie.
    if output in rules:
        return False
    mon = live[output]
    if mon.get("disabled") or int(mon.get("width") or 0) <= 0 or int(mon.get("height") or 0) <= 0:
        die("salida desactivada o sin modo activo: %s (no se puede adoptar)" % output)
    rules[output] = {
        "mode": live_mode(mon) if live_mode_supported(mon) else "preferred",
        "position": live_position(mon),
        "scale": float(mon.get("scale") or 1.0),
    }
    return True


def pick_available_mode(mon, want_w, want_h, want_rr, raw):
    found = find_available_mode(mon, want_w, want_h, want_rr)
    if not found:
        die("modo no disponible en %s: %s (mira availableModes con 'hyprctl -j monitors')"
            % (mon["name"], raw))
    return found


def ensure_scale_checks():
    # Sin esto Hyprland recorta escalas fraccionales (1.75 -> 1.8).
    result = hyprctl_run("eval", "hl.config({debug = {disable_scale_checks = 1}})")
    if result.returncode != 0:
        print("monitor-ctl: aviso: no pude asegurar debug:disable_scale_checks ("
              + (result.stderr.strip() or "sin salida") + ")", file=sys.stderr)
    time.sleep(0.2)


def eval_monitor(output, mode, position, scale):
    lua = 'hl.monitor({output = "%s", mode = "%s", position = "%s", scale = %s})' % (
        output, mode, position, fmt_scale(scale))
    result = hyprctl_run("eval", lua)
    if result.returncode != 0:
        die("hyprctl eval fallo para %s: %s"
            % (output, result.stderr.strip() or result.stdout.strip() or "sin salida"))


def rollback(prev):
    for output, mode, position, scale in prev:
        try:
            eval_monitor(output, mode, position, scale)
        except SystemExit:
            pass


def apply_and_verify(desired, prev, check, what):
    ensure_scale_checks()
    try:
        for timeout in (2.5, 1.5):
            for output, mode, position, scale in desired:
                eval_monitor(output, mode, position, scale)
            current = wait_for(check, timeout)
            if check(current):
                return
    except SystemExit:
        rollback(prev)
        raise
    rollback(prev)
    die("no pude confirmar %s; intente revertir en vivo (revisa 'hyprctl monitors')" % what)


# --- comandos -------------------------------------------------------------

args = sys.argv[1:]
if not args:
    die("uso: monitor-ctl.sh {mode <salida> <WxH@RR|preferred|highrr|highres> | "
        "scale <salida> <factor> | primary [salida] | reconcile [--quiet]}")

command = args[0]

if command == "primary" and len(args) == 1:
    _rules, primary, _secondary, _ws = parse_managed(MONITORS_LUA)
    print(primary)
    sys.exit(0)

if command == "mode":
    if len(args) != 3:
        die("uso: monitor-ctl.sh mode <salida> <WxH@RR|preferred|highrr|highres>")
    output, mode_arg = args[1], args[2]
    if mode_arg not in SYMBOLIC_MODES and not MODE_ARG_RE.match(mode_arg):
        die("modo invalido: %s (formato WxH@RR o preferred/highrr/highres)" % mode_arg)
    rules, primary, secondary, primary_ws = parse_managed(MONITORS_LUA)
    live = read_live()
    if output not in live:
        die("salida no conectada o inactiva: " + output)
    adopted = adopt_output(rules, live, output)
    current = live[output]
    old_stored = rules[output]["mode"]
    if mode_arg in SYMBOLIC_MODES:
        new_mode = mode_arg
        # No se puede saber cual resolera "preferred" sin leer el EDID: se
        # aplica siempre y se verifica que el resultado sea un modo valido.
        same_live = False
    else:
        parsed = MODE_ARG_RE.match(mode_arg)
        new_mode = pick_available_mode(
            current, int(parsed.group(1)), int(parsed.group(2)), float(parsed.group(3)), mode_arg)
        same_live = mode_matches(current, new_mode)
    same_stored = old_stored == new_mode
    if same_live and same_stored and not adopted:
        note("%s ya esta en %s (sin cambios)" % (output, new_mode))
        sys.exit(0)
    rules[output]["mode"] = new_mode
    changes = prepare_changes(primary, secondary, rules, primary_ws)
    prev = []

    def check_mode(live_now, output=output, new_mode=new_mode):
        mon = live_now.get(output)
        return bool(mon and mode_matches(mon, new_mode))

    if not same_live:
        prev_mode = (live_mode(current) if live_mode_supported(current)
                     else best_safe_mode(current, old_stored))
        prev = [(output, prev_mode, live_position(current), current["scale"])]
        apply_and_verify(
            [(output, new_mode, live_position(current), current["scale"])],
            prev, check_mode, "%s en modo %s" % (output, new_mode))
    written = write_or_rollback(changes, prev, "%s mode=%s" % (output, new_mode))
    note("%s mode=%s%s (%s; %s)" % (
        output, new_mode,
        " (salida adoptada)" if adopted else "",
        "aplicado en vivo" if not same_live else "en vivo ya estaba",
        "persistido en " + written if changes else "sin cambios en ficheros"))
    sys.exit(0)

if command == "scale":
    if len(args) != 3:
        die("uso: monitor-ctl.sh scale <salida> <factor>")
    output, scale_arg = args[1], args[2]
    if not SCALE_RE.match(scale_arg):
        die("escala no numerica: " + scale_arg)
    factor = round(float(scale_arg), 2)
    if not (SCALE_MIN <= factor <= SCALE_MAX):
        die("escala fuera de rango [%s, %s]: %s" % (SCALE_MIN, SCALE_MAX, scale_arg))
    rules, primary, secondary, primary_ws = parse_managed(MONITORS_LUA)
    live = read_live()
    if output not in live:
        die("salida no conectada o inactiva: " + output)
    adopted = adopt_output(rules, live, output)
    current = live[output]
    old_stored = rules[output]["mode"]
    live_ok = live_mode_supported(current)
    target_mode = live_mode(current) if live_ok else best_safe_mode(current, old_stored)
    mode_fixed = not live_ok
    # Si el modo guardado era exacto y no existe en el EDID, se corrige al
    # mismo tiempo que la escala; si era simbolico, se conserva el simbolo.
    stored_fixed = (old_stored not in SYMBOLIC_MODES
                    and not mode_is_supported(current, old_stored))
    if stored_fixed:
        rules[output]["mode"] = target_mode
    same_live = abs(float(current["scale"]) - factor) <= 0.01 and not mode_fixed
    same_stored = abs(rules[output]["scale"] - factor) <= 0.005
    if same_live and same_stored and not stored_fixed and not adopted:
        note("%s ya usa escala %s (sin cambios)" % (output, fmt_scale(factor)))
        sys.exit(0)
    rules[output]["scale"] = factor
    changes = prepare_changes(primary, secondary, rules, primary_ws)
    prev = []

    def check_scale(live_now, output=output, factor=factor, mode_fixed=mode_fixed,
                    target_mode=target_mode):
        mon = live_now.get(output)
        if not (mon and abs(float(mon["scale"]) - factor) <= 0.01):
            return False
        return not mode_fixed or mode_matches(mon, target_mode)

    if not same_live:
        prev = [(output, target_mode, live_position(current), current["scale"])]
        apply_and_verify(
            [(output, target_mode, live_position(current), factor)],
            prev, check_scale, "%s con escala %s" % (output, fmt_scale(factor)))
    written = write_or_rollback(changes, prev, "%s scale=%s" % (output, fmt_scale(factor)))
    note("%s scale=%s%s%s (%s; %s)" % (
        output, fmt_scale(factor),
        ", modo corregido a " + target_mode if mode_fixed
        else (", modo guardado corregido a " + target_mode if stored_fixed else ""),
        " (salida adoptada)" if adopted else "",
        "aplicado en vivo" if not same_live else "en vivo ya estaba",
        "persistido en " + written if changes else "sin cambios en ficheros"))
    sys.exit(0)

if command == "primary":
    if len(args) != 2:
        die("uso: monitor-ctl.sh primary [salida]")
    output = args[1]
    rules, primary, secondary, primary_ws = parse_managed(MONITORS_LUA)
    live = read_live()
    if output not in live:
        die("salida no conectada o inactiva: " + output)
    adopted = adopt_output(rules, live, output)
    if output == primary:
        other = secondary
    elif output == secondary:
        other = primary
    else:
        # Salida recien adoptada: pasa a principal y la principal actual baja
        # a secundaria. La secundaria anterior queda como regla extra.
        other = primary
    target = live[output]
    other_mon = live.get(other)
    target_old_stored = rules[output]["mode"]
    target_mode = (live_mode(target) if live_mode_supported(target)
                   else best_safe_mode(target, target_old_stored))
    if (target_old_stored not in SYMBOLIC_MODES
            and not mode_is_supported(target, target_old_stored)):
        rules[output]["mode"] = target_mode
    other_mode = None
    if other in rules and other_mon is not None:
        other_old_stored = rules[other]["mode"]
        other_mode = (live_mode(other_mon) if live_mode_supported(other_mon)
                      else best_safe_mode(other_mon, other_old_stored))
        if (other_old_stored not in SYMBOLIC_MODES
                and not mode_is_supported(other_mon, other_old_stored)):
            rules[other]["mode"] = other_mode
    mode_fixed = (not live_mode_supported(target)
                  or (other_mon is not None and not live_mode_supported(other_mon)))
    already = (target["x"] == 0 and target["y"] == 0 and not mode_fixed
               and (other_mon is None or other_mon["x"] != 0 or other_mon["y"] != 0))
    rules[output]["position"] = "0x0"
    if other in rules:
        rules[other]["position"] = "auto"
    changes = prepare_changes(output, other, rules, primary_ws)
    if already and primary == output and not changes and not adopted:
        note("%s ya es la principal (sin cambios)" % output)
        sys.exit(0)
    prev = [(output, target_mode, live_position(target), target["scale"])]
    desired = [(output, target_mode, "0x0", target["scale"])]
    if other_mon is not None:
        prev.insert(0, (other, other_mode, live_position(other_mon), other_mon["scale"]))
        desired.insert(0, (other, other_mode, "auto", other_mon["scale"]))

    def check_primary(live_now, output=output, other=other, other_was_live=other_mon is not None,
                      mode_fixed=mode_fixed, target_mode=target_mode, other_mode=other_mode):
        tgt = live_now.get(output)
        if not (tgt and tgt["x"] == 0 and tgt["y"] == 0):
            return False
        if mode_fixed and not mode_matches(tgt, target_mode):
            return False
        if other_was_live:
            oth = live_now.get(other)
            if not (oth and (oth["x"] != 0 or oth["y"] != 0)):
                return False
            if mode_fixed and other_mode is not None and not mode_matches(oth, other_mode):
                return False
        return True

    live_changed = not already or adopted
    if live_changed:
        apply_and_verify(desired, prev, check_primary, "%s como principal" % output)
    written = write_or_rollback(changes, prev if live_changed else [], "%s principal" % output)
    note("principal=%s (0x0, escritorios 1-%d); %s -> auto (escritorio %d)%s (%s; %s)" % (
        output, primary_ws, other, primary_ws + 1,
        " (salida adoptada)" if adopted else "",
        "aplicado en vivo" if live_changed else "en vivo ya estaba",
        "persistido en " + written if changes else "sin cambios en ficheros"))
    sys.exit(0)

if command == "reconcile":
    quiet = "--quiet" in args[1:]
    unknown = [arg for arg in args[1:] if arg != "--quiet"]
    if unknown:
        die("uso: monitor-ctl.sh reconcile [--quiet]")
    rules, primary, secondary, primary_ws = parse_managed(MONITORS_LUA)
    live = read_live()
    desired = []
    prev = []
    fixed = []
    adopted_any = False
    for output in sorted(live):
        mon = live[output]
        if (mon.get("disabled") or int(mon.get("width") or 0) <= 0
                or int(mon.get("height") or 0) <= 0):
            continue
        if adopt_output(rules, live, output):
            adopted_any = True
        rule = rules[output]
        stored_invalid = (rule["mode"] not in SYMBOLIC_MODES
                          and not mode_is_supported(mon, rule["mode"]))
        safe = best_safe_mode(mon, rule["mode"])
        if stored_invalid:
            rule["mode"] = safe
        if not live_mode_supported(mon):
            desired.append((output, safe, rule["position"], rule["scale"]))
            prev.append((output, safe, live_position(mon), mon["scale"]))
            fixed.append("%s: %s -> %s" % (output, live_mode(mon), safe))
    changes = prepare_changes(primary, secondary, rules, primary_ws)
    if not desired and not changes:
        if not quiet:
            note("todos los monitores conectados usan modos soportados (sin cambios)")
        sys.exit(0)
    if desired:
        def check_reconcile(live_now, desired=desired):
            for output, mode, _position, _scale in desired:
                mon = live_now.get(output)
                if not mon or not mode_matches(mon, mode):
                    return False
            return True

        apply_and_verify(desired, prev, check_reconcile, "reconcile de monitores")
    written = write_or_rollback(changes, prev, "reconcile de monitores")
    if not quiet:
        for line in fixed:
            note("modo corregido " + line)
        if adopted_any:
            note("salidas nuevas adoptadas en el bloque gestionado")
        if changes:
            note("reconcile completado; persistido en " + written)
        else:
            note("reconcile completado; sin cambios en ficheros")
    sys.exit(0)


die("orden desconocida: " + command)
PY
