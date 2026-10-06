#!/usr/bin/env python3
"""GPU usage for the Quickshell settings graph (Intel i915), no perf events.

nvtop/intel_gpu_top need perf events, which perf_event_paranoid=3 blocks for
unprivileged users. The i915 driver instead exposes cumulative per-client
engine busy time in /proc/<pid>/fdinfo/<fd> (drm-engine-*), readable by the
process owner. Two samples are compared and the busiest engine's busy
fraction is printed as an integer percentage.

Mirrors ~/.config/waybar/scripts/gpu_usage.py so the panel and the settings
window report the same number.
"""

import glob
import time

ENGINES = (
    "drm-engine-render",
    "drm-engine-copy",
    "drm-engine-video",
    "drm-engine-video-enhance",
)
INTERVAL = 0.5


def snapshot():
    """Map each DRM client to its per-engine busy nanoseconds."""
    clients = {}
    for path in glob.glob("/proc/[0-9]*/fdinfo/*"):
        pid = path.split("/")[2]
        cid = None
        engines = {}
        try:
            with open(path) as fh:
                for line in fh:
                    key, _, value = line.partition(":")
                    if key == "drm-client-id":
                        cid = value.strip()
                    elif key in ENGINES and value.strip().endswith("ns"):
                        engines[key] = int(value.split()[0])
        except (OSError, ValueError):
            continue
        if engines:
            # drm-client-id deduplicates fds that share the same DRM file;
            # fall back to the fd path if the kernel does not report it.
            clients[(pid, cid) if cid else (pid, path)] = engines
    return clients


def main():
    before = snapshot()
    start = time.monotonic()
    time.sleep(INTERVAL)
    after = snapshot()
    elapsed = (time.monotonic() - start) * 1e9

    busy = {}
    for key, engines in after.items():
        prev = before.get(key)
        if prev is None:  # client appeared mid-sample
            continue
        for name, ns in engines.items():
            delta = ns - prev.get(name, ns)
            if delta > 0:
                busy[name] = busy.get(name, 0) + delta

    usage = max(busy.values(), default=0) / elapsed * 100 if elapsed > 0 else 0
    print(min(100, round(usage)))


if __name__ == "__main__":
    main()
