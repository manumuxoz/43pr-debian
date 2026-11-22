#!/usr/bin/env python3
"""Battery status, history and diagnostics for the Quickshell power page."""
import argparse
import glob
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time

POWER_SUPPLY = "/sys/class/power_supply"
DEFAULT_INTERVAL = 6 * 3600
MAX_AGE_DAYS = 1095
MAX_ENTRIES = 20000
LIMIT_CHOICES = (60, 80, 100)
STATUS_VALUES = {"Discharging", "Charging", "Full", "Not charging", "Unknown"}
def read_text(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except (OSError, UnicodeError):
        return None
def read_int(path):
    try: return int(read_text(path) or "")
    except ValueError: return None
def safe_float(value):
    if value is None or isinstance(value, bool): return None
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) else None
def find_battery():
    found = []
    for path in sorted(glob.glob(os.path.join(POWER_SUPPLY, "*"))):
        present = read_text(os.path.join(path, "present"))
        if read_text(os.path.join(path, "type")) == "Battery" and present == "1":
            found.append(path)
    return min(found, key=lambda p: (os.path.basename(p) != "BAT0", p), default=None)
def find_ac():
    preferred = os.path.join(POWER_SUPPLY, "ADP1")
    candidates = [preferred] if os.path.isdir(preferred) else []
    candidates += [p for p in sorted(glob.glob(os.path.join(POWER_SUPPLY, "*")))
                   if p != preferred and read_text(os.path.join(p, "type")) in ("Mains", "USB")]
    return any(read_text(os.path.join(p, "online")) == "1" for p in candidates)
def find_binary(name):
    candidates = (shutil.which(name), f"/usr/sbin/{name}", f"/sbin/{name}")
    return next((path for path in candidates if path and os.access(path, os.X_OK)), None)
def battery_voltage(device):
    for name in ("voltage_now", "voltage_min_design"):
        raw = read_int(os.path.join(device, name))
        if raw is not None and raw > 0:
            return raw / 1_000_000
    return None
def capacity_ah(device, field, voltage):
    raw = read_int(os.path.join(device, "charge_" + field))
    if raw is not None:
        return raw / 1_000_000
    raw = read_int(os.path.join(device, "energy_" + field))
    return (raw / 1_000_000) / voltage if raw is not None and voltage else None
def battery_temperature(device):
    for path in sorted(glob.glob(os.path.join(device, "hwmon*", "temp*_input"))):
        raw = read_int(path)
        if raw:
            return round(raw / 1000, 1)
    return None
def time_estimate(device, status, now_ah, full_ah, current_a, charging):
    if status != ("Charging" if charging else "Discharging") or not current_a or current_a <= 0:
        return None
    keys = ("time_to_full_now", "time_to_full_avg") if charging else ("time_to_empty_now", "time_to_empty_avg")
    for key in keys:
        seconds = read_int(os.path.join(device, key))
        if seconds is not None and seconds > 0:
            return round(seconds / 60)
    if charging:
        return round(max(0.0, full_ah - now_ah) / current_a * 60) if full_ah is not None and now_ah is not None else None
    return round(now_ah / current_a * 60) if now_ah is not None else None
def collect_status():
    device = find_battery()
    if device is None:
        return None
    voltage = battery_voltage(device)
    status = read_text(os.path.join(device, "status")) or "Unknown"
    if status not in STATUS_VALUES:
        status = "Unknown"

    raw_current = read_int(os.path.join(device, "current_now"))
    current = abs(raw_current) / 1_000_000 if raw_current is not None else None
    raw_power = read_int(os.path.join(device, "power_now"))
    power = (abs(voltage * current) if voltage is not None and current is not None
             else abs(raw_power) / 1_000_000 if raw_power is not None else None)
    if current is None and power is not None and voltage:
        current = power / voltage

    now_ah = capacity_ah(device, "now", voltage)
    full_ah = capacity_ah(device, "full", voltage)
    design_ah = capacity_ah(device, "full_design", voltage)
    health = round(full_ah / design_ah * 100, 1) if full_ah is not None and design_ah else None
    wear = round(100 - health, 1) if health is not None else None

    capacity = read_int(os.path.join(device, "capacity"))
    if capacity is None and now_ah is not None and full_ah:
        capacity = round(now_ah / full_ah * 100)
    limit_path = os.path.join(device, "charge_control_end_threshold")
    limit_supported = os.path.exists(limit_path)

    def rounded(value, digits):
        return round(value, digits) if value is not None else None

    return {
        "ok": True, "battery": os.path.basename(device),
        "manufacturer": read_text(os.path.join(device, "manufacturer")) or "Unknown",
        "model": read_text(os.path.join(device, "model_name")) or "Unknown",
        "technology": read_text(os.path.join(device, "technology")) or "Unknown",
        "status": status, "present": True, "capacity_pct": capacity,
        "voltage_v": rounded(voltage, 3), "current_a": rounded(current, 3),
        "power_w": rounded(power, 2), "charge_now_ah": rounded(now_ah, 3),
        "charge_full_ah": rounded(full_ah, 3), "charge_full_design_ah": rounded(design_ah, 3),
        "health_pct": health, "wear_pct": wear,
        "cycles": read_int(os.path.join(device, "cycle_count")),
        "charge_limit_supported": limit_supported, "charge_limit": read_int(limit_path),
        "charge_limit_choices": list(LIMIT_CHOICES) if limit_supported else [],
        "ac_online": find_ac(),
        "time_to_empty_min": time_estimate(device, status, now_ah, full_ah, current, False),
        "time_to_full_min": time_estimate(device, status, now_ah, full_ah, current, True),
        "temp_c": battery_temperature(device),
        "energy_full_wh": rounded(full_ah * voltage, 1) if full_ah is not None and voltage else None,
        "energy_full_design_wh": rounded(design_ah * voltage, 1)
        if design_ah is not None and voltage else None,
        "energy_now_wh": rounded(now_ah * voltage, 1) if now_ah is not None and voltage else None,
    }
def history_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "43pr", "battery-history.jsonl")
def load_history(path):
    entries = []
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    entry = json.loads(line)
                except (json.JSONDecodeError, TypeError):
                    continue
                stamp = entry.get("t") if isinstance(entry, dict) else None
                if isinstance(stamp, (int, float)) and not isinstance(stamp, bool) and math.isfinite(stamp):
                    entries.append(entry)
    except FileNotFoundError:
        pass
    return entries
def write_history(path, entries):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".battery-history.", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.writelines(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n"
                              for entry in entries)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise
def coerce_sample(entry):
    sample = {"t": int(float(entry["t"]))}
    for key in ("h", "w", "full", "design"):
        sample[key] = safe_float(entry.get(key))
    for key in ("c", "p"):
        value = safe_float(entry.get(key))
        sample[key] = int(value) if value is not None else None
    sample["s"] = entry.get("s") if isinstance(entry.get("s"), str) else None
    return sample
def cmd_status(_args):
    status = collect_status()
    print(json.dumps(status or {"ok": False, "error": "no battery"}, ensure_ascii=False))
    return 0
def cmd_record(args):
    status = collect_status()
    if status is None:
        return 0
    path = history_path()
    now = int(time.time())
    try:
        entries = load_history(path)
    except OSError as error:
        print(f"No se pudo leer {path}: {error}", file=sys.stderr)
        return 1
    newest = max((float(entry["t"]) for entry in entries), default=None)
    interval = safe_float(os.environ.get("BATTERY_RECORD_INTERVAL"))
    interval = interval if interval is not None and interval >= 0 else DEFAULT_INTERVAL
    if newest is not None and now - newest < interval and not args.force:
        return 0
    entries.append({"t": now, "h": status["health_pct"], "c": status["cycles"], "p": status["capacity_pct"],
                    "w": status["power_w"], "s": status["status"], "full": status["charge_full_ah"],
                    "design": status["charge_full_design_ah"]})
    cutoff = now - MAX_AGE_DAYS * 86400
    entries = [entry for entry in entries if float(entry["t"]) >= cutoff]
    entries.sort(key=lambda entry: float(entry["t"]))
    if len(entries) > MAX_ENTRIES:
        entries = entries[-MAX_ENTRIES:]
    try:
        write_history(path, entries)
    except OSError as error:
        print(f"No se pudo escribir {path}: {error}", file=sys.stderr)
        return 1
    return 0
def cmd_history(args):
    try:
        entries = load_history(history_path())
    except OSError:
        entries = []
    if args.days is not None:
        cutoff = time.time() - args.days * 86400
        entries = [entry for entry in entries if float(entry["t"]) >= cutoff]
    entries.sort(key=lambda entry: float(entry["t"]))
    if args.limit is not None:
        entries = entries[-args.limit:] if args.limit > 0 else []
    print(json.dumps([coerce_sample(entry) for entry in entries], ensure_ascii=False))
    return 0
def run_command(argv, timeout=3):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                              check=False).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
def fmt(value, digits=1, unit="", missing="n/d"):
    return f"{value:.{digits}f}{unit}" if value is not None else missing
def minutes_text(minutes):
    if minutes is None:
        return "no disponible"
    hours, remaining = divmod(int(minutes), 60)
    return f"{hours} h {remaining:02d} min" if hours else f"{remaining} min"
def swap_summary():
    total = devices = 0
    try:
        with open("/proc/swaps", encoding="utf-8") as handle:
            next(handle, None)
            for fields in (line.split() for line in handle):
                if len(fields) >= 3 and fields[2].isdigit():
                    total += int(fields[2])
                    devices += 1
    except OSError:
        return "no disponible"
    return "ninguno" if devices == 0 else f"{total / 1024:.0f} MiB en {devices} dispositivo(s)"
def zram_summary():
    if (binary := find_binary("zramctl")) is None:
        return "no disponible (zramctl no instalado)"
    lines = [line for line in run_command([binary, "--noheadings", "--output", "NAME,DISKSIZE"]).splitlines() if line.strip()]
    return f"{len(lines)} dispositivo(s)" if lines else "ninguno"
def throttle_summary():
    def total(pattern):
        return sum(v for v in (read_int(path) for path in glob.glob(pattern)) if v is not None)
    core = total("/sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count")
    packages = [read_int(path) for path in glob.glob(
        "/sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count")]
    return core, max((v for v in packages if v is not None), default=0)
def cmd_report(_args):
    status = collect_status()
    if status is None:
        print("No se detectó ninguna batería.")
        return 0
    profile, choices = (
        read_text("/sys/firmware/acpi/platform_profile") or "n/d",
        read_text("/sys/firmware/acpi/platform_profile_choices") or "n/d",
    )
    governor, epp = (
        read_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") or "n/d",
        read_text("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference") or "n/d",
    )
    no_turbo = read_int("/sys/devices/system/cpu/intel_pstate/no_turbo")
    turbo = "n/d" if no_turbo is None else f"{'desactivado' if no_turbo else 'activado'} (no_turbo={no_turbo})"
    ppd = run_command(["systemctl", "is-active", "power-profiles-daemon"]) or "desconocido"
    thermald = ("no instalado" if find_binary("thermald") is None
                else run_command(["systemctl", "is-active", "thermald"]) or "desconocido")
    swap, zram = swap_summary(), zram_summary()
    swappiness = read_text("/proc/sys/vm/swappiness") or "n/d"
    fstrim = run_command(["systemctl", "is-active", "fstrim.timer"]) or "desconocido"
    core_throttle, package_throttle = throttle_summary()
    now, full, design = status["charge_now_ah"], status["charge_full_ah"], status["charge_full_design_ah"]
    health, wear, cycles = status["health_pct"], status["wear_pct"], status["cycles"]
    limit = status["charge_limit"]
    limit_text = fmt(limit, 0, "%") if status["charge_limit_supported"] else "no soportado"

    print(f"""Batería: {status['battery']} — {status['manufacturer']} {status['model']}
  Tecnología {status['technology']} · estado {status['status']} · presente: sí

Carga y energía
  Nivel: {fmt(status['capacity_pct'], 0, '%')}
  Carga: {fmt(now, 3, ' Ah')} / {fmt(full, 3, ' Ah')} · diseño {fmt(design, 3, ' Ah')}
  Energía: {fmt(status['energy_now_wh'], 1)} / {fmt(status['energy_full_wh'], 1, ' Wh')} · diseño {fmt(status['energy_full_design_wh'], 1, ' Wh')}
  Voltaje {fmt(status['voltage_v'], 3, ' V')} · corriente {fmt(status['current_a'], 3, ' A')} · potencia {fmt(status['power_w'], 2, ' W')}

Salud
  Salud {fmt(health, 1, '%')} · desgaste {fmt(wear, 1, '%')}
  Ciclos: {cycles if cycles is not None else 'n/d'}

Límite y autonomía
  Límite de carga: {limit_text}
  Tiempo restante: {minutes_text(status['time_to_empty_min'])}
  Tiempo para carga completa: {minutes_text(status['time_to_full_min'])}

Estado del sistema
  Perfil: {profile} ({choices})
  Gobernador: {governor} · EPP: {epp} · turbo: {turbo}
  power-profiles-daemon: {ppd} · thermald: {thermald}
  Swap: {swap} · zram: {zram}
  swappiness: {swappiness} · fstrim.timer: {fstrim}
  Throttling: {package_throttle} de paquete, {core_throttle} de núcleo

Sugerencias""")

    suggestions = []
    if status["charge_limit_supported"] and limit is not None and wear is not None:
        if limit < 100 and wear > 15:
            suggestions.append("El límite está por debajo del 100% y el desgaste supera el 15%: mantenlo en el 80% o menos para el uso diario.")
        elif limit >= 100 and wear > 15:
            suggestions.append("El desgaste supera el 15%: baja el límite de carga al 80% con «battery-health.py limit 80».")
    if not status["ac_online"] and no_turbo == 0:
        suggestions.append("El turbo está activo con batería: usa el perfil balanced o desactívalo.")
    if thermald == "no instalado":
        suggestions.append("Thermald no está instalado: instálalo con «apt install thermald».")
    if swap == "ninguno" and not glob.glob("/dev/zram*"):
        suggestions.append("No hay swap ni zram: ejecuta «sudo bash scripts/install-zram.sh» (usa systemd-zram-generator).")
    if package_throttle > 0 or core_throttle > 0:
        suggestions.append(f"Hay {package_throttle + core_throttle} eventos de throttling: revisa la refrigeración o usa un perfil más conservador en carga sostenida.")
    if fstrim != "active":
        suggestions.append("fstrim.timer no está activo: actívalo con «systemctl enable --now fstrim.timer».")
    if len(suggestions) < 3:
        if status["ac_online"] and profile != "performance":
            suggestions.append("Estás conectado a la corriente: el límite de carga protege la batería.")
        suggestions += ["Revisa el consumo con «powertop» y cierra aplicaciones en segundo plano.",
                        "Mantén la batería entre el 40% y el 80% para reducir el desgaste.",
                        "Mantén el equipo ventilado y evita bloquear las rejillas de refrigeración."]
    for suggestion in suggestions[:5]:
        print(f"  - {suggestion}")
    return 0
def cmd_limit(args):
    device = find_battery()
    path = os.path.join(device, "charge_control_end_threshold") if device else None
    supported = bool(path and os.path.exists(path))
    if args.value is None:
        current = read_int(path) if supported else None
        print(current if current is not None else "unsupported")
        return 0
    if args.value not in LIMIT_CHOICES:
        print(f"Valor no válido: {args.value}. Usa 60, 80 o 100.", file=sys.stderr)
        return 2
    if not supported:
        print("Límite de carga no soportado en esta batería.", file=sys.stderr)
        return 1
    try:
        result = subprocess.run(["sudo", "-n", "/usr/bin/tee", path], input=f"{args.value}\n",
                                capture_output=True, text=True, timeout=10, check=False)
    except (OSError, subprocess.SubprocessError) as error:
        print(f"No se pudo ejecutar sudo: {error}", file=sys.stderr)
        return 1
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        missing = any(word in detail.lower() for word in ("password", "sudoers", "tty"))
        reason = (f"falta una regla sudoers NOPASSWD para /usr/bin/tee {path}"
                  if missing else detail or "error de sudo")
        print(f"No se pudo escribir el límite: {reason}", file=sys.stderr)
        return 1
    if (actual := read_int(path)) != args.value:
        print(f"La escritura no se aplicó: se leyó {actual} en lugar de {args.value}.", file=sys.stderr)
        return 1
    print(f"Límite de carga establecido en {actual}%.")
    return 0
def nonnegative(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("debe ser un entero no negativo")
    return number
def main():
    parser = argparse.ArgumentParser(description="Estado e historial de la batería.")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("status")
    sub.add_parser("record").add_argument("--force", action="store_true")
    history = sub.add_parser("history")
    history.add_argument("--days", type=nonnegative, default=None)
    history.add_argument("--limit", type=nonnegative, default=None)
    sub.add_parser("report")
    sub.add_parser("limit").add_argument("value", nargs="?", type=int)
    args = parser.parse_args()
    commands = {"status": cmd_status, "record": cmd_record, "history": cmd_history,
                "report": cmd_report, "limit": cmd_limit}
    if args.command not in commands:
        parser.print_help()
        return 2
    return commands[args.command](args)

if __name__ == "__main__":
    sys.exit(main())
