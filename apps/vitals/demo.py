#!/usr/bin/python3
"""Write a phone's /proc, a frame at a time.

A system monitor photographs badly. Two seconds after launch it has taken
exactly one sample, so every graph is a flat line against the left edge and the
task list is whatever the container happened to be running -- which on the
machine that takes these pictures is Xvfb, a shell and nothing else. None of
that says what the app is.

So this writes a machine: sixty-four frames of a plausible PinePhone, two
seconds apart, with a browser opening a page in the middle of it. Each frame is
a directory of the files the kernel would have had at that moment, and
`sysinfo.Reel` reads one per tick -- so the app samples a fixture exactly the
way it samples a phone, through the same code, with no screenshot mode in the
window and no "if testing" anywhere in the app.

The arithmetic is the point of the file. Every process is given a share of the
machine per frame; the /proc/stat the frame carries is the *sum* of those
shares, so the task list and the processor graph agree because they were
generated from one number rather than dressed to match. The same goes for the
network counters and the rates, which are the totals a device would have had if
it had been moving that much data.

It is invented data and says so: `Reel` refuses to signal anything, which is the
other half of why the demo is safe to run -- there is a pid 1 in here.
"""

from __future__ import annotations

import math
import os
import random
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

# The kernel's units, from the app rather than from a guess: /proc/<pid>/stat
# counts processor time in clock ticks and memory in pages, and both are
# properties of whichever kernel reads the file back. Writing 4096-byte pages
# and reading them on a machine with 16 KB ones reports every process using four
# times the memory it has, which is exactly what the first run of this did.
from moarchy_vitals.sysinfo import (  # noqa: E402
    HZ,
    PAGE,
    STAT,
    STAT_FIELDS,
    STAT_FIRST,
)

FRAMES = 64
STEP = 2.0  # seconds between frames, which is the app's own tick
CORES = 4
BOOT = 197_412.0  # a phone that has been up two days

MEM_TOTAL = 3_072_000  # kB, a 3 GB PinePhone
SWAP_TOTAL = 1_536_000  # zram, which is where swap lives on this hardware

# The burst: a browser opening a heavy page, a third of the way in and lasting
# half a minute. Without one the whole reel is a flat line at twelve per cent,
# which is an honest picture of an idle phone and a useless picture of an app
# about load.
BURST_FROM, BURST_TO = 20, 36

# (pid, comm, uid, cgroup, share of the machine, burst factor, resident MB)
#
# Shares are of the whole machine, the way the app reports them, and they add up
# to what /proc/stat says the machine was doing. The cgroups are the real
# shapes: a systemd user session puts a launched desktop entry in an
# app-*.scope, which is what lets the app group three firefox processes into one
# row without guessing.
# The cgroup paths a systemd user session actually uses, kept short so the table
# below stays a table.
USER = "0::/user.slice/user-1000.slice/user@1000.service"
APP = f"{USER}/app.slice"
SYSTEM = "0::/system.slice"
FIREFOX = f"{APP}/app-firefox-1203.scope"

PROCESSES = (
    (1, "systemd", 0, "0::/init.scope", 0.0015, 1.0, 11.8),
    (2, "kthreadd", 0, "", 0.0004, 1.0, 0.0),
    (14, "ksoftirqd/0", 0, "", 0.0011, 3.0, 0.0),
    (38, "kworker/1:1H", 0, "", 0.0008, 3.5, 0.0),
    (52, "kcompactd0", 0, "", 0.0003, 4.0, 0.0),
    (61, "irq/25-mmc0", 0, "", 0.0009, 2.5, 0.0),
    (
        198,
        "systemd-journal",
        0,
        f"{SYSTEM}/systemd-journald.service",
        0.0035,
        2.0,
        27.4,
    ),
    (231, "NetworkManager", 0, f"{SYSTEM}/NetworkManager.service", 0.0028, 1.6, 23.9),
    (243, "dbus-broker", 81, f"{SYSTEM}/dbus-broker.service", 0.0041, 2.2, 6.1),
    (266, "iwd", 0, f"{SYSTEM}/iwd.service", 0.0022, 1.8, 9.3),
    (402, "eg25-manager", 0, f"{SYSTEM}/eg25-manager.service", 0.0016, 1.0, 5.2),
    (901, "systemd", 1000, f"{USER}/init.scope", 0.0012, 1.0, 10.4),
    (
        944,
        "pipewire",
        1000,
        f"{USER}/session.slice/pipewire.service",
        0.0068,
        1.2,
        18.7,
    ),
    (
        951,
        "wireplumber",
        1000,
        f"{USER}/session.slice/wireplumber.service",
        0.0044,
        1.1,
        21.2,
    ),
    (1102, "quickshell", 1000, f"{APP}/app-quickshell-1102.scope", 0.052, 2.4, 184.6),
    (
        1140,
        "moarchy-keyboar",
        1000,
        f"{APP}/app-org.moarchy.Keyboard-1140.scope",
        0.006,
        1.3,
        61.8,
    ),
    (1203, "firefox", 1000, FIREFOX, 0.041, 4.2, 411.5),
    (1219, "Isolated Web Co", 1000, FIREFOX, 0.030, 6.5, 286.3),
    (1224, "WebExtensions", 1000, FIREFOX, 0.008, 1.4, 137.9),
    (
        1288,
        "moarchy-keep",
        1000,
        f"{APP}/app-org.moarchy.Keep-1288.scope",
        0.0035,
        1.0,
        73.1,
    ),
    (1301, "foot", 1000, f"{APP}/app-foot-1301.scope", 0.0021, 1.2, 22.8),
    (1310, "bash", 1000, f"{APP}/app-foot-1301.scope", 0.0006, 1.0, 4.3),
    (
        1402,
        "moarchy-vitals",
        1000,
        f"{APP}/app-org.moarchy.Vitals-1402.scope",
        0.0115,
        1.1,
        57.6,
    ),
)

# What a process is running, where it is not simply /usr/bin/<name>. The three
# firefox rows are the interesting ones: two of them are the same binary with
# -contentproc, which is exactly why a task list that does not group them shows
# a browser as twenty strangers.
COMMANDS = {
    1: "/usr/lib/systemd/systemd --system --deserialize 31",
    198: "/usr/lib/systemd/systemd-journald",
    231: "/usr/bin/NetworkManager --no-daemon",
    243: "/usr/bin/dbus-broker --log 4 --controller 9 --machine-id 7c1",
    266: "/usr/lib/iwd/iwd",
    901: "/usr/lib/systemd/systemd --user",
    1102: "/usr/bin/quickshell -c omarchy",
    1203: "/usr/lib/firefox/firefox --name firefox",
    1219: "/usr/lib/firefox/firefox -contentproc -childID 7 -isForBrowser",
    1224: "/usr/lib/firefox/firefox -contentproc -childID 2 -isForBrowser",
    1301: "foot",
    1310: "-bash",
}

# Kernel threads have no command line, and that is how the app tells them apart
# from everything else rather than by a list of names.
KERNEL_PARENT = {14: 2, 38: 2, 52: 2, 61: 2}


def command_of(pid: int, comm: str) -> str:
    """What a process is running: nothing at all, if it is a kernel thread."""
    if pid == 2 or pid in KERNEL_PARENT:
        return ""
    return COMMANDS.get(pid, f"/usr/bin/{comm}")


def stat_line(pid: int, comm: str, **values: object) -> str:
    """One /proc/<pid>/stat, by field name rather than by counting commas.

    The file is positional and fifty-two fields long. Everything the app does
    not read is a zero, and the ones it does read are placed by the same map the
    parser indexes with -- so a fixture cannot quietly disagree with it.
    """
    fields = ["0"] * STAT_FIELDS
    for name, value in values.items():
        fields[STAT[name] - STAT_FIRST] = str(value)
    return f"{pid} ({comm}) " + " ".join(fields) + "\n"


INTERFACES = ("wlan0", "lo")

PASSWD = "root:x:0:0::/root:/usr/bin/bash\nsimon:x:1000:1000::/home/simon:/usr/bin/bash\ndbus:x:81:81::/:/usr/bin/nologin\n"

MOUNTS = (
    "/dev/mmcblk0p2 / ext4 rw,relatime 0 0\n"
    "/dev/mmcblk0p1 /boot vfat rw,relatime,fmask=0022 0 0\n"
    "/dev/mmcblk1p1 /run/media/simon/SD\\040card exfat rw,nosuid,nodev,relatime 0 0\n"
    "proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0\n"
    "tmpfs /run tmpfs rw,nosuid,nodev,mode=755 0 0\n"
)

# total, used, mount -- statvfs(2) is the one number that is not in a file, so a
# fixture has to stand in for it. The mount is last because it may contain a
# space, and an SD card mounted by name is where that happens. See Sysroot.usage.
DF = (
    (28_991_029_248, 11_402_215_424, "/"),
    (535_805_952, 92_274_688, "/boot"),
    (63_864_569_856, 21_331_058_688, "/run/media/simon/SD card"),
)


def burst(frame: int) -> float:
    """0 outside the burst, rising to 1 in the middle of it.

    A raised cosine rather than a step, because a step makes every graph in the
    app draw one vertical line and nothing else -- and because a phone opening a
    page does not go from idle to busy between two samples.
    """
    if not BURST_FROM <= frame <= BURST_TO:
        return 0.0
    span = BURST_TO - BURST_FROM
    return 0.5 - 0.5 * math.cos(2 * math.pi * (frame - BURST_FROM) / span)


def shares(frame: int, rng: random.Random) -> dict[int, float]:
    """Every process's share of the machine in this frame."""
    heat = burst(frame)
    out = {}
    for pid, _, _, _, base, factor, _ in PROCESSES:
        # Jitter every process independently, so the sum wobbles the way a real
        # machine's does rather than moving as one block.
        jitter = 1.0 + rng.uniform(-0.35, 0.35)
        out[pid] = max(0.0, base * jitter * (1.0 + heat * (factor - 1.0)))
    return out


def core_loads(total: float, rng: random.Random) -> list[float]:
    """One machine-wide load, spread unevenly over four cores.

    Unevenly on purpose: a phone's scheduler does not spread work evenly, and
    four identical bars would be a picture of something that does not happen.
    The mean is still `total`, which is what keeps the bars and the figure above
    them telling the same story.
    """
    weights = [1.55, 1.15, 0.75, 0.55]
    rng.shuffle(weights)
    loads = [min(0.99, total * w) for w in weights]
    mean = sum(loads) / CORES
    if mean <= 0:
        return loads
    # Rescale back onto the machine-wide figure, then clamp again: clamping a
    # core is what makes the mean drift, so it is done before the correction.
    scale = total / mean
    return [min(0.995, load * scale) for load in loads]


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_base(root: Path) -> None:
    """Everything that does not change between frames."""
    base = root / "base"
    write(base / "etc/passwd", PASSWD)
    write(base / "proc/self/mounts", MOUNTS)
    write(base / "fixture-df", "".join(f"{t} {u} {m}\n" for t, u, m in DF))

    # A driver's quality out of 70, and a level in dBm: good signal, one AP.
    write(
        base / "proc/net/wireless",
        "Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n"
        " face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22\n"
        " wlan0: 0000   59.  -51.  -256        0      0      0     94      0        0\n",
    )
    for name in INTERFACES:
        write(base / f"sys/class/net/{name}/operstate", "up\n")

    write(base / "sys/class/thermal/thermal_zone0/type", "cpu-thermal\n")
    write(base / "sys/class/thermal/thermal_zone1/type", "battery\n")
    write(base / "sys/class/thermal/thermal_zone1/temp", "31200\n")

    write(base / "sys/class/power_supply/BAT0/type", "Battery\n")
    write(base / "sys/class/power_supply/BAT0/status", "Discharging\n")
    write(base / "sys/class/power_supply/BAT0/voltage_now", "3842000\n")
    write(base / "sys/class/power_supply/BAT0/current_now", "421000\n")

    for pid, comm, uid, cgroup, _, _, _ in PROCESSES:
        where = base / "proc" / str(pid)
        write(
            where / "status",
            f"Name:\t{comm}\nState:\tS (sleeping)\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n",
        )
        # NUL separated, and empty for a kernel thread -- which is how the app
        # knows one when it sees it.
        command = command_of(pid, comm)
        write(where / "cmdline", "\0".join(command.split()) + ("\0" if command else ""))
        write(where / "cgroup", f"{cgroup}\n" if cgroup else "")


def write_frame(root: Path, index: int, state: dict, rng: random.Random) -> None:
    frame = root / "frames" / f"{index:03d}"
    uptime = BOOT + index * STEP
    per_process = shares(index, rng)
    total = min(0.97, sum(per_process.values()))
    loads = core_loads(total, rng)
    heat = burst(index)

    # --- the processor ---------------------------------------------------
    lines = []
    for core, load in enumerate(loads):
        busy = load * STEP * HZ
        idle = (1.0 - load) * STEP * HZ
        state["cores"][core][0] += busy * 0.68  # user
        state["cores"][core][1] += busy * 0.32  # system
        state["cores"][core][2] += idle
        state["cores"][core][3] += idle * 0.035  # iowait, off the eMMC
        lines.append(state["cores"][core])
    summed = [sum(column) for column in zip(*lines)]

    def cpu_line(name: str, values: list[float]) -> str:
        user, system, idle, wait = (int(v) for v in values)
        # user nice system idle iowait irq softirq steal guest guest_nice
        return f"{name} {user} 0 {system} {idle} {wait} 0 {int(system * 0.08)} 0 0 0\n"

    # The aggregate is the sum of the cores it is over, which is a promise the
    # kernel makes and an app is entitled to lean on.
    stat = cpu_line("cpu ", summed)
    stat += "".join(cpu_line(f"cpu{core}", values) for core, values in enumerate(lines))
    state["ctxt"] += int(9000 + 42000 * total)
    stat += f"intr {int(state['ctxt'] * 2.4)}\nctxt {state['ctxt']}\nbtime 1789012345\n"
    stat += f"processes {12000 + index * 3}\nprocs_running {1 + int(total * CORES)}\nprocs_blocked 0\n"
    write(frame / "proc/stat", stat)

    write(frame / "proc/uptime", f"{uptime:.2f} {uptime * CORES * 0.82:.2f}\n")

    # The load average is a decaying mean of runnable tasks, so it lags the
    # burst -- which is the whole reason both are on screen.
    state["load"] = [
        was + (total * CORES - was) * pull
        for was, pull in zip(state["load"], (0.22, 0.06, 0.02))
    ]
    one, five, fifteen = state["load"]
    tasks = len(PROCESSES) + 389
    write(
        frame / "proc/loadavg",
        f"{one:.2f} {five:.2f} {fifteen:.2f} {1 + int(total * CORES)}/{tasks} {12000 + index * 3}\n",
    )

    # --- memory ----------------------------------------------------------
    # The browser's page costs memory and gives most of it back.
    extra = int(heat * 348_000)
    free = 214_000 - int(extra * 0.55) + int(rng.uniform(-6000, 6000))
    cached = 892_000 - int(extra * 0.45)
    available = free + cached - 120_000
    swap_free = SWAP_TOTAL - 214_000 - int(heat * 96_000)
    write(
        frame / "proc/meminfo",
        f"MemTotal:       {MEM_TOTAL} kB\n"
        f"MemFree:        {free} kB\n"
        f"MemAvailable:   {available} kB\n"
        f"Buffers:        {41_200} kB\n"
        f"Cached:         {cached} kB\n"
        f"SwapCached:     {18_400} kB\n"
        f"SReclaimable:   {96_800} kB\n"
        f"SwapTotal:      {SWAP_TOTAL} kB\n"
        f"SwapFree:       {swap_free} kB\n"
        f"Shmem:          {54_100} kB\n",
    )

    # --- the network -----------------------------------------------------
    wlan_rx = 9_600 + heat * 1_380_000 * rng.uniform(0.75, 1.25)
    wlan_tx = 3_100 + heat * 138_000 * rng.uniform(0.7, 1.3)
    lo_rx = lo_tx = 4_200 + rng.uniform(0, 2600)
    for name, (rx_rate, tx_rate) in (
        ("wlan0", (wlan_rx, wlan_tx)),
        ("lo", (lo_rx, lo_tx)),
    ):
        counters = state["net"][name]
        counters[0] += rx_rate * STEP
        counters[1] += tx_rate * STEP
    dev = (
        "Inter-|   Receive                                                |  Transmit\n"
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n"
    )
    for name in INTERFACES:
        rx, tx = state["net"][name]
        packets = int(rx / 1140)
        dev += (
            f"{name:>6}: {int(rx)} {packets} 0 0 0 0 0 0 "
            f"{int(tx)} {int(tx / 640)} 0 0 0 0 0 0\n"
        )
    write(frame / "proc/net/dev", dev)

    # --- the disk --------------------------------------------------------
    read_rate = 24_000 + heat * 3_100_000 * rng.uniform(0.6, 1.4)
    write_rate = 61_000 + heat * 420_000 * rng.uniform(0.5, 1.5)
    state["disk"][0] += read_rate * STEP / 512
    state["disk"][1] += write_rate * STEP / 512
    reads, writes = state["disk"]
    write(
        frame / "proc/diskstats",
        f" 179       0 mmcblk0 {int(reads / 8)} 0 {int(reads)} 4812 {int(writes / 6)} 0 {int(writes)} 21044 0 9214 25856\n"
        f" 179       1 mmcblk0p1 812 0 6420 44 12 0 96 8 0 52 52\n"
        f" 179       2 mmcblk0p2 {int(reads / 9)} 0 {int(reads * 0.94)} 4610 {int(writes / 7)} 0 {int(writes * 0.95)} 20120 0 8890 24700\n"
        f" 254       0 zram0 {int(reads / 40)} 0 {int(reads / 20)} 120 {int(writes / 12)} 0 {int(writes / 6)} 310 0 240 430\n",
    )

    # --- heat, charge, clock ---------------------------------------------
    state["temp"] += (41_500 + heat * 23_000 - state["temp"]) * 0.25
    write(frame / "sys/class/thermal/thermal_zone0/temp", f"{int(state['temp'])}\n")
    write(frame / "sys/class/power_supply/BAT0/capacity", f"{68 - index // 40}\n")
    for core, load in enumerate(loads):
        # A big.LITTLE-ish ramp: idle at 480 MHz, flat out at 1.15 GHz.
        khz = int(480_000 + load * 672_000)
        write(
            frame / f"sys/devices/system/cpu/cpu{core}/cpufreq/scaling_cur_freq",
            f"{khz}\n",
        )

    # --- every process ---------------------------------------------------
    for pid, comm, _, _, _, _, megabytes in PROCESSES:
        share = per_process[pid]
        # A share of the machine over STEP seconds is that much processor time
        # on every core, which is what /proc/<pid>/stat counts.
        ticks = share * CORES * STEP * HZ
        # Seeded with a plausible lifetime rather than with zero: the detail
        # page shows processor time since the process started, and a browser
        # that has been open four hours has not used two seconds of it.
        started = max(0.0, BOOT - 14_400 + pid * 1.7)
        seed = share * CORES * (BOOT - started) * HZ * 0.45
        used = state["procs"].setdefault(pid, [seed * 0.7, seed * 0.3])
        used[0] += ticks * 0.7
        used[1] += ticks * 0.3

        command = command_of(pid, comm)
        rss_pages = int(megabytes * 1_000_000 / PAGE)
        if heat and command.startswith("/usr/lib/firefox"):
            rss_pages = int(rss_pages * (1.0 + heat * 0.22))
        write(
            frame / f"proc/{pid}/stat",
            stat_line(
                pid,
                comm,
                state="R" if share > 0.05 else "S",
                ppid=KERNEL_PARENT.get(pid, 1),
                utime=int(used[0]),
                stime=int(used[1]),
                threads=1 if not command else 4 + pid % 9,
                starttime=int(started * HZ),
                vsize=rss_pages * PAGE + 41_000_000,
                rss=rss_pages,
            ),
        )


def main() -> int:
    target = os.environ.get("MOARCHY_VITALS_DIR")
    if not target:
        print(
            "set MOARCHY_VITALS_DIR first -- this writes a few thousand files",
            file=sys.stderr,
        )
        return 2

    root = Path(target)
    for stale in ("base", "frames"):
        shutil.rmtree(root / stale, ignore_errors=True)

    rng = random.Random(20260913)
    state = {
        "cores": [
            [3_140_000.0 + core * 2200, 980_000.0, 41_900_000.0, 210_000.0]
            for core in range(CORES)
        ],
        "net": {
            "wlan0": [2_914_882_100.0, 214_663_900.0],
            "lo": [88_142_000.0, 88_142_000.0],
        },
        "disk": [42_118_400.0, 18_442_100.0],
        "procs": {},
        "load": [0.38, 0.31, 0.29],
        "temp": 41_500.0,
        "ctxt": 884_112_000,
    }

    write_base(root)
    for index in range(FRAMES):
        write_frame(root, index, state, rng)

    print(f"wrote {FRAMES} frames of a phone to {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
