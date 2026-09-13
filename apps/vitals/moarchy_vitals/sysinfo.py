"""What the phone is doing, read out of /proc.

This is the half of the app that has nothing to do with GTK: it turns the text
files the kernel exports into numbers, and it is the only place in the app that
knows a file format. Everything above it is given dataclasses.

Three decisions shape the whole module.

**Everything is read through a `Sysroot`.** Not `open("/proc/stat")` anywhere:
one object owns "where the kernel's files are", which buys three things that
matter more than the indirection costs. A test can hand it a directory of
hand-written files and assert on exact arithmetic -- on a Mac, where there is no
/proc at all. The screenshot harness can hand it a *reel* of such directories
and get moving graphs out of a machine that does not exist. And signalling a
process goes through the same object, so a fixture cannot kill anything: the
demo data has a pid 1 in it, and `os.kill(1, SIGKILL)` in a container is not a
bug anybody gets to make twice.

**Rates come from deltas, and the clock is `/proc/uptime`.** Processor load and
network throughput are not in /proc at all; what is there are counters since
boot, and a rate is the difference between two readings divided by the time
between them. Using the kernel's own clock rather than `time.monotonic()` means
a fixture reel advances its own time by writing a different uptime -- the same
reason the screenshot harness pins today's date for Habits.

**Nothing raises.** A phone kernel may have no swap, no battery, no thermal
zone, no wireless; a container may have no /proc/net/wireless at all; a process
read one line ago may be gone by the next line. Every read returns None on
failure and every parser copes, because the alternative is an app that dies on
the machine it was not developed on.
"""

from __future__ import annotations

import os
import re
import signal
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path

# Clock ticks per second, the unit /proc/<pid>/stat counts processor time in,
# and the page size /proc/<pid>/stat counts resident memory in. Both are
# constants of the running kernel rather than of the file format, which is why
# they are asked for rather than assumed to be 100 and 4096.
try:
    HZ = os.sysconf("SC_CLK_TCK") or 100
    PAGE = os.sysconf("SC_PAGE_SIZE") or 4096
except (ValueError, OSError):  # pragma: no cover - depends on the host
    HZ, PAGE = 100, 4096

# Filesystems worth showing. The alternative -- everything in /proc/self/mounts
# minus a blocklist -- lists forty entries on a systemd machine, most of them
# cgroup and tmpfs mounts of no interest to anybody looking at a storage bar.
REAL_FILESYSTEMS = frozenset(
    {
        "ext2",
        "ext3",
        "ext4",
        "btrfs",
        "xfs",
        "f2fs",
        "jfs",
        "reiserfs",
        "zfs",
        "vfat",
        "exfat",
        "ntfs",
        "ntfs3",
    }
)

# Block devices that are not disks. zram is the interesting one on a phone: it
# is where swap lives on a 2 GB device, and counting its traffic as disk I/O
# would report a machine thrashing its storage when it is compressing memory.
NOT_A_DISK = re.compile(r"^(loop|ram|zram|dm-|md|sr|fd)")

# A systemd user-session app unit: app-org.gnome.Calculator-1234.scope, or
# app-firefox@abcd.service. This is what a desktop entry launched through the
# session looks like from /proc/<pid>/cgroup, and it is the one grouping the
# system itself provides -- so where it is there, it is believed.
#
# The launcher prefixes are an explicit list rather than `[a-z]+-`, which is the
# obvious pattern and is wrong: app-foot-8f3a.scope matched it with "foot" as
# the prefix, and the app came out of the list called "8f3a".
APP_UNIT = re.compile(
    r"app-(?:gnome|flatpak|snap|kde|plasma|xdg)?-?"
    r"(?P<id>.+?)(?:[-@][0-9a-f]+)?\.(?:scope|service)$"
)

# systemd escapes a dash in a unit name. Left alone, every Flatpak-style id
# reads as org\x2dexample\x2dApp in the list.
UNIT_ESCAPE = re.compile(r"\\x([0-9a-fA-F]{2})")

# The fields of /proc/<pid>/stat this app reads, numbered as proc(5) numbers
# them: field 1 is the pid and field 2 is the command, so the rest of the line
# begins at 3. Named here rather than indexed inline because `fields[11]` is not
# checkable against the manual page by anybody reading it -- and because the
# demo and the test fixtures write the file from this same map, so what is
# written and what is read cannot drift apart.
STAT = {
    "state": 3,
    "ppid": 4,
    "utime": 14,
    "stime": 15,
    "threads": 20,
    "starttime": 22,
    "vsize": 23,
    "rss": 24,
}

# How many fields follow the command, and the offset from a proc(5) field number
# into the list of them.
STAT_FIELDS = 50
STAT_FIRST = 3

# How long a process name is allowed to be in the kernel: TASK_COMM_LEN is 16,
# of which one is the terminator. Every longer name arrives from /proc cut to
# exactly this, which is why a phone's task list is full of "moarchy-keyboar"
# and "xdg-desktop-por".
COMM_MAX = 15

STATES = {
    "R": "Running",
    "S": "Sleeping",
    "D": "Waiting for disk",
    "Z": "Zombie",
    "T": "Stopped",
    "t": "Traced",
    "X": "Dead",
    "I": "Idle",
}


# --- where the files are ---------------------------------------------------


class Sysroot:
    """The machine's own /proc and /sys, or a directory shaped like them."""

    def __init__(self, root: Path | str = "/") -> None:
        self.root = Path(root)
        self._passwd: dict[int, str] | None = None

    # Read failures are silence rather than exceptions on purpose: a process
    # can exit between listing /proc and reading its stat file, and that is
    # the normal case rather than an error -- it happens on every tick of a
    # busy machine.
    def read(self, rel: str) -> str | None:
        try:
            return (self.root / rel).read_text(encoding="utf-8", errors="replace")
        except (OSError, ValueError):
            return None

    def listdir(self, rel: str) -> list[str]:
        try:
            return os.listdir(self.root / rel)
        except OSError:
            return []

    def usage(self, mount: str) -> tuple[int, int] | None:
        """(total, used) bytes of a mounted filesystem.

        The one number in this module that does not come out of a file: a
        filesystem's size comes from statvfs(2), which asks the kernel about a
        path rather than about a sysroot. So a sysroot that is not the machine's
        own answers from a `fixture-df` beside its proc directory instead --
        because statvfs("/") under a fixture would report the size of the disk
        the tests are running on, which is how this was found.
        """
        if not self.live:
            return self._fixture_usage(mount)
        try:
            st = os.statvfs(mount)
        except OSError:
            return None
        total = st.f_blocks * st.f_frsize
        # f_bfree, not f_bavail: the difference is the root reserve, and a bar
        # that ignores it reports 5% of the disk as free when nobody can use it.
        return total, total - st.f_bfree * st.f_frsize

    def _fixture_usage(self, mount: str) -> tuple[int, int] | None:
        """From `fixture-df`: one `total used mount` line each.

        The mount point is last because it is the field that can contain a
        space -- /run/media/simon/SD card is a real mount point, and a fixture
        that could not express one would not exercise the unescaping that the
        kernel's own /proc/self/mounts needs.
        """
        for line in (self.read("fixture-df") or "").splitlines():
            parts = line.split(None, 2)
            if len(parts) == 3 and parts[2] == mount:
                try:
                    return int(parts[0]), int(parts[1])
                except ValueError:
                    return None
        return None

    def username(self, uid: int) -> str:
        """A uid as a name, from the sysroot's own passwd where it has one."""
        if self._passwd is None:
            self._passwd = {}
            text = self.read("etc/passwd")
            for line in (text or "").splitlines():
                parts = line.split(":")
                if len(parts) > 2 and parts[2].isdigit():
                    self._passwd[int(parts[2])] = parts[0]
        name = self._passwd.get(uid)
        if name:
            return name
        if self.root == Path("/"):
            try:
                import pwd

                return pwd.getpwuid(uid).pw_name
            except (KeyError, ImportError):
                pass
        return str(uid)

    def signal(self, pid: int, sig: int) -> None:
        """Send a signal, for real.

        pid 1 is refused outright. Nothing an app of this shape wants to do is
        served by signalling init, the kernel would refuse it anyway on the
        phone, and in a container -- where this app is developed and where pid 1
        is the thing being developed in -- it would not.
        """
        if pid <= 1:
            raise PermissionError("refusing to signal pid 1")
        os.kill(pid, sig)

    def advance(self) -> None:
        """Move to the next reading. Real time needs no help; a reel does."""

    @property
    def live(self) -> bool:
        return self.root == Path("/")


class Reel(Sysroot):
    """A directory of numbered snapshots, read one per tick.

    `<root>/frames/000`, `001`, ... each hold whatever *changed* in that frame;
    anything absent falls back to `<root>/base`, which holds the files that do
    not change. That split is what keeps a minute of history down to a couple
    of thousand small files rather than ten thousand.

    A reel is what makes a screenshot of this app worth taking. An app that
    samples every two seconds has, two seconds after launch, exactly one sample
    -- so a graph photographed on a real machine is a flat line at the left
    edge, which says nothing about what the app does. A reel has a past.

    Run out, it holds the last frame. The Sampler then sees no time passing and
    returns its previous reading unchanged, so the screen holds still rather
    than showing a machine that stopped dead.
    """

    def __init__(self, root: Path | str) -> None:
        super().__init__(root)
        self.base = self.root / "base"
        self.frames = sorted(p for p in (self.root / "frames").glob("*") if p.is_dir())
        # Before the first advance, so that the first `sample()` -- which
        # advances before it reads -- reads frame zero rather than skipping it.
        self.index = -1
        self.signalled: list[tuple[int, int]] = []

    def __len__(self) -> int:
        return len(self.frames)

    @property
    def exhausted(self) -> bool:
        return self.index >= len(self.frames) - 1

    def advance(self) -> None:
        if not self.exhausted:
            self.index += 1

    @property
    def remaining(self) -> int:
        return max(0, len(self.frames) - 1 - self.index)

    def _frame(self) -> Path:
        if not self.frames:
            return self.base
        return self.frames[max(0, min(self.index, len(self.frames) - 1))]

    def read(self, rel: str) -> str | None:
        for where in (self._frame(), self.base):
            try:
                return (where / rel).read_text(encoding="utf-8", errors="replace")
            except (OSError, ValueError):
                continue
        return None

    def listdir(self, rel: str) -> list[str]:
        names: set[str] = set()
        for where in (self._frame(), self.base):
            try:
                names.update(os.listdir(where / rel))
            except OSError:
                continue
        return sorted(names)

    def signal(self, pid: int, sig: int) -> None:
        """Recorded, never sent. The demo data has a pid 1 in it."""
        self.signalled.append((pid, sig))

    @property
    def live(self) -> bool:
        return False


def sysroot_for(path: str | None) -> Sysroot:
    """The sysroot an environment variable asks for, or the real one."""
    if not path:
        return Sysroot("/")
    root = Path(path)
    if (root / "frames").is_dir():
        return Reel(root)
    return Sysroot(root)


# --- what a reading looks like ---------------------------------------------


@dataclass(frozen=True)
class Cpu:
    total: float  # 0..1 of the whole machine
    cores: tuple[float, ...]
    load: tuple[float, float, float]
    uptime: float
    tasks: int
    running: int
    temperature: float | None  # degrees celsius
    frequency: float | None  # MHz, averaged over the cores that report one


@dataclass(frozen=True)
class Memory:
    total: int
    available: int
    cached: int
    swap_total: int
    swap_free: int

    @property
    def used(self) -> int:
        """Total minus *available*, not minus free.

        MemAvailable is the kernel's own estimate of what a new process could
        get without swapping, which is the question anybody looking at a memory
        bar is asking. Total minus free counts the page cache as used and
        reports every idle Linux machine as full.
        """
        return max(0, self.total - self.available)

    @property
    def fraction(self) -> float:
        return self.used / self.total if self.total else 0.0

    @property
    def swap_used(self) -> int:
        return max(0, self.swap_total - self.swap_free)

    @property
    def swap_fraction(self) -> float:
        return self.swap_used / self.swap_total if self.swap_total else 0.0


@dataclass(frozen=True)
class Interface:
    name: str
    rx: int
    tx: int
    rx_rate: float
    tx_rate: float
    state: str
    quality: float | None = None  # wireless link, 0..1
    signal: int | None = None  # dBm

    @property
    def wireless(self) -> bool:
        return self.quality is not None or self.signal is not None

    @property
    def up(self) -> bool:
        return self.state == "up"


@dataclass(frozen=True)
class Disk:
    mount: str
    device: str
    total: int
    used: int

    @property
    def free(self) -> int:
        return max(0, self.total - self.used)

    @property
    def fraction(self) -> float:
        return self.used / self.total if self.total else 0.0


@dataclass(frozen=True)
class Io:
    read_rate: float
    write_rate: float


@dataclass(frozen=True)
class Battery:
    percent: int
    status: str
    watts: float | None


@dataclass(frozen=True)
class Process:
    pid: int
    ppid: int
    name: str
    cmdline: str
    user: str
    state: str
    threads: int
    rss: int
    cpu: float  # 0..1 of the whole machine, as the overview reports it
    seconds: float  # processor time used since it started
    app_key: str
    app_name: str

    @property
    def kernel(self) -> bool:
        """A kernel thread: no address space, so no command line."""
        return not self.cmdline


@dataclass(frozen=True)
class AppGroup:
    key: str
    name: str
    pids: tuple[int, ...]
    cpu: float
    rss: int
    user: str

    @property
    def count(self) -> int:
        return len(self.pids)


@dataclass(frozen=True)
class Sample:
    uptime: float
    cpu: Cpu
    memory: Memory
    interfaces: tuple[Interface, ...]
    disks: tuple[Disk, ...]
    io: Io
    battery: Battery | None
    processes: tuple[Process, ...]
    apps: tuple[AppGroup, ...]

    @property
    def net_rx(self) -> float:
        return sum(i.rx_rate for i in self.interfaces)

    @property
    def net_tx(self) -> float:
        return sum(i.tx_rate for i in self.interfaces)


# --- the reading itself ----------------------------------------------------


class Sampler:
    """One reading of the machine, and the previous one it is measured against.

    Stateful on purpose: every rate in this app is a difference between two
    readings, so something has to remember the first one. Keeping that here
    rather than in the window means the arithmetic can be tested by calling
    `sample()` twice against two fixtures.
    """

    def __init__(self, root: Sysroot | Path | str = "/") -> None:
        self.root = root if isinstance(root, Sysroot) else Sysroot(root)
        self._cpu_prev: dict[str, tuple[int, int]] = {}
        self._net_prev: dict[str, tuple[int, int]] = {}
        self._io_prev: tuple[int, int] | None = None
        self._proc_prev: dict[int, tuple[float, float]] = {}
        self._uptime_prev: float | None = None
        self._proc_uptime_prev: float | None = None
        self._meta: dict[tuple[int, float], tuple[str, str, str, str]] = {}
        self._last: Sample | None = None
        self._cores = 1

    # --- the entry point -------------------------------------------------

    def sample(self, *, processes: bool = True) -> Sample:
        """Read the machine now.

        `processes=False` skips the expensive half. Walking /proc is a few
        hundred file reads; the overview needs none of them, and doing it every
        two seconds to draw a memory bar is the difference between an app you
        can leave open on a phone and one you cannot.
        """
        self.root.advance()
        uptime = self._uptime()
        elapsed = None
        if self._uptime_prev is not None:
            elapsed = uptime - self._uptime_prev
            # No time has passed: either two reads inside one clock tick, or a
            # fixture reel that has run out. Either way the honest answer is the
            # reading we already have.
            if elapsed <= 0 and self._last is not None:
                return self._last

        cpu = self._cpu(uptime, elapsed)
        memory = self._memory()
        interfaces = self._net(elapsed)
        io = self._io(elapsed)
        disks = self._disks()
        battery = self._battery()

        procs: tuple[Process, ...] = ()
        apps: tuple[AppGroup, ...] = ()
        if processes:
            procs = self._processes(uptime)
            apps = group_apps(procs)

        self._uptime_prev = uptime
        sample = Sample(
            uptime=uptime,
            cpu=cpu,
            memory=memory,
            interfaces=interfaces,
            disks=disks,
            io=io,
            battery=battery,
            processes=procs,
            apps=apps,
        )
        # Only a sample that read everything may stand in for the next one: a
        # held reading with an empty process list would empty the task list.
        if processes or self._last is None:
            self._last = sample
        return sample

    # --- processor -------------------------------------------------------

    def _uptime(self) -> float:
        text = self.root.read("proc/uptime")
        if text:
            try:
                return float(text.split()[0])
            except (IndexError, ValueError):
                pass
        return time.monotonic()

    def _cpu(self, uptime: float, elapsed: float | None) -> Cpu:
        busy_total: dict[str, tuple[int, int]] = {}
        for line in (self.root.read("proc/stat") or "").splitlines():
            parts = line.split()
            if not parts or not parts[0].startswith("cpu"):
                continue
            try:
                values = [int(v) for v in parts[1:]]
            except ValueError:
                continue
            if len(values) < 5:
                continue
            total = sum(values)
            # Idle *and* iowait: a processor waiting for the eMMC is not
            # working, and counting iowait as load makes every boot look pegged.
            busy = total - values[3] - values[4]
            busy_total[parts[0]] = (busy, total)

        fractions: dict[str, float] = {}
        for name, (busy, total) in busy_total.items():
            was = self._cpu_prev.get(name)
            if was is None:
                # The first reading has nothing to subtract from, so it is the
                # average since boot. Zero would be a lie about an idle machine
                # and 100% a worse one about a busy phone.
                fractions[name] = busy / total if total else 0.0
            else:
                span = total - was[1]
                fractions[name] = (busy - was[0]) / span if span > 0 else 0.0
        self._cpu_prev = busy_total

        # `cpu` is the whole machine and `cpu0`... are the cores, in the file's
        # own order rather than sorted as strings -- cpu10 sorts before cpu2.
        count = sum(1 for name in fractions if re.fullmatch(r"cpu\d+", name))
        cores = tuple(_clamp(fractions.get(f"cpu{n}", 0.0)) for n in range(count))
        self._cores = max(1, len(cores))

        load, tasks, running = (0.0, 0.0, 0.0), 0, 0
        parts = (self.root.read("proc/loadavg") or "").split()
        if len(parts) >= 4:
            try:
                load = (float(parts[0]), float(parts[1]), float(parts[2]))
            except ValueError:
                pass
            runnable, _, total_tasks = parts[3].partition("/")
            running = int(runnable) if runnable.isdigit() else 0
            tasks = int(total_tasks) if total_tasks.isdigit() else 0

        return Cpu(
            total=_clamp(fractions.get("cpu", 0.0)),
            cores=cores,
            load=load,
            uptime=uptime,
            tasks=tasks,
            running=running,
            temperature=self._temperature(),
            frequency=self._frequency(),
        )

    def _temperature(self) -> float | None:
        """The hottest thermal zone, preferring one that names the processor.

        A phone has several -- battery, charger, modem, GPU -- and which index
        is which differs per SoC, so the type is read rather than assuming
        thermal_zone0 is the one anybody means.
        """
        best: float | None = None
        best_cpu: float | None = None
        for name in self.root.listdir("sys/class/thermal"):
            if not name.startswith("thermal_zone"):
                continue
            raw = self.root.read(f"sys/class/thermal/{name}/temp")
            if raw is None:
                continue
            try:
                celsius = int(raw.strip()) / 1000.0
            except ValueError:
                continue
            if not -50 < celsius < 200:
                continue
            kind = (self.root.read(f"sys/class/thermal/{name}/type") or "").strip()
            if any(
                hint in kind.lower() for hint in ("cpu", "soc", "pkg", "core", "tsens")
            ):
                best_cpu = celsius if best_cpu is None else max(best_cpu, celsius)
            best = celsius if best is None else max(best, celsius)
        return best_cpu if best_cpu is not None else best

    def _frequency(self) -> float | None:
        rates = []
        base = "sys/devices/system/cpu"
        for name in self.root.listdir(base):
            if not re.fullmatch(r"cpu\d+", name):
                continue
            raw = self.root.read(f"{base}/{name}/cpufreq/scaling_cur_freq")
            if raw is None:
                continue
            try:
                rates.append(int(raw.strip()) / 1000.0)  # kHz -> MHz
            except ValueError:
                continue
        return sum(rates) / len(rates) if rates else None

    # --- memory ----------------------------------------------------------

    def _memory(self) -> Memory:
        values: dict[str, int] = {}
        for line in (self.root.read("proc/meminfo") or "").splitlines():
            key, _, rest = line.partition(":")
            parts = rest.split()
            if not parts:
                continue
            try:
                amount = int(parts[0])
            except ValueError:
                continue
            values[key] = amount * 1024 if len(parts) > 1 else amount

        total = values.get("MemTotal", 0)
        return Memory(
            total=total,
            # A kernel too old for MemAvailable is rare enough that the estimate
            # below is only there so the bar is not nonsense on one.
            available=values.get(
                "MemAvailable",
                values.get("MemFree", 0)
                + values.get("Cached", 0)
                + values.get("Buffers", 0),
            ),
            cached=values.get("Cached", 0)
            + values.get("SReclaimable", 0)
            + values.get("Buffers", 0),
            swap_total=values.get("SwapTotal", 0),
            swap_free=values.get("SwapFree", 0),
        )

    # --- network ---------------------------------------------------------

    def _net(self, elapsed: float | None) -> tuple[Interface, ...]:
        wireless = self._wireless()
        found: list[Interface] = []
        counters: dict[str, tuple[int, int]] = {}
        for line in (self.root.read("proc/net/dev") or "").splitlines():
            name, _, rest = line.partition(":")
            name = name.strip()
            if not rest or not name:
                continue
            parts = rest.split()
            if len(parts) < 9:
                continue
            try:
                rx, tx = int(parts[0]), int(parts[8])
            except ValueError:
                continue
            counters[name] = (rx, tx)
            was = self._net_prev.get(name)
            if was is None or elapsed is None:
                rx_rate = tx_rate = 0.0
            else:
                # max(0, ...): an interface that goes down and comes back up
                # starts its counters again, and a negative throughput on a
                # graph is a spike downwards that never happened.
                rx_rate = max(0.0, (rx - was[0]) / elapsed)
                tx_rate = max(0.0, (tx - was[1]) / elapsed)
            quality, level = wireless.get(name, (None, None))
            found.append(
                Interface(
                    name=name,
                    rx=rx,
                    tx=tx,
                    rx_rate=rx_rate,
                    tx_rate=tx_rate,
                    state=(
                        self.root.read(f"sys/class/net/{name}/operstate") or ""
                    ).strip()
                    or "unknown",
                    quality=quality,
                    signal=level,
                )
            )
        self._net_prev = counters
        # Loopback last. It is not a lie -- it carries real traffic -- but it is
        # never the answer to "what is using my data", and on a phone with one
        # wlan and one rmnet it would otherwise sit at the top of the list.
        return tuple(
            sorted(found, key=lambda i: (i.name == "lo", -i.rx - i.tx, i.name))
        )

    def _wireless(self) -> dict[str, tuple[float | None, int | None]]:
        """How good the wireless is, from the one column that means something.

        /proc/net/wireless has three figures per interface -- link, level,
        noise -- and only one of them can be read without knowing the driver.

        The *link* column is a figure of merit whose denominator is not in the
        file: 70 for the mac80211 stack, 100 for several vendor drivers, and
        nothing says which. Dividing by the wrong one is a made-up percentage,
        so it is not used at all. This phone's Realtek reports 73 there, which
        read as "signal 104%, clamped to 100" for as long as it was.

        The *level* column carries its own units in its sign, which is the one
        piece of luck here. Negative is dBm, the way every driver on the
        mac80211 path reports it; zero or above is the driver's own 0-100
        figure. So a negative reading is converted through the ramp below and
        shown as dBm as well, and a positive one is taken at face value.
        """
        out: dict[str, tuple[float | None, int | None]] = {}
        for line in (self.root.read("proc/net/wireless") or "").splitlines()[2:]:
            name, _, rest = line.partition(":")
            parts = rest.split()
            if len(parts) < 3:
                continue
            try:
                # Printed with a trailing dot, which float() will not take.
                level = int(float(parts[2].rstrip(".")))
            except ValueError:
                continue
            if level < 0:
                out[name.strip()] = (dbm_quality(level), level)
            else:
                out[name.strip()] = (_clamp(level / 100.0), None)
        return out

    # --- disks -----------------------------------------------------------

    def _disks(self) -> tuple[Disk, ...]:
        seen: set[str] = set()
        disks: list[Disk] = []
        for line in (self.root.read("proc/self/mounts") or "").splitlines():
            parts = line.split()
            if len(parts) < 3 or parts[2] not in REAL_FILESYSTEMS:
                continue
            device, mount = _unescape_mount(parts[0]), _unescape_mount(parts[1])
            if mount in seen:
                continue
            seen.add(mount)
            usage = self.root.usage(mount)
            if usage is None or usage[0] <= 0:
                continue
            disks.append(
                Disk(mount=mount, device=device, total=usage[0], used=usage[1])
            )
        return tuple(sorted(disks, key=lambda d: (d.mount != "/", d.mount)))

    def _io(self, elapsed: float | None) -> Io:
        """Sectors read and written across the real disks, as bytes a second.

        Whole devices only: /proc/diskstats lists every partition as well, and
        adding sda and sda1 together double-counts everything on it.
        """
        names: dict[str, tuple[int, int]] = {}
        for line in (self.root.read("proc/diskstats") or "").splitlines():
            parts = line.split()
            if len(parts) < 10 or NOT_A_DISK.match(parts[2]):
                continue
            try:
                names[parts[2]] = (int(parts[5]), int(parts[9]))
            except ValueError:
                continue
        whole = {
            name: values
            for name, values in names.items()
            if not any(other != name and name.startswith(other) for other in names)
        }
        read = sum(v[0] for v in whole.values()) * 512
        written = sum(v[1] for v in whole.values()) * 512
        was, self._io_prev = self._io_prev, (read, written)
        if was is None or elapsed is None:
            return Io(0.0, 0.0)
        return Io(
            read_rate=max(0.0, (read - was[0]) / elapsed),
            write_rate=max(0.0, (written - was[1]) / elapsed),
        )

    # --- battery ---------------------------------------------------------

    def _battery(self) -> Battery | None:
        base = "sys/class/power_supply"
        for name in sorted(self.root.listdir(base)):
            kind = (self.root.read(f"{base}/{name}/type") or "").strip()
            if kind != "Battery":
                continue
            raw = self.root.read(f"{base}/{name}/capacity")
            if raw is None:
                continue
            try:
                percent = int(raw.strip())
            except ValueError:
                continue
            status = (
                self.root.read(f"{base}/{name}/status") or ""
            ).strip() or "Unknown"
            return Battery(
                percent=percent, status=status, watts=self._watts(base, name)
            )
        return None

    def _watts(self, base: str, name: str) -> float | None:
        """What the phone is drawing, in watts.

        Two driver conventions and no way to pick without trying both:
        power_now is microwatts, and where it is missing the current and the
        voltage are there instead.
        """
        micro = _number(self.root.read(f"{base}/{name}/power_now"))
        if micro:
            return abs(micro) / 1e6
        current = _number(self.root.read(f"{base}/{name}/current_now"))
        volts = _number(self.root.read(f"{base}/{name}/voltage_now"))
        if current and volts:
            return abs(current) * volts / 1e12
        return None

    # --- processes -------------------------------------------------------

    def _processes(self, uptime: float) -> tuple[Process, ...]:
        elapsed = None
        if self._proc_uptime_prev is not None:
            elapsed = uptime - self._proc_uptime_prev
            if elapsed <= 0:
                elapsed = None
        self._proc_uptime_prev = uptime

        found: list[Process] = []
        seen: dict[int, tuple[float, float]] = {}
        for name in self.root.listdir("proc"):
            if not name.isdigit():
                continue
            proc = self._one_process(int(name), uptime, elapsed, seen)
            if proc is not None:
                found.append(proc)
        self._proc_prev = seen
        # Drop the metadata of processes that are gone, or a phone left open for
        # a day accumulates a row per short-lived shell command ever run.
        alive = {
            (p.pid, self._proc_prev[p.pid][0])
            for p in found
            if p.pid in self._proc_prev
        }
        self._meta = {key: value for key, value in self._meta.items() if key in alive}
        return tuple(found)

    def _one_process(
        self,
        pid: int,
        uptime: float,
        elapsed: float | None,
        seen: dict[int, tuple[float, float]],
    ) -> Process | None:
        raw = self.root.read(f"proc/{pid}/stat")
        if not raw:
            return None
        # The command is in parentheses and may contain spaces *and*
        # parentheses -- "(Web Content)", "(sh (deleted))" -- so the split is
        # from the last close paren rather than by whitespace.
        open_paren, close_paren = raw.find("("), raw.rfind(")")
        if open_paren < 0 or close_paren < open_paren:
            return None
        comm = raw[open_paren + 1 : close_paren]
        fields = raw[close_paren + 1 :].split()
        if len(fields) < STAT["rss"] - STAT_FIRST + 1:
            return None

        def field(name: str) -> str:
            return fields[STAT[name] - STAT_FIRST]

        try:
            state = field("state")
            ppid = int(field("ppid"))
            utime, stime = int(field("utime")), int(field("stime"))
            threads = int(field("threads"))
            started = int(field("starttime")) / HZ
            rss = int(field("rss")) * PAGE
        except ValueError:
            return None

        ticks = (utime + stime) / HZ
        seen[pid] = (started, ticks)
        was = self._proc_prev.get(pid)
        if was is not None and was[0] == started and elapsed:
            share = (ticks - was[1]) / (elapsed * self._cores)
        else:
            # No previous reading -- a new process, or the first tick of the
            # list. Its average since it started, so the very first list is
            # sorted by something real instead of by a column of zeroes.
            alive = max(0.001, uptime - started)
            share = ticks / (alive * self._cores)

        user, cmdline, name, app_key, app_name = self._process_meta(
            pid, started, comm, ppid
        )
        return Process(
            pid=pid,
            ppid=ppid,
            name=name,
            cmdline=cmdline,
            user=user,
            state=STATES.get(state, state),
            threads=threads,
            rss=rss,
            cpu=_clamp(share),
            seconds=ticks,
            app_key=app_key,
            app_name=app_name,
        )

    def _process_meta(
        self, pid: int, started: float, comm: str, ppid: int
    ) -> tuple[str, str, str, str, str]:
        """The three files that never change for a process, read once.

        Keyed by pid *and* start time. A pid is reused within minutes on a busy
        machine, and a cache keyed by pid alone eventually shows one process
        wearing a dead one's name and owner.
        """
        key = (pid, started)
        cached = self._meta.get(key)
        if cached is not None:
            return cached

        uid = 0
        for line in (self.root.read(f"proc/{pid}/status") or "").splitlines():
            if line.startswith("Uid:"):
                parts = line.split()
                if len(parts) > 1 and parts[1].isdigit():
                    uid = int(parts[1])
                break
        raw = self.root.read(f"proc/{pid}/cmdline") or ""
        cmdline = " ".join(part for part in raw.split("\0") if part)

        name = untruncated(comm, cmdline)
        app_key, app_name = _app_of(
            self.root.read(f"proc/{pid}/cgroup"), name, pid, ppid
        )
        value = (self.root.username(uid), cmdline, name, app_key, app_name)
        self._meta[key] = value
        return value

    # --- acting on one --------------------------------------------------

    def end(self, pid: int, *, force: bool = False) -> None:
        """Ask a process to stop, or make it.

        TERM by default because a process asked to stop can save what it was
        doing, which on a phone is the note somebody was typing. KILL is behind
        a second, differently worded button for exactly that reason.
        """
        self.root.signal(pid, signal.SIGKILL if force else signal.SIGTERM)


# --- grouping processes into apps ------------------------------------------


def untruncated(comm: str, cmdline: str) -> str:
    """The process's name, put back to its full length where it was cut.

    /proc/<pid>/stat carries fifteen characters of it. On a desktop that is
    rarely noticed; on the phone five of the eleven rows on the first screen of
    the task list read "moarchy-keyboar", "xdg-desktop-por", "evolution-sourc".

    The command line has the whole name in it, so the basename of the executable
    is the answer -- but only where it is plainly the same name made longer, and
    only where the kernel could have done the cutting. A process that renamed
    itself to something else entirely means it: firefox's content processes call
    themselves "Isolated Web Co", and turning that back into "firefox" because
    the binary is firefox would throw away the one thing that row had to say.
    """
    if len(comm) < COMM_MAX or not cmdline:
        return comm
    base = cmdline.split()[0].rsplit("/", 1)[-1]
    return base if base.startswith(comm) and len(base) > len(comm) else comm


def _unescape_unit(name: str) -> str:
    return UNIT_ESCAPE.sub(lambda m: chr(int(m.group(1), 16)), name)


def _pretty_app(app_id: str) -> str:
    """A unit's app id as something worth putting in a list.

    `org.gnome.Calculator` is the name of a file, not of an app. The last dotted
    component is, near enough, every time it is one of these ids -- and where it
    is not a dotted id the string is already a program name.
    """
    app_id = _unescape_unit(app_id)
    if app_id.count(".") >= 2:
        tail = app_id.rsplit(".", 1)[1]
        if tail:
            return tail
    return app_id


def _app_of(cgroup: str | None, comm: str, pid: int, ppid: int) -> tuple[str, str]:
    """Which app a process belongs to, and what that app is called.

    Two answers, in order of how much they can be trusted:

    1. The session's own. A desktop entry launched through a systemd user
       session gets a cgroup named after it -- `app-org.gnome.Calculator-*.scope`
       -- and every helper process the app forks inherits it. That is the
       session telling us what the app is, and it is believed.

    2. The program's name. Where there is no such unit -- a compositor that
       spawns apps itself, a process started from a shell, anything on a system
       without a user session -- processes are grouped by what they are running.
       Twenty renderer processes become one row called `chrome`, which is the
       useful half of the grouping even when the precise half is not available.

    Kernel threads are one group. There are ninety of them on an idle phone,
    they are not apps by any reading, and a list they can crowd out is a list
    where the app eating the battery is on page two.
    """
    if pid == 2 or ppid == 2:
        return "kernel", "Kernel threads"
    for line in (cgroup or "").splitlines():
        path = line.rpartition(":")[2]
        unit = path.rsplit("/", 1)[-1]
        match = APP_UNIT.match(unit)
        if match:
            app_id = match.group("id")
            return f"unit:{_unescape_unit(app_id)}", _pretty_app(app_id)
    return f"comm:{comm}", comm


def group_apps(processes: tuple[Process, ...]) -> tuple[AppGroup, ...]:
    """One row per app, busiest first."""
    buckets: dict[str, list[Process]] = {}
    for proc in processes:
        buckets.setdefault(proc.app_key, []).append(proc)
    groups = []
    for key, members in buckets.items():
        first = max(members, key=lambda p: p.rss)
        groups.append(
            AppGroup(
                key=key,
                name=members[0].app_name,
                # Lowest pid first: for anything with helper processes that is
                # the one that started them, so it is the one to signal first.
                pids=tuple(sorted(p.pid for p in members)),
                cpu=sum(p.cpu for p in members),
                rss=sum(p.rss for p in members),
                user=first.user,
            )
        )
    return tuple(sorted(groups, key=lambda g: (-g.cpu, -g.rss, g.name)))


# --- history ---------------------------------------------------------------


class History:
    """The last N readings of one number, for something to draw.

    /proc has no past in it: a graph of the last two minutes exists only
    because the app kept the samples. A deque with a maxlen is the whole
    mechanism, and the size is how many pixels wide the graph is.
    """

    def __init__(self, size: int) -> None:
        self.size = size
        self.values: deque[float] = deque(maxlen=size)

    def push(self, value: float) -> None:
        self.values.append(float(value))

    @property
    def peak(self) -> float:
        return max(self.values) if self.values else 0.0

    @property
    def last(self) -> float:
        return self.values[-1] if self.values else 0.0

    def as_tuple(self) -> tuple[float, ...]:
        return tuple(self.values)

    def clear(self) -> None:
        self.values.clear()


# --- saying numbers out loud ----------------------------------------------

# Powers of a thousand, not of 1024. The phone's own storage is sold in these
# units and so is its data allowance, and GNOME's own tools report them this
# way -- an app that disagreed with the settings panel about how much memory is
# free would be the one that is wrong, whatever the arithmetic says.
UNITS = ("B", "kB", "MB", "GB", "TB")


def human_bytes(value: float, *, digits: int | None = None) -> str:
    scale = 0
    amount = float(max(0.0, value))
    while amount >= 1000 and scale < len(UNITS) - 1:
        amount /= 1000.0
        scale += 1
    if digits is None:
        # One decimal below ten, none above: "1.4 GB" and "428 MB" are both
        # three glyphs of information, which is what fits in a phone's column.
        digits = 1 if amount < 10 and scale else 0
    return f"{amount:.{digits}f} {UNITS[scale]}"


def human_rate(value: float) -> str:
    return f"{human_bytes(value)}/s"


def human_seconds(value: float) -> str:
    """A duration as the largest two units that say anything."""
    seconds = int(max(0, value))
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {seconds}s"
    return f"{seconds}s"


def human_percent(value: float) -> str:
    return f"{round(_clamp(value) * 100)}%"


def task_percent(value: float) -> str:
    """A process's share of the machine, which is usually a small number.

    Rounded to whole percent, the busiest twenty processes on an idle phone all
    read "0%" and the list appears to be sorted by nothing. One decimal below
    ten per cent is the smallest change that makes the order visible.
    """
    share = _clamp(value) * 100
    return f"{share:.1f}%" if share < 9.95 else f"{round(share)}%"


# Where a signal in dBm stops improving and where it stops working. -40 is a
# phone on top of the router and -85 is the edge of the flat; the useful range
# between them is what a bar on a screen is drawn from.
DBM_BEST, DBM_WORST = -40.0, -85.0


def dbm_quality(dbm: float) -> float:
    """A signal strength as a fraction, for something with a bar to fill."""
    return _clamp((dbm - DBM_WORST) / (DBM_BEST - DBM_WORST))


def _clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def _number(text: str | None) -> float | None:
    try:
        return float((text or "").strip())
    except ValueError:
        return None


def _unescape_mount(text: str) -> str:
    """Undo the octal escapes /proc/self/mounts uses for spaces and tabs."""
    return re.sub(r"\\(\d{3})", lambda m: chr(int(m.group(1), 8)), text)
