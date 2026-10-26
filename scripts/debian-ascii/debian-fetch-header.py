#!/usr/bin/env python3
"""
Cabecera persistente con el logo Debian ASCII animado y la información de
fastfetch.

El script dibuja una cabecera (logo a la izquierda, info a la derecha) y deja
el resto de la terminal para el prompt y los comandos. La cabecera no está
fijada: se pausa cuando zsh va a ejecutar un comando y sube con el scroll como
cualquier otra línea. Por defecto usa siempre el logo pequeño de 22×13; los
artes mayores solo se usan si se pasan con --art.

Uso principal (lo hace ~/.zshrc):
    debian-fetch-header.py --fallback

Control manual:
    debian-fetch-header.py --pause
    debian-fetch-header.py --resume
    debian-fetch-header.py --stop
    debian-fetch-header.py --status

Pruebas:
    debian-fetch-header.py --no-fork --seconds 1
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import os
import re
import shlex
import signal
import struct
import subprocess
import sys
import termios
import time
import traceback
from pathlib import Path

RESET = "\x1b[0m"
SYNC_START = "\x1b[?2026h"
SYNC_END = "\x1b[?2026l"
CURSOR_SAVE = "\x1b7"
CURSOR_RESTORE = "\x1b8"
CLEAR_SCREEN = "\x1b[2J\x1b[H"

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
RAMP = " .:-=+*#%@"

DEFAULT_ART = Path(__file__).with_name("debian_small_22x13.txt")
# Tamaño fijo por defecto: el logo pequeño de siempre. Los artes mediano y
# grande siguen disponibles, pero solo si se pasan explícitamente con --art.
ART_CANDIDATES = ((DEFAULT_ART, 0),)
DEFAULT_FPS = 12.0
FRAMES = 31
MIN_INFO_WIDTH = 45
MIN_SHELL_ROWS = 10
BASE_RGB = (168, 0, 48)  # #A80030, rojo oficial del logo Debian


def visible_len(text: str) -> int:
    return len(ANSI_RE.sub("", text))


def truncate_visible(text: str, width: int) -> str:
    """Recorta a `width` columnas visibles conservando las secuencias ANSI."""
    if width <= 0:
        return ""
    if visible_len(text) <= width:
        return text
    out: list[str] = []
    used = 0
    pos = 0
    while pos < len(text):
        match = ANSI_RE.match(text, pos)
        if match:
            out.append(match.group())
            pos = match.end()
            continue
        if used >= width:
            break
        out.append(text[pos])
        used += 1
        pos += 1
    out.append(RESET)
    return "".join(out)


def pad_visible(text: str, width: int) -> str:
    return text + " " * max(0, width - visible_len(text))


def write_tty(data: str | bytes) -> None:
    if isinstance(data, str):
        data = data.encode()
    view = memoryview(data)
    while view:
        try:
            written = os.write(sys.stdout.fileno(), view)
        except OSError as exc:
            if exc.errno == errno.EINTR:
                continue
            if exc.errno not in (errno.EIO, errno.EBADF, errno.EPIPE):
                raise
            return
        if written <= 0:
            return
        view = view[written:]


def rgb_sgr(rgb: tuple[int, int, int]) -> str:
    return f"\x1b[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m"


def mix(rgb: tuple[int, int, int], target: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(int(round(c + (t - c) * amount)) for c, t in zip(rgb, target))


def parse_rgb(value: str) -> tuple[int, int, int]:
    parts = [int(p.strip()) for p in value.split(",")]
    if len(parts) != 3 or any(p < 0 or p > 255 for p in parts):
        raise argparse.ArgumentTypeError("usa R,G,B entre 0 y 255")
    return parts[0], parts[1], parts[2]


def default_runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))


def tty_tag() -> str:
    """Identificador estable por terminal, para no compartir el pidfile."""
    try:
        tty = os.ttyname(1)
    except OSError:
        tty = "notty"
    tag = tty.strip("/").replace("/", "_")
    return tag or "notty"


def default_pidfile() -> Path:
    return default_runtime_dir() / f"debian-fetch-header-{tty_tag()}-{os.getuid()}.pid"


def default_logfile() -> Path:
    return default_runtime_dir() / f"debian-fetch-header-{tty_tag()}-{os.getuid()}.log"


def read_pid(pidfile: Path) -> int | None:
    try:
        raw = pidfile.read_text().strip()
        pid = int(raw)
    except (OSError, ValueError):
        return None
    return pid if pid > 1 else None


def pid_is_ours(pid: int) -> bool:
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return False
    return "debian-fetch-header.py" in cmdline


def living_pid(pidfile: Path) -> int | None:
    pid = read_pid(pidfile)
    if pid is None:
        return None
    if pid_is_ours(pid):
        return pid
    return None


def load_art(path: Path) -> list[str]:
    lines = [line.rstrip() for line in path.read_text().splitlines()]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    if not lines:
        raise ValueError(f"el arte está vacío: {path}")
    return lines


def clean_info(lines: list[str]) -> list[str]:
    lines = [line.rstrip() for line in lines]
    while lines and visible_len(lines[0]) == 0:
        lines.pop(0)
    while lines and visible_len(lines[-1]) == 0:
        lines.pop()
    return lines


def detect_terminal() -> str | None:
    """Nombre de terminal para --terminal-format, según el entorno."""
    env = os.environ
    if env.get("KITTY_WINDOW_ID"):
        return "kitty"
    if env.get("WEZTERM_PANE"):
        return "wezterm"
    if env.get("ALACRITTY_WINDOW_ID"):
        return "alacritty"
    if env.get("KONSOLE_VERSION"):
        return "konsole"
    if env.get("GNOME_TERMINAL_SCREEN"):
        return "gnome-terminal"
    return env.get("TERM_PROGRAM") or None


def detect_shell() -> str | None:
    """Nombre del shell interactivo, no el proceso python3 que lanza fastfetch."""
    shell = Path(os.environ.get("SHELL", "")).name
    return shell or None


def run_fastfetch(compact_cpu: bool = False) -> list[str]:
    cmd = ["fastfetch", "--logo-type", "none", "--pipe", "false"]
    terminal = detect_terminal()
    if terminal:
        cmd += ["--terminal-format", terminal]
    shell = detect_shell()
    if shell:
        cmd += ["--shell-format", shell]
    if compact_cpu:
        cmd += ["--cpu-format", "{name} ({cores-logical})"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"no se pudo ejecutar fastfetch: {exc}") from exc
    if proc.returncode != 0:
        raise RuntimeError(f"fastfetch terminó con código {proc.returncode}: {proc.stderr.strip()}")
    output = proc.stdout.replace("\r\n", "\n").replace("\r", "\n")
    return clean_info(output.splitlines())


class Header:
    def __init__(
        self,
        art: list[str],
        info: list[str],
        fps: float,
        base_rgb: tuple[int, int, int],
        glitch: bool,
    ):
        self.art = art
        self.art_w = max(len(line) for line in art)
        self.art_h = len(art)
        self.info = info
        self.info_h = len(info)
        self.fps = max(1.0, fps)
        self.glitch = glitch
        self.base_rgb = base_rgb
        if base_rgb == BASE_RGB:
            self.mid_rgb = (206, 0, 86)      # #CE0056
            self.bright_rgb = (255, 77, 109)  # #FF4D6D
        else:
            self.mid_rgb = mix(base_rgb, (255, 255, 255), 0.25)
            self.bright_rgb = mix(base_rgb, (255, 255, 255), 0.55)
        self.info_col = self.art_w + 3
        self.full_info_w = max((visible_len(line) for line in info), default=0)
        self.rows = 0
        self.cols = 0
        self.content_h = 0
        self.header_h = 0
        self.scroll_top = 0
        self.logo_top = 0
        self.info_w = 0
        self.ok = False
        self.paused = False
        self.dirty = False
        self.stop = False
        self.frame = 0
        self.frame_count = FRAMES
        self.logfile: Path | None = None
        self.pidfile: Path | None = None
        self.art_candidates = ART_CANDIDATES
        self._drawn_header_h = 0

    # ---------- terminal ----------

    @staticmethod
    def get_size() -> tuple[int, int]:
        try:
            packed = fcntl.ioctl(1, termios.TIOCGWINSZ, b"\0" * 8)
            rows, cols, _, _ = struct.unpack("HHHH", packed)
            if rows and cols:
                return rows, cols
        except OSError:
            pass
        try:
            size = os.get_terminal_size(1)
            if size.lines and size.columns:
                return size.lines, size.columns
        except OSError:
            pass
        return 24, 80

    def wait_for_size(self, timeout: float = 0.6) -> tuple[int, int]:
        """Hyprland/kitty pueden reportar 80x24 durante el arranque."""
        rows, cols = self.get_size()
        if (rows, cols) != (24, 80):
            return rows, cols
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            time.sleep(0.03)
            rows, cols = self.get_size()
            if (rows, cols) != (24, 80):
                break
        return rows, cols

    def set_art(self, art: list[str]) -> None:
        self.art = art
        self.art_w = max(len(line) for line in art)
        self.art_h = len(art)
        self.info_col = self.art_w + 3

    def adapt_art(self, candidates=ART_CANDIDATES) -> bool:
        """Vuelve a aplicar el arte fijo tras un redimensionado."""
        _rows, cols = self.get_size()
        for path, min_cols in candidates:
            if cols < min_cols or not path.exists():
                continue
            art = load_art(path)
            probe = Header(art, self.info, self.fps, self.base_rgb, self.glitch)
            if not probe.layout():
                continue
            self.set_art(art)
            return self.layout()
        return False

    def layout(self) -> bool:
        self.rows, self.cols = self.wait_for_size()
        self.content_h = max(self.art_h, self.info_h)
        self.header_h = self.content_h + 1
        self.scroll_top = self.header_h + 1
        available_info_w = self.cols - self.info_col + 1
        self.info_w = min(self.full_info_w, available_info_w)
        self.logo_top = 1 + max(0, (self.content_h - self.art_h) // 2)
        self.ok = (
            bool(self.info)
            and self.full_info_w > 0
            and available_info_w >= MIN_INFO_WIDTH
            and self.cols - self.info_col + 1 >= MIN_INFO_WIDTH
            and self.rows - self.header_h >= MIN_SHELL_ROWS
        )
        return self.ok

    # ---------- dibujo ----------

    def color_for(self, row: int) -> str:
        highlight = (self.frame * self.art_h) // self.frame_count
        if row == highlight:
            color = self.bright_rgb
        elif row == highlight - 1:
            color = self.mid_rgb
        else:
            color = self.base_rgb
        return rgb_sgr(color)

    def glitch_line(self, line: str, row: int) -> str:
        if not self.glitch:
            return line
        highlight = (self.frame * self.art_h) // self.frame_count
        if row != highlight:
            return line
        chars = list(line.ljust(self.art_w))
        # Un único carácter cambia de densidad al paso de la línea.
        col = (self.frame * 7 + 3) % self.art_w
        for offset in range(self.art_w):
            idx = (col + offset) % self.art_w
            ch = chars[idx]
            if ch != " " and ch in RAMP:
                pos = RAMP.index(ch)
                new_pos = pos + 1 if pos < len(RAMP) - 1 else pos - 1
                chars[idx] = RAMP[max(0, new_pos)]
                break
        return "".join(chars)

    def render_logo(self) -> str:
        parts: list[str] = []
        for i, line in enumerate(self.art):
            row = self.logo_top + i
            text = self.glitch_line(line, i).ljust(self.art_w)
            parts.append(f"\x1b[{row};1H{self.color_for(i)}{text}{RESET}")
        return "".join(parts)

    def render_info(self, clear: bool) -> str:
        if not self.info:
            return ""
        parts: list[str] = []
        if clear:
            blank = " " * (self.cols - self.info_col + 1)
            for row in range(1, self.content_h + 1):
                parts.append(f"\x1b[{row};{self.info_col}H{blank}")
        for i, line in enumerate(self.info):
            row = 1 + i
            text = pad_visible(truncate_visible(line, self.info_w), self.info_w)
            parts.append(f"\x1b[{row};{self.info_col}H{text}")
        return "".join(parts)

    def clear_header(self, rows: int) -> str:
        blank = " " * self.cols
        return "".join(f"\x1b[{row};1H{blank}" for row in range(1, rows + 1))

    def setup(self) -> None:
        # La cabecera es contenido normal: no se fija una región de scroll.
        # Así, cuando la salida llena la pantalla, sube con el resto del texto.
        write_tty("\x1b[r")
        write_tty(CLEAR_SCREEN)
        write_tty(SYNC_START)
        write_tty(self.render_info(clear=False))
        write_tty(self.render_logo())
        write_tty(f"\x1b[{self.scroll_top};1H")
        write_tty(SYNC_END)
        self._drawn_header_h = self.header_h

    def redraw(self) -> None:
        # Al cambiar de arte (p. ej. al encoger la ventana) hay que borrar
        # también el área que ocupaba la cabecera anterior; si no, quedan
        # restos del logo grande debajo del pequeño.
        rows = min(max(self.header_h, self._drawn_header_h), self.rows)
        write_tty(CURSOR_SAVE + RESET)
        write_tty(SYNC_START)
        write_tty(self.clear_header(rows))
        write_tty(self.render_info(clear=False))
        write_tty(self.render_logo())
        write_tty(RESET + CURSOR_RESTORE)
        write_tty(SYNC_END)
        self._drawn_header_h = self.header_h

    def animate(self) -> None:
        write_tty(CURSOR_SAVE)
        write_tty(SYNC_START)
        write_tty(self.render_logo())
        write_tty(CURSOR_RESTORE)
        write_tty(SYNC_END)

    def cleanup(self) -> None:
        # No se borran las filas de la cabecera: ya forma parte del scrollback.
        # `clear` y Ctrl+L limpian la pantalla completa cuando hace falta.
        write_tty(CURSOR_SAVE + "\x1b[r" + CURSOR_RESTORE)
        if self.pidfile:
            try:
                self.pidfile.unlink()
            except OSError:
                pass

    def cleanup_for_fallback(self) -> None:
        write_tty("\x1b[r\x1b[2J\x1b[H")

    # ---------- ejecución ----------

    def log(self, message: str) -> None:
        if not self.logfile:
            return
        try:
            with self.logfile.open("a") as handle:
                handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
        except OSError:
            pass

    def install_signals(self) -> None:
        def pause_handler(_signum, _frame):
            self.paused = True

        def resume_handler(_signum, _frame):
            self.paused = False
            self.dirty = True

        def stop_handler(_signum, _frame):
            self.stop = True

        signal.signal(signal.SIGUSR1, pause_handler)
        signal.signal(signal.SIGUSR2, resume_handler)
        signal.signal(signal.SIGTERM, stop_handler)
        signal.signal(signal.SIGINT, stop_handler)
        signal.signal(signal.SIGQUIT, stop_handler)
        signal.signal(signal.SIGHUP, stop_handler)
        signal.signal(signal.SIGPIPE, signal.SIG_IGN)
        # El hijo vive en un grupo de proceso propio; si el terminal tuviera
        # TOSTOP activado, escribir no debe detenerlo.
        signal.signal(signal.SIGTTOU, signal.SIG_IGN)
        signal.signal(signal.SIGTTIN, signal.SIG_IGN)

    def loop(self, seconds: float = 0.0) -> None:
        started = time.monotonic()
        last_check = 0.0
        try:
            while not self.stop:
                if seconds and time.monotonic() - started >= seconds:
                    break
                if self.paused:
                    time.sleep(0.03)
                    continue
                if self.dirty:
                    if not self.layout():
                        self.log("la terminal ya no tiene tamaño suficiente; se detiene")
                        break
                    self.redraw()
                    self.dirty = False
                self.animate()
                self.frame = (self.frame + 1) % self.frame_count
                time.sleep(1.0 / self.fps)
                now = time.monotonic()
                if now - last_check >= 0.5:
                    last_check = now
                    try:
                        os.ttyname(1)
                    except OSError:
                        break
                    rows, cols = self.get_size()
                    if (rows, cols) != (self.rows, self.cols):
                        if self.art_candidates:
                            if not self.adapt_art(self.art_candidates):
                                self.log("la terminal ya no tiene tamaño suficiente; se detiene")
                                break
                        elif not self.layout():
                            self.log("la terminal ya no tiene tamaño suficiente; se detiene")
                            break
                        self.redraw()
        except Exception:
            self.log(traceback.format_exc())
        finally:
            self.cleanup()


def run_normal_fastfetch() -> int:
    try:
        return subprocess.run(["fastfetch"]).returncode
    except OSError as exc:
        print(f"debian-fetch: no se pudo ejecutar fastfetch: {exc}", file=sys.stderr)
        return 1


def signal_existing(pidfile: Path, signum: int) -> bool:
    pid = living_pid(pidfile)
    if pid is None:
        return False
    try:
        os.kill(pid, signum)
    except OSError:
        return False
    return True


def make_header(art: list[str], info: list[str], args) -> Header:
    return Header(art, info, args.fps, args.color, not args.no_glitch)


def select_header(info: list[str], args) -> Header | None:
    """Usa el arte pequeño fijo (22×13)."""
    for path, min_cols in ART_CANDIDATES:
        if not path.exists():
            continue
        art = load_art(path)
        header = make_header(art, info, args)
        _rows, cols = header.wait_for_size()
        if cols < min_cols:
            continue
        if not header.layout():
            continue
        if header.full_info_w > header.cols - header.info_col + 1:
            compact = make_header(art, run_fastfetch(compact_cpu=True), args)
            if compact.layout():
                header = compact
        return header
    return None


def stop_existing(pidfile: Path) -> None:
    pid = living_pid(pidfile)
    if pid is not None:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
        for _ in range(30):
            if not pid_is_ours(pid):
                break
            time.sleep(0.01)
    try:
        pidfile.unlink()
    except OSError:
        pass
    if sys.stdout.isatty():
        write_tty("\x1b[r")


def main() -> int:
    parser = argparse.ArgumentParser(description="Cabecera persistente con logo Debian ASCII animado y fastfetch.")
    parser.add_argument(
        "--art",
        type=Path,
        default=None,
        help="usa un arte fijo; por defecto, el pequeño 22×13",
    )
    parser.add_argument("--fps", type=float, default=DEFAULT_FPS)
    parser.add_argument("--color", type=parse_rgb, default=BASE_RGB, help="color base R,G,B (por defecto 168,0,48)")
    parser.add_argument("--no-glitch", action="store_true", help="no cambia caracteres en la línea de barrido")
    parser.add_argument("--fallback", action="store_true", help="si no cabe, ejecuta fastfetch normal")
    parser.add_argument("--pidfile", type=Path, default=default_pidfile())
    parser.add_argument("--log", type=Path, default=default_logfile())
    parser.add_argument("--pause", action="store_true", help="pausa la animación")
    parser.add_argument("--resume", action="store_true", help="reanuda la animación")
    parser.add_argument("--stop", action="store_true", help="detiene la animación y limpia la cabecera")
    parser.add_argument("--status", action="store_true", help="indica si la animación está activa")
    parser.add_argument("--restart", action="store_true", help="reinicia la animación")
    parser.add_argument("--no-fork", action="store_true", help="no crea el proceso hijo; útil para pruebas")
    parser.add_argument("--seconds", type=float, default=0.0, help="duración máxima (0 = infinita)")
    args = parser.parse_args()

    if args.stop:
        stop_existing(args.pidfile)
        return 0
    if args.pause:
        return 0 if signal_existing(args.pidfile, signal.SIGUSR1) else 0
    if args.resume:
        return 0 if signal_existing(args.pidfile, signal.SIGUSR2) else 0
    if args.status:
        pid = living_pid(args.pidfile)
        print("activa" if pid else "detenida")
        return 0 if pid else 1
    if args.restart:
        stop_existing(args.pidfile)

    existing = living_pid(args.pidfile)
    if existing is not None and not args.restart:
        try:
            os.kill(existing, signal.SIGUSR2)
        except OSError:
            pass
        return 0

    try:
        info = run_fastfetch()
        if args.art:
            # Arte fijo elegido a mano: no se adapta al redimensionar.
            art = load_art(args.art)
            header = make_header(art, info, args)
            if not header.layout():
                if args.fallback:
                    return run_normal_fastfetch()
                print(
                    f"debian-fetch: la terminal necesita al menos "
                    f"{header.info_col + MIN_INFO_WIDTH - 1} columnas y "
                    f"{header.content_h + 1 + MIN_SHELL_ROWS} filas "
                    f"(actual: {header.cols}x{header.rows}).",
                    file=sys.stderr,
                )
                return 1
            # En ventanas estrechas, quitar la frecuencia de la CPU suele
            # bastar para que la caja de información no se recorte.
            if header.full_info_w > header.cols - header.info_col + 1:
                compact_header = make_header(
                    art, run_fastfetch(compact_cpu=True), args
                )
                if compact_header.layout():
                    header = compact_header
            header.art_candidates = ()
        else:
            header = select_header(info, args)
            if header is None:
                # No cabe ni el arte pequeño: dejar que el mensaje de error
                # indique el tamaño mínimo y, si se pidió, usar fastfetch.
                header = make_header(load_art(DEFAULT_ART), info, args)
                if not header.layout():
                    if args.fallback:
                        return run_normal_fastfetch()
                    print(
                        f"debian-fetch: la terminal necesita al menos "
                        f"{header.info_col + MIN_INFO_WIDTH - 1} columnas y "
                        f"{header.content_h + 1 + MIN_SHELL_ROWS} filas "
                        f"(actual: {header.cols}x{header.rows}).",
                        file=sys.stderr,
                    )
                    return 1

        header.pidfile = args.pidfile
        header.logfile = args.log

        if args.no_fork:
            header.install_signals()
            header.setup()
            header.loop(args.seconds)
            return 0

        header.setup()
        ready_r, ready_w = os.pipe()
        try:
            pid = os.fork()
        except OSError:
            os.close(ready_r)
            os.close(ready_w)
            header.cleanup_for_fallback()
            if args.fallback:
                return run_normal_fastfetch()
            raise

        if pid == 0:
            # Hijo: crear un grupo de proceso propio para no interferir con el
            # trabajo en primer plano de zsh, avisar de que está listo y animar.
            os.close(ready_r)
            try:
                os.setpgid(0, 0)
            except OSError:
                pass
            header.install_signals()
            try:
                os.write(ready_w, b"R")
            finally:
                os.close(ready_w)
            header.loop(args.seconds)
            os._exit(0)

        # Padre: esperar a que el hijo tenga los manejadores instalados.
        os.close(ready_w)
        ready = b""
        try:
            ready = os.read(ready_r, 1)
        finally:
            os.close(ready_r)
        if ready != b"R":
            header.cleanup_for_fallback()
            if args.fallback:
                return run_normal_fastfetch()
            return 1
        try:
            args.pidfile.write_text(f"{pid}\n")
        except OSError:
            pass
        return 0
    except Exception as exc:
        if args.fallback:
            print(f"debian-fetch: {exc}; usando fastfetch normal", file=sys.stderr)
            return run_normal_fastfetch()
        print(f"debian-fetch: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
