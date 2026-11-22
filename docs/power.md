# Power, battery health and performance

This page covers the battery-health tools added to Quickshell, the optional
zram setup and the read-only performance audit. Everything here is optional:
the desktop works without it.

## Settings → Power

The Power page (second entry in the settings sidebar) shows:

- **Charge and runtime** — percentage, charging state, battery voltage,
  current, power draw and time to empty/full.
- **Battery health** — `charge_full / charge_full_design`, wear, cycle count
  and the resulting capacity in Ah/Wh. Grades: `EXCELLENT` ≥ 90 %,
  `GOOD` ≥ 80 %, `FAIR` ≥ 70 %, `POOR` below that.
- **Health history** — a sample is written every six hours while the session
  is running to `~/.local/state/43pr/battery-history.jsonl` (three-year
  retention). The graph plots the last 180 days.
- **Charge limit** — 60 %, 80 % or 100 % on batteries that expose
  `charge_control_end_threshold` (ASUS Battery Health Charging). 60–80 %
  significantly slows wear if the laptop is usually plugged in; 100 % keeps
  the longest runtime.
- **Battery power graph** — the last three minutes of pack power, sampled every
  three seconds while the page is open.
- **Performance** — Turbo Boost on/off, current governor, energy-performance
  preference, ACPI platform profile, power-profiles-daemon state, package
  temperature, fan (if the firmware exposes it), package throttle events since
  boot and the swap/zram devices.

The CPU profile itself stays in **Settings → System → CPU MODE**, together with
the live CPU/GPU/RAM graphs. CPU MODE writes the ACPI `platform_profile`
(firmware power limits and fan policy); Linux keeps the `powersave` governor
and `balance_performance` EPP, which still scales to the maximum turbo clock on
demand. Turbo Boost is the separate hardware on/off switch above.

The charge limit and the Turbo choice are stored in
`~/.config/quickshell/state/power.json`. `PowerAgent` (a small Quickshell
component) re-applies them on the next shell start and writes the six-hour
health samples even if the page is never opened.

### One-time privileged setup

The charge limit and Turbo toggle write sysfs files. Install the narrow
sudoers rule once:

```bash
sudo bash scripts/install-power-sudoers.sh
```

It allows exactly three writes through `sudo -n /usr/bin/tee`:
`platform_profile`, `intel_pstate/no_turbo` and
`BAT0/charge_control_end_threshold`. The kernel still validates the values.
Re-run it after updating from a release that used
`install-cpu-profile-sudoers.sh`; the old rule is removed automatically.

Waybar's battery module opens the page on click.

## Battery-health CLI

The same data is available from a terminal:

```bash
~/.config/quickshell/scripts/battery-health.py status   # JSON
~/.config/quickshell/scripts/battery-health.py history --days 30
~/.config/quickshell/scripts/battery-health.py record --force
~/.config/quickshell/scripts/battery-health.py report   # Spanish summary
~/.config/quickshell/scripts/battery-health.py limit    # current threshold
~/.config/quickshell/scripts/battery-health.py limit 80 # needs the sudoers rule
```

`status` is the stable interface used by the GUI; `report` adds a system
section (governor, platform profile, Turbo, PPD, swap/zram) and suggestions.

## Read-only performance audit

```bash
./tools/power-audit.sh
```

It reports battery wear and charge limit, CPU governor/EPP/profile, Turbo,
memory pressure, swap/zram, boot time and the slowest units, thermal throttling
and optional tooling (`thermald`, `powertop`, `irqbalance`, `tlp`, `tuned`).
It prints concrete commands but changes nothing. `tools/doctor.sh` includes a
compact version of the same checks.

## zram (compressed RAM swap)

A default Debian desktop installation may have no swap at all. When RAM fills,
the kernel has to drop caches or trigger the OOM killer, which shows up as a
system-wide stall. zram gives that pressure a fast, compressed backing store in
RAM:

```bash
sudo bash scripts/install-zram.sh --dry-run   # inspect the plan
sudo bash scripts/install-zram.sh             # install and start
sudo bash scripts/install-zram.sh --remove    # undo
```

The script installs `systemd-zram-generator` if needed and writes:

- `/etc/systemd/zram-generator.conf` — `min(ram / 2, 8192)` MiB, zstd,
  swap priority 100.
- `/etc/sysctl.d/99-43pr-zram.conf` — `vm.swappiness=150`,
  `vm.page-cluster=0`, `vm.watermark_boost_factor=0`,
  `vm.watermark_scale_factor=125` (the usual zram tuning; harmless without
  zram).

zram is not compatible with hibernation (there is no persistent swap device).
If `resume=` is configured, do not use this script. It does not replace a swap
partition for suspend-to-disk.

## Other measurable wins

These are system-level choices, not applied by the repository:

- **`thermald`** (`sudo apt install thermald`) — on a 13th-gen i9 it can avoid
  unnecessary throttling and keep sustained clocks steadier. It can also fight
  the firmware's own `platform_profile` policy on ASUS laptops, so measure
  before/after and keep it only if it helps. Check with
  `systemctl status thermald`.
- **Disk headroom** — a root filesystem above ~90% full slows ext4 allocation
  and can break updates. Check with `df -h /`; `apt clean`,
  `journalctl --vacuum-size=200M` and removing old kernels usually recover
  several GiB.
- **Boot time** — `systemd-analyze blame` and `systemd-analyze critical-chain`.
  Disable services you do not use, for example:
  `sudo systemctl disable --now NetworkManager-wait-online.service` (only if
  you do not need network-online ordering at boot) and the same for
  `vboxdrv`, `rabbitmq-server`, `docker`, `snapd`, `tor` or `ovs-vswitchd` if
  they are not part of your workflow. Do not disable services you do not
  recognise.
- **systemd-oomd** (`sudo apt install systemd-oomd`) — kills the heaviest
  cgroup before the whole desktop freezes under memory pressure. It complements
  zram; it is not a substitute for enough RAM.
- **TRIM** — `systemctl status fstrim.timer`; enable it with
  `sudo systemctl enable --now fstrim.timer` if it is inactive.
- **Refresh rate** — the internal panel runs at 90 Hz at 2880×1800, which is
  expensive for the iGPU. On battery, a 60 Hz mode saves power:
  `~/.config/hypr/scripts/monitor-ctl.sh mode eDP-1 2880x1800@60` (check the
  exact available mode first with `hyprctl monitors`). `monitor-ctl.sh`
  persists the choice in `monitors.lua`; switch back to `@90` on AC, or put a
  manual override in `monitors.local.lua`. Automatic AC/battery switching is
  not wired up.
- **i915 panel power features** — this machine boots with
  `i915.enable_psr=0 i915.enable_dc=0 i915.enable_fbc=0` in
  `/etc/default/grub`, disabling panel self-refresh, display power states and
  framebuffer compression. They are worth roughly 1–3 W at idle, but some
  panels flicker or corrupt with them. Re-enable one flag at a time, reboot and
  test; keep a rollback entry. This is an experiment, not a default.
- **Wi-Fi power save** — NetworkManager usually enables it; confirm with
  `iw dev wlo1 get power_save`. Enabling it when it is off saves a little
  idle power (`nmcli connection modify <name> wifi.powersave 3`).
- **Hyprland effects** — `look.lua` enables blur (size 5, one pass) and
  shadows. Lowering `blur.size`, reducing `passes`, or disabling `shadow` is a
  direct GPU saving; it is an aesthetic trade-off, so the repository leaves the
  defaults untouched.
- **One power owner** — do not run `power-profiles-daemon`, TLP, `tuned` and
  manual `platform_profile` writes at the same time. On this setup PPD is
  inactive and **Settings → System → CPU MODE** owns the profile. If you enable
  PPD, use it as the single owner (or mask it and keep the manual selector).
- **`powertop`** — for a second opinion on what drains the battery:
  `sudo powertop` (the `Tunables` tab lists suggestions; review each one).

None of this overrides the hardware limits of the laptop. The biggest battery
lever is the charge limit; the biggest responsiveness lever on a machine with
no swap is zram.
