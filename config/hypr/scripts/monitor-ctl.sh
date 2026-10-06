#!/usr/bin/env bash
# monitor-ctl.sh — gestion de monitores en Hyprland 0.55 (config Lua).
#
# Uso:
#   monitor-ctl.sh mode <salida> <WxH@RR>   -> p.ej. mode eDP-1 2880x1800@90.00
#   monitor-ctl.sh scale <salida> <factor>  -> p.ej. scale DP-1 1.0
#   monitor-ctl.sh primary <salida>         -> hace principal esa salida (0x0, escritorios fijos del principal)
#   monitor-ctl.sh primary                  -> imprime SOLO la salida principal actual
#
# Aplica en vivo con `hyprctl eval` (hl.monitor) usando el modo/posicion/escala
# vigentes de cada salida, y persiste el bloque gestionado en:
#   ~/.config/hypr/monitors.lua        (obligatorio)
#
# Cualquier salida conectada que no este en el bloque se adopta
# automaticamente con su estado en vivo (al cambiar de puerto, p.ej.
# DP-3 <-> HDMI-A-1, no hay que editar nombres a mano).
#
# El modo se valida contra availableModes de la salida (hyprctl -j monitors).
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
RULE_RE = re.compile(
    r'^[ \t]*hl\.monitor\(\{\s*output\s*=\s*"([^"]+)"\s*,\s*mode\s*=\s*"([^"]+)"\s*,\s*'
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
    if len(rules) < 2:
        die("el bloque gestionado de %s tiene menos de 2 salidas" % path)
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


def adopt_output(rules, live, output):
    # Salida conectada que no esta en el bloque gestionado: se adopta con su
    # estado en vivo (no mueve nada) para poder gestionarla sin editar nombres.
    if output in rules:
        return False
    mon = live[output]
    if mon.get("disabled") or int(mon.get("width") or 0) <= 0 or int(mon.get("height") or 0) <= 0:
        die("salida desactivada o sin modo activo: %s (no se puede adoptar)" % output)
    rules[output] = {
        "mode": live_mode(mon),
        "position": live_position(mon),
        "scale": float(mon.get("scale") or 1.0),
    }
    return True


def parse_mode(mode):
    parsed = MODE_ARG_RE.match(mode)
    return int(parsed.group(1)), int(parsed.group(2)), float(parsed.group(3))


def pick_available_mode(mon, want_w, want_h, want_rr, raw):
    candidates = []
    for entry in mon.get("availableModes") or []:
        parsed = AVAIL_MODE_RE.match(entry)
        if not parsed:
            continue
        width, height, rate = int(parsed.group(1)), int(parsed.group(2)), float(parsed.group(3))
        if width == want_w and height == want_h and abs(rate - want_rr) <= 0.005:
            candidates.append((entry[:-2], rate))
    if not candidates:
        die("modo no disponible en %s: %s (mira availableModes con 'hyprctl -j monitors')"
            % (mon["name"], raw))
    candidates.sort(key=lambda item: (abs(item[1] - want_rr), item[0]))
    return candidates[0][0]


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


def apply_and_verify(desired, prev, check, what):
    ensure_scale_checks()
    for timeout in (2.5, 1.5):
        for output, mode, position, scale in desired:
            eval_monitor(output, mode, position, scale)
        current = wait_for(check, timeout)
        if check(current):
            return
    try:
        for output, mode, position, scale in prev:
            eval_monitor(output, mode, position, scale)
    except SystemExit:
        pass
    die("no pude confirmar %s; intente revertir en vivo (revisa 'hyprctl monitors')" % what)


# --- comandos -------------------------------------------------------------

args = sys.argv[1:]
if not args:
    die("uso: monitor-ctl.sh {mode <salida> <WxH@RR> | scale <salida> <factor> | primary [salida]}")

command = args[0]

if command == "primary" and len(args) == 1:
    _rules, primary, _secondary, _ws = parse_managed(MONITORS_LUA)
    print(primary)
    sys.exit(0)

if command == "mode":
    if len(args) != 3:
        die("uso: monitor-ctl.sh mode <salida> <WxH@RR>")
    output, mode_arg = args[1], args[2]
    parsed = MODE_ARG_RE.match(mode_arg)
    if not parsed:
        die("modo invalido: %s (formato WxH@RR, p.ej. 2880x1800@90.00)" % mode_arg)
    rules, primary, secondary, primary_ws = parse_managed(MONITORS_LUA)
    live = read_live()
    if output not in live:
        die("salida no conectada o inactiva: " + output)
    adopted = adopt_output(rules, live, output)
    current = live[output]
    want_w, want_h, want_rr = int(parsed.group(1)), int(parsed.group(2)), float(parsed.group(3))
    new_mode = pick_available_mode(current, want_w, want_h, want_rr, mode_arg)
    mode_w, mode_h, mode_rr = parse_mode(new_mode)
    same_live = (current["width"] == mode_w and current["height"] == mode_h
                 and abs(float(current["refreshRate"]) - mode_rr) <= 0.02)
    same_stored = rules[output]["mode"] == new_mode
    if same_live and same_stored and not adopted:
        note("%s ya esta en %s (sin cambios)" % (output, new_mode))
        sys.exit(0)
    rules[output]["mode"] = new_mode
    changes = prepare_changes(primary, secondary, rules, primary_ws)
    prev = []

    def check_mode(live_now, output=output, mode_w=mode_w, mode_h=mode_h, mode_rr=mode_rr):
        mon = live_now.get(output)
        return bool(mon and mon["width"] == mode_w and mon["height"] == mode_h
                    and abs(float(mon["refreshRate"]) - mode_rr) <= 0.02)

    if not same_live:
        prev = [(output, live_mode(current), live_position(current), current["scale"])]
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
    same_live = abs(float(current["scale"]) - factor) <= 0.01
    same_stored = abs(rules[output]["scale"] - factor) <= 0.005
    if same_live and same_stored and not adopted:
        note("%s ya usa escala %s (sin cambios)" % (output, fmt_scale(factor)))
        sys.exit(0)
    rules[output]["scale"] = factor
    changes = prepare_changes(primary, secondary, rules, primary_ws)
    prev = []

    def check_scale(live_now, output=output, factor=factor):
        mon = live_now.get(output)
        return bool(mon and abs(float(mon["scale"]) - factor) <= 0.01)

    if not same_live:
        prev = [(output, live_mode(current), live_position(current), current["scale"])]
        apply_and_verify(
            [(output, live_mode(current), live_position(current), factor)],
            prev, check_scale, "%s con escala %s" % (output, fmt_scale(factor)))
    written = write_or_rollback(changes, prev, "%s scale=%s" % (output, fmt_scale(factor)))
    note("%s scale=%s%s (%s; %s)" % (
        output, fmt_scale(factor),
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
    already = (target["x"] == 0 and target["y"] == 0
               and (other_mon is None or other_mon["x"] != 0 or other_mon["y"] != 0))
    rules[output]["position"] = "0x0"
    if other in rules:
        rules[other]["position"] = "auto"
    changes = prepare_changes(output, other, rules, primary_ws)
    if already and primary == output and not changes and not adopted:
        note("%s ya es la principal (sin cambios)" % output)
        sys.exit(0)
    prev = [(output, live_mode(target), live_position(target), target["scale"])]
    desired = [(output, live_mode(target), "0x0", target["scale"])]
    if other_mon is not None:
        prev.insert(0, (other, live_mode(other_mon), live_position(other_mon), other_mon["scale"]))
        desired.insert(0, (other, live_mode(other_mon), "auto", other_mon["scale"]))

    def check_primary(live_now, output=output, other=other, other_was_live=other_mon is not None):
        tgt = live_now.get(output)
        if not (tgt and tgt["x"] == 0 and tgt["y"] == 0):
            return False
        if other_was_live:
            oth = live_now.get(other)
            return bool(oth and (oth["x"] != 0 or oth["y"] != 0))
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

die("orden desconocida: " + command)
PY
