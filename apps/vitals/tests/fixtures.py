"""Small machines, written by hand.

The app reads a directory, so a test writes one. That is the whole reason
`Sysroot` exists, and it is what makes every number in `sysinfo` checkable as
arithmetic on a Mac with no /proc in it at all.

These are deliberately *small* -- two cores, three processes -- and deliberately
literal: a test that asserts 50% processor load should be able to point at the
two numbers it came from. The plausible machine with sixty-four frames of
history is `demo.py`, which is for photographs rather than for assertions.

Every writer takes the same root and can be called again with different numbers,
which is how a delta is tested: write, sample, write again, sample again. The
sampler re-reads the files each time, so that exercises the real path rather
than a mocked one.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent), str(HERE.parent.parent.parent / "shared")]

from moarchy_vitals.sysinfo import (  # noqa: E402
    HZ,
    PAGE,
    STAT,
    STAT_FIELDS,
    STAT_FIRST,
)

# (pid, comm, cumulative ticks, resident bytes, ppid, uid, cgroup, threads)
DEFAULT_PROCESSES = (
    (1, "systemd", 400, 8 * 1024 * 1024, 0, 0, "0::/init.scope", 1),
    (
        420,
        "firefox",
        1200,
        200 * 1024 * 1024,
        1,
        1000,
        "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-firefox-420.scope",
        12,
    ),
    (
        421,
        "Isolated Web Co",
        800,
        100 * 1024 * 1024,
        420,
        1000,
        "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-firefox-420.scope",
        6,
    ),
)

PASSWD = "root:x:0:0::/root:/bin/sh\nsimon:x:1000:1000::/home/simon:/bin/sh\n"


def clear_processes(root: Path) -> None:
    """Take away every /proc/<pid> the last call left behind.

    Without this `processes=()` means "the ones from before", and a test that
    thought it had written one process is quietly asserting about another.
    """
    proc = root / "proc"
    if not proc.is_dir():
        return
    for entry in proc.iterdir():
        if entry.name.isdigit():
            shutil.rmtree(entry, ignore_errors=True)


def put(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_machine(
    root: Path,
    *,
    uptime: float = 1000.0,
    cores: tuple[tuple[int, int], ...] = ((100, 900), (200, 800)),
    load: tuple[float, float, float] = (0.5, 0.4, 0.3),
    tasks: str = "2/143",
    mem_total: int = 1_000_000,
    mem_available: int = 400_000,
    swap: tuple[int, int] = (500_000, 300_000),
    net: dict[str, tuple[int, int]] | None = None,
    wireless: bool = True,
    signal: int = -60,
    processes: tuple = DEFAULT_PROCESSES,
    disk_sectors: tuple[int, int] = (1000, 2000),
    temperature: int | None = 47_500,
    battery: int | None = 80,
    mounts: bool = True,
) -> Path:
    """One reading of a whole machine, every file the app looks at.

    Counters are absolute, the way the kernel's are: to test a rate, call this
    twice with a larger uptime and larger counters.
    """
    stat = _cpu_lines(cores)
    stat += "intr 88\nctxt 4242\nbtime 1700000000\nprocesses 900\n"
    stat += f"procs_running {tasks.split('/')[0]}\nprocs_blocked 0\n"
    put(root, "proc/stat", stat)
    put(root, "proc/uptime", f"{uptime:.2f} {uptime * 2:.2f}\n")
    put(root, "proc/loadavg", f"{load[0]} {load[1]} {load[2]} {tasks} 999\n")

    put(
        root,
        "proc/meminfo",
        f"MemTotal:       {mem_total} kB\n"
        f"MemFree:        {mem_available // 2} kB\n"
        f"MemAvailable:   {mem_available} kB\n"
        "Buffers:        10000 kB\n"
        "Cached:         100000 kB\n"
        "SReclaimable:   20000 kB\n"
        f"SwapTotal:      {swap[0]} kB\n"
        f"SwapFree:       {swap[1]} kB\n",
    )

    interfaces = {"lo": (1000, 1000), "wlan0": (5_000, 2_000)} if net is None else net
    dev = "Inter-|   Receive          |  Transmit\n face |bytes packets errs drop fifo frame compressed multicast|bytes\n"
    for name, (rx, tx) in interfaces.items():
        dev += f"{name:>6}: {rx} 10 0 0 0 0 0 0 {tx} 8 0 0 0 0 0 0\n"
    put(root, "proc/net/dev", dev)
    for name in interfaces:
        put(root, f"sys/class/net/{name}/operstate", "up\n")
    if wireless and "wlan0" in interfaces:
        put(
            root,
            "proc/net/wireless",
            "Inter-| sta-|   Quality        |   Discarded packets\n"
            " face | tus | link level noise |  nwid crypt frag retry misc | beacon\n"
            f" wlan0: 0000   35. {signal:>5}.  -256        0     0    0     0    0        0\n",
        )

    reads, writes = disk_sectors
    put(
        root,
        "proc/diskstats",
        f" 179 0 mmcblk0 10 0 {reads} 5 8 0 {writes} 9 0 1 1\n"
        f" 179 1 mmcblk0p1 9 0 {reads} 5 7 0 {writes} 9 0 1 1\n"
        f" 254 0 zram0 400 0 99999 5 300 0 99999 9 0 1 1\n",
    )

    if mounts:
        put(
            root,
            "proc/self/mounts",
            "/dev/mmcblk0p2 / ext4 rw,relatime 0 0\n"
            "/dev/mmcblk1p1 /media/SD\\040card exfat rw 0 0\n"
            "proc /proc proc rw 0 0\n"
            "tmpfs /run tmpfs rw 0 0\n",
        )
        put(
            root,
            "fixture-df",
            "8000000000 2000000000 /\n1000000000 250000000 /media/SD card\n",
        )

    if temperature is not None:
        put(root, "sys/class/thermal/thermal_zone0/type", "battery\n")
        put(root, "sys/class/thermal/thermal_zone0/temp", "30000\n")
        put(root, "sys/class/thermal/thermal_zone1/type", "cpu-thermal\n")
        put(root, "sys/class/thermal/thermal_zone1/temp", f"{temperature}\n")

    if battery is not None:
        put(root, "sys/class/power_supply/AC/type", "Mains\n")
        put(root, "sys/class/power_supply/BAT0/type", "Battery\n")
        put(root, "sys/class/power_supply/BAT0/capacity", f"{battery}\n")
        put(root, "sys/class/power_supply/BAT0/status", "Discharging\n")
        put(root, "sys/class/power_supply/BAT0/power_now", "2500000\n")

    put(root, "etc/passwd", PASSWD)
    put(root, "sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", "800000\n")
    put(root, "sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq", "1200000\n")

    clear_processes(root)
    for entry in processes:
        write_process(root, uptime, *entry)
    return root


def _cpu_lines(cores: tuple[tuple[int, int], ...]) -> str:
    """/proc/stat, with the aggregate being the sum of the cores it is over."""
    lines = ""
    busy_total = idle_total = 0
    for index, (busy, idle) in enumerate(cores):
        lines += _cpu_line(f"cpu{index}", busy, idle)
        busy_total += busy
        idle_total += idle
    return _cpu_line("cpu ", busy_total, idle_total) + lines


def _cpu_line(name: str, busy: int, idle: int) -> str:
    # user nice system idle iowait irq softirq steal guest guest_nice, with the
    # busy time all in user so a test can do the arithmetic in its head.
    return f"{name} {busy} 0 0 {idle} 0 0 0 0 0 0\n"


def write_process(
    root: Path,
    uptime: float,
    pid: int,
    comm: str,
    ticks: int,
    rss: int,
    ppid: int = 1,
    uid: int = 1000,
    cgroup: str = "",
    threads: int = 1,
    started: float = 10.0,
    state: str = "S",
) -> None:
    # By field name rather than by counting commas: /proc/<pid>/stat is
    # positional and fifty-two fields long, and the map is the parser's own, so
    # a fixture cannot quietly disagree with the code it is testing.
    fields = ["0"] * STAT_FIELDS
    for name, value in (
        ("state", state),
        ("ppid", ppid),
        ("utime", int(ticks * 0.75)),
        ("stime", ticks - int(ticks * 0.75)),
        ("threads", threads),
        ("starttime", int(started * HZ)),
        ("vsize", rss + 1_000_000),
        ("rss", rss // PAGE),
    ):
        fields[STAT[name] - STAT_FIRST] = str(value)
    put(root, f"proc/{pid}/stat", f"{pid} ({comm}) " + " ".join(fields) + "\n")
    put(
        root, f"proc/{pid}/status", f"Name:\t{comm}\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n"
    )
    put(root, f"proc/{pid}/cmdline", "" if not cgroup else f"/usr/bin/{comm}\0--flag\0")
    put(root, f"proc/{pid}/cgroup", f"{cgroup}\n" if cgroup else "")


def write_reel(root: Path, frames: int = 4, *, step: float = 2.0) -> Path:
    """A reel of `frames` machines, each busier than the last.

    Each frame adds 100 ticks of processor time per core over `step` seconds,
    which on a two-core machine at 100 Hz is exactly half of one core -- so a
    test can assert the graph filled with 25% and mean it.
    """
    base = root / "base"
    base.mkdir(parents=True, exist_ok=True)
    put(base, "etc/passwd", PASSWD)
    for index in range(frames):
        frame = root / "frames" / f"{index:03d}"
        write_machine(
            frame,
            uptime=1000.0 + index * step,
            cores=((100 + index * 100, 900 + index * 100),) * 2,
            net={"wlan0": (5_000 + index * 20_000, 2_000 + index * 4_000)},
            processes=tuple(
                (pid, comm, ticks + index * 40, rss, ppid, uid, cgroup, threads)
                for pid, comm, ticks, rss, ppid, uid, cgroup, threads in DEFAULT_PROCESSES
            ),
            disk_sectors=(1000 + index * 500, 2000 + index * 1000),
        )
    return root
