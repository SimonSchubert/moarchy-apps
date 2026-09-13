"""The arithmetic, against machines written by hand.

Everything here is a fixture: a directory of files shaped like /proc, read by
the same code that reads the kernel's. That is what lets the numbers be asserted
exactly -- "two hundred busy ticks out of a thousand is twenty per cent" is a
claim a test can make about a file it wrote, and cannot make about a phone.

The last class is the exception and is deliberately on the other side: it reads
the real /proc, where there is one, and asserts only that the answers are
*sane*. A fixture proves the parser is right about a file; only the live kernel
proves the file is the one the parser was written for.

No GTK anywhere in here. The reason this module has none is the reason this file
runs on a Mac.
"""

from __future__ import annotations

import os
import signal
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent), str(HERE.parent.parent.parent / "shared")]

from fixtures import put, write_machine, write_process, write_reel  # noqa: E402
from moarchy_vitals.sysinfo import (  # noqa: E402
    HZ,
    History,
    Reel,
    Sampler,
    Sysroot,
    group_apps,
    human_bytes,
    human_percent,
    human_rate,
    human_seconds,
    sysroot_for,
    task_percent,
)


class MachineTest(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.addCleanup(self.dir.cleanup)

    def sampler(self, **kwargs) -> Sampler:
        write_machine(self.root, **kwargs)
        return Sampler(Sysroot(self.root))

    def rewrite(self, **kwargs) -> None:
        write_machine(self.root, **kwargs)


class TheProcessor(MachineTest):
    def test_the_first_reading_is_the_average_since_boot(self):
        # 300 busy of 2000 total across two cores. There is nothing to subtract
        # from, and both of the alternatives -- zero, or a hundred -- are lies.
        sample = self.sampler(cores=((100, 900), (200, 800))).sample()
        self.assertAlmostEqual(sample.cpu.total, 0.15, places=3)

    def test_the_second_reading_is_the_difference_between_them(self):
        sampler = self.sampler(uptime=1000.0, cores=((100, 900), (100, 900)))
        sampler.sample()
        # Half of the next 200 ticks on each core were busy.
        self.rewrite(uptime=1002.0, cores=((200, 1000), (200, 1000)))
        sample = sampler.sample()
        self.assertAlmostEqual(sample.cpu.total, 0.5, places=3)
        self.assertEqual(len(sample.cpu.cores), 2)
        self.assertAlmostEqual(sample.cpu.cores[0], 0.5, places=3)

    def test_a_busy_core_and_an_idle_one_are_told_apart(self):
        sampler = self.sampler(uptime=1000.0, cores=((100, 900), (100, 900)))
        sampler.sample()
        self.rewrite(uptime=1002.0, cores=((300, 900), (100, 1100)))
        cores = sampler.sample().cpu.cores
        self.assertAlmostEqual(cores[0], 1.0, places=3)
        self.assertAlmostEqual(cores[1], 0.0, places=3)

    def test_waiting_for_the_disk_is_not_load(self):
        # iowait is field five, and counting it as busy reports every boot as
        # a machine at a hundred per cent.
        put(
            self.root,
            "proc/stat",
            "cpu  0 0 0 500 500 0 0 0 0 0\ncpu0 0 0 0 500 500 0 0 0 0 0\n",
        )
        write_machine(self.root, uptime=1000.0)
        put(
            self.root,
            "proc/stat",
            "cpu  0 0 0 500 500 0 0 0 0 0\ncpu0 0 0 0 500 500 0 0 0 0 0\n",
        )
        self.assertEqual(Sampler(Sysroot(self.root)).sample().cpu.total, 0.0)

    def test_the_load_average_and_the_task_count_come_off_one_line(self):
        sample = self.sampler(load=(1.25, 0.75, 0.5), tasks="3/188").sample()
        self.assertEqual(sample.cpu.load, (1.25, 0.75, 0.5))
        self.assertEqual(sample.cpu.tasks, 188)
        self.assertEqual(sample.cpu.running, 3)

    def test_the_processor_zone_is_preferred_to_the_hotter_one(self):
        # thermal_zone0 is the battery at 30 degrees; the cpu zone is the answer
        # even though picking the hottest zone would be easier.
        sample = self.sampler(temperature=61_000).sample()
        self.assertAlmostEqual(sample.cpu.temperature, 61.0, places=3)

    def test_a_machine_with_no_thermal_zone_says_so(self):
        sample = self.sampler(temperature=None).sample()
        self.assertIsNone(sample.cpu.temperature)

    def test_the_clock_speed_is_the_average_of_the_cores(self):
        sample = self.sampler().sample()
        self.assertAlmostEqual(sample.cpu.frequency, 1000.0, places=1)

    def test_an_empty_proc_is_an_idle_machine_rather_than_an_exception(self):
        sample = Sampler(Sysroot(self.root)).sample()
        self.assertEqual(sample.cpu.total, 0.0)
        self.assertEqual(sample.memory.total, 0)
        self.assertEqual(sample.processes, ())


class TheMemory(MachineTest):
    def test_used_is_total_minus_available(self):
        sample = self.sampler(mem_total=1_000_000, mem_available=400_000).sample()
        self.assertEqual(sample.memory.total, 1_024_000_000)
        self.assertEqual(sample.memory.used, 614_400_000)
        self.assertAlmostEqual(sample.memory.fraction, 0.6, places=3)

    def test_the_page_cache_is_reported_apart_from_it(self):
        # Cached plus SReclaimable plus Buffers: the kernel calls three things
        # the page cache and a bar that showed one of them is wrong by the
        # other two.
        sample = self.sampler().sample()
        self.assertEqual(sample.memory.cached, 130_000 * 1024)

    def test_a_machine_with_no_swap_has_no_swap_bar(self):
        sample = self.sampler(swap=(0, 0)).sample()
        self.assertEqual(sample.memory.swap_total, 0)
        self.assertEqual(sample.memory.swap_fraction, 0.0)

    def test_swap_in_use_is_what_is_not_free(self):
        sample = self.sampler(swap=(500_000, 300_000)).sample()
        self.assertEqual(sample.memory.swap_used, 200_000 * 1024)
        self.assertAlmostEqual(sample.memory.swap_fraction, 0.4, places=3)


class TheNetwork(MachineTest):
    def test_the_first_reading_has_no_rate(self):
        sample = self.sampler().sample()
        wlan = next(i for i in sample.interfaces if i.name == "wlan0")
        self.assertEqual(wlan.rx_rate, 0.0)
        self.assertEqual(wlan.rx, 5_000)

    def test_a_rate_is_the_difference_over_the_time_between(self):
        sampler = self.sampler(uptime=1000.0, net={"wlan0": (1_000, 500)})
        sampler.sample()
        self.rewrite(uptime=1002.0, net={"wlan0": (3_000, 1_500)})
        wlan = sampler.sample().interfaces[0]
        self.assertAlmostEqual(wlan.rx_rate, 1000.0, places=3)
        self.assertAlmostEqual(wlan.tx_rate, 500.0, places=3)

    def test_an_interface_whose_counters_restart_does_not_go_backwards(self):
        # An interface that goes down and comes back up starts again from zero,
        # and a negative throughput is a spike downwards that never happened.
        sampler = self.sampler(uptime=1000.0, net={"wlan0": (900_000, 900_000)})
        sampler.sample()
        self.rewrite(uptime=1002.0, net={"wlan0": (12, 12)})
        wlan = sampler.sample().interfaces[0]
        self.assertEqual(wlan.rx_rate, 0.0)
        self.assertEqual(wlan.tx_rate, 0.0)

    def test_loopback_is_last(self):
        sample = self.sampler(
            net={"lo": (9_000_000, 9_000_000), "wlan0": (5, 5)}
        ).sample()
        self.assertEqual(sample.interfaces[-1].name, "lo")

    def test_a_wireless_interface_carries_its_signal(self):
        wlan = next(i for i in self.sampler().sample().interfaces if i.name == "wlan0")
        self.assertTrue(wlan.wireless)
        self.assertEqual(wlan.signal, -60)
        # -60 dBm is a little over half way between the ends of the ramp.
        self.assertAlmostEqual(wlan.quality, 25 / 45, places=3)

    def test_a_driver_that_reports_a_percentage_instead_of_dbm(self):
        # The phone's Realtek does this: a positive level, which is its own
        # 0-100 figure and not dBm. Read as dBm it is a signal from the future.
        wlan = next(
            i for i in self.sampler(signal=47).sample().interfaces if i.name == "wlan0"
        )
        self.assertAlmostEqual(wlan.quality, 0.47, places=3)
        self.assertIsNone(wlan.signal)
        self.assertTrue(wlan.wireless)

    def test_the_link_column_is_not_a_percentage_of_anything(self):
        # 35 out of "70 or 100, and the file does not say which". Whatever the
        # quality is, it is not read from there.
        wlan = next(
            i for i in self.sampler(signal=-40).sample().interfaces if i.name == "wlan0"
        )
        self.assertEqual(wlan.quality, 1.0)

    def test_a_wired_interface_carries_none(self):
        sample = self.sampler(net={"eth0": (1, 1)}, wireless=False).sample()
        self.assertFalse(sample.interfaces[0].wireless)

    def test_a_machine_with_no_wireless_file_still_reads_its_interfaces(self):
        sample = self.sampler(wireless=False).sample()
        self.assertTrue(sample.interfaces)


class TheDisks(MachineTest):
    def test_only_filesystems_worth_showing(self):
        mounts = {disk.mount for disk in self.sampler().sample().disks}
        self.assertIn("/", mounts)
        self.assertNotIn("/proc", mounts)
        self.assertNotIn("/run", mounts)

    def test_a_mount_point_with_a_space_in_it(self):
        # /proc/self/mounts escapes a space as \040, and an SD card mounted by
        # its label is where that actually happens.
        mounts = {disk.mount for disk in self.sampler().sample().disks}
        self.assertIn("/media/SD card", mounts)

    def test_usage_comes_from_the_filesystem_rather_than_from_proc(self):
        root = next(d for d in self.sampler().sample().disks if d.mount == "/")
        self.assertEqual(root.total, 8_000_000_000)
        self.assertEqual(root.used, 2_000_000_000)
        self.assertAlmostEqual(root.fraction, 0.25, places=3)

    def test_disk_traffic_counts_the_disk_and_not_its_partitions(self):
        sampler = self.sampler(uptime=1000.0, disk_sectors=(1000, 2000))
        sampler.sample()
        self.rewrite(uptime=1002.0, disk_sectors=(3000, 4000))
        io = sampler.sample().io
        # 2000 sectors of 512 bytes in two seconds -- mmcblk0 only. Counting
        # mmcblk0p1 as well would double it, and zram is not a disk.
        self.assertAlmostEqual(io.read_rate, 512_000.0, places=1)
        self.assertAlmostEqual(io.write_rate, 512_000.0, places=1)


class TheBattery(MachineTest):
    def test_the_charge_and_what_it_is_doing(self):
        battery = self.sampler(battery=42).sample().battery
        self.assertEqual(battery.percent, 42)
        self.assertEqual(battery.status, "Discharging")
        self.assertAlmostEqual(battery.watts, 2.5, places=3)

    def test_the_mains_is_not_a_battery(self):
        # /sys/class/power_supply holds both, and only one of them has a charge.
        put(self.root, "sys/class/power_supply/AC/online", "1\n")
        self.assertIsNotNone(self.sampler(battery=42).sample().battery)

    def test_a_machine_with_no_battery_has_no_panel(self):
        self.assertIsNone(self.sampler(battery=None).sample().battery)

    def test_a_driver_that_reports_current_and_voltage_instead(self):
        write_machine(self.root, battery=50)
        os.remove(self.root / "sys/class/power_supply/BAT0/power_now")
        put(self.root, "sys/class/power_supply/BAT0/current_now", "500000\n")
        put(self.root, "sys/class/power_supply/BAT0/voltage_now", "4000000\n")
        battery = Sampler(Sysroot(self.root)).sample().battery
        self.assertAlmostEqual(battery.watts, 2.0, places=3)


class TheProcesses(MachineTest):
    def test_what_is_running(self):
        sample = self.sampler().sample()
        names = {p.name for p in sample.processes}
        self.assertEqual(names, {"systemd", "firefox", "Isolated Web Co"})

    def test_a_command_with_spaces_and_parens_in_it(self):
        # The comm field is in parentheses and may contain both, so the split
        # is from the last close paren rather than by whitespace.
        write_machine(self.root, processes=())
        write_process(
            self.root, 1000.0, 77, "sh (deleted) (x)", 10, 4096, cgroup="0::/x"
        )
        sample = Sampler(Sysroot(self.root)).sample()
        self.assertEqual(sample.processes[0].name, "sh (deleted) (x)")

    def test_the_first_reading_is_the_average_since_the_process_started(self):
        # 1200 ticks over 990 seconds of life on two cores. Zero would sort the
        # first list by nothing at all.
        firefox = next(
            p for p in self.sampler().sample().processes if p.name == "firefox"
        )
        self.assertAlmostEqual(firefox.cpu, (1200 / HZ) / (990 * 2), places=4)

    def test_the_second_reading_is_the_difference(self):
        sampler = self.sampler(uptime=1000.0)
        sampler.sample()
        write_machine(
            self.root,
            uptime=1002.0,
            processes=((420, "firefox", 1600, 1024, 1, 1000, "0::/x", 2),),
        )
        firefox = sampler.sample().processes[0]
        # 400 ticks is four seconds of processor time in two seconds on two
        # cores, which is the whole machine.
        self.assertAlmostEqual(firefox.cpu, 1.0, places=3)

    def test_a_pid_that_has_been_reused_is_not_the_old_process(self):
        sampler = self.sampler(uptime=1000.0)
        sampler.sample()
        # The clock has to move too, or no time has passed and the sampler
        # rightly hands back the reading it already had.
        write_machine(self.root, uptime=1002.0, processes=())
        write_process(
            self.root, 1002.0, 420, "bash", 4, 1024, cgroup="0::/new", started=1001.0
        )
        again = sampler.sample().processes[0]
        self.assertEqual(again.name, "bash")
        # Its own short life, not the ticks the dead firefox had accumulated.
        self.assertLess(again.cpu, 0.1)

    def test_a_name_the_kernel_cut_short_is_put_back(self):
        # /proc gives fifteen characters. The phone's task list was full of
        # rows reading "moarchy-keyboar" and "xdg-desktop-por".
        write_machine(self.root, processes=())
        write_process(
            self.root, 1000.0, 700, "moarchy-keyboar", 10, 4096, cgroup="0::/session"
        )
        put(self.root, "proc/700/cmdline", "/usr/bin/moarchy-keyboard\0")
        sample = Sampler(Sysroot(self.root)).sample()
        self.assertEqual(sample.processes[0].name, "moarchy-keyboard")
        self.assertEqual(sample.apps[0].name, "moarchy-keyboard")

    def test_a_process_that_renamed_itself_keeps_the_name_it_chose(self):
        # firefox's content processes are "Isolated Web Co" and the binary is
        # firefox. That is not truncation, it is the process saying what it is.
        write_machine(self.root, processes=())
        write_process(
            self.root, 1000.0, 701, "Isolated Web Co", 10, 4096, cgroup="0::/session"
        )
        put(self.root, "proc/701/cmdline", "/usr/lib/firefox/firefox\0-contentproc\0")
        self.assertEqual(
            Sampler(Sysroot(self.root)).sample().processes[0].name, "Isolated Web Co"
        )

    def test_a_short_name_is_never_stretched(self):
        # "bash" is four characters, so the kernel cut nothing, so there is
        # nothing to put back -- whatever the command line looks like.
        write_machine(self.root, processes=())
        write_process(self.root, 1000.0, 702, "bash", 10, 4096, cgroup="0::/session")
        put(self.root, "proc/702/cmdline", "/usr/bin/bash-completion-helper\0")
        self.assertEqual(Sampler(Sysroot(self.root)).sample().processes[0].name, "bash")

    def test_a_kernel_thread_keeps_its_name_with_no_command_line(self):
        write_machine(self.root, processes=())
        write_process(self.root, 1000.0, 703, "irq/25-mmc0-err", 4, 0, ppid=2, uid=0)
        self.assertEqual(
            Sampler(Sysroot(self.root)).sample().processes[0].name, "irq/25-mmc0-err"
        )

    def test_the_owner_comes_from_the_sysroot_own_passwd(self):
        firefox = next(
            p for p in self.sampler().sample().processes if p.name == "firefox"
        )
        self.assertEqual(firefox.user, "simon")

    def test_memory_is_resident_pages_rather_than_address_space(self):
        firefox = next(
            p for p in self.sampler().sample().processes if p.name == "firefox"
        )
        self.assertAlmostEqual(firefox.rss / (200 * 1024 * 1024), 1.0, places=2)

    def test_a_process_that_ends_between_two_files_is_skipped(self):
        write_machine(self.root, processes=())
        (self.root / "proc/999").mkdir(parents=True)
        sample = Sampler(Sysroot(self.root)).sample()
        self.assertEqual(sample.processes, ())

    def test_the_overview_is_skippable(self):
        # The expensive half is optional, because the overview needs none of it.
        sample = self.sampler().sample(processes=False)
        self.assertEqual(sample.processes, ())
        self.assertGreater(sample.memory.total, 0)


class GroupingIntoApps(MachineTest):
    def test_a_systemd_app_unit_is_one_app(self):
        sample = self.sampler().sample()
        firefox = next(g for g in sample.apps if g.name == "firefox")
        self.assertEqual(firefox.count, 2)
        self.assertEqual(firefox.pids, (420, 421))

    def test_an_app_id_is_shown_as_the_name_it_ends_with(self):
        write_machine(self.root, processes=())
        write_process(
            self.root,
            1000.0,
            500,
            "moarchy-keep",
            10,
            1024,
            cgroup="0::/user.slice/user@1000.service/app.slice/app-gnome-org.moarchy.Keep-500.scope",
        )
        group = Sampler(Sysroot(self.root)).sample().apps[0]
        self.assertEqual(group.name, "Keep")

    def test_a_unit_with_an_escaped_dash_in_it(self):
        write_machine(self.root, processes=())
        write_process(
            self.root,
            1000.0,
            501,
            "x",
            10,
            1024,
            cgroup="0::/user.slice/app.slice/app-my\\x2dapp-501.scope",
        )
        self.assertEqual(Sampler(Sysroot(self.root)).sample().apps[0].name, "my-app")

    def test_without_a_unit_processes_group_by_what_they_are_running(self):
        # A compositor that launches apps itself gives them no unit, and the
        # useful half of the grouping is still available: twenty renderers with
        # one name are one row.
        write_machine(self.root, processes=())
        for pid in (600, 601, 602):
            write_process(
                self.root, 1000.0, pid, "chrome", 10, 1024, cgroup="0::/session"
            )
        groups = Sampler(Sysroot(self.root)).sample().apps
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0].count, 3)

    def test_kernel_threads_are_one_group_rather_than_ninety(self):
        write_machine(self.root, processes=())
        write_process(self.root, 1000.0, 2, "kthreadd", 4, 0, ppid=0, uid=0)
        for pid in (10, 11, 12):
            write_process(self.root, 1000.0, pid, f"kworker/{pid}", 4, 0, ppid=2, uid=0)
        groups = Sampler(Sysroot(self.root)).sample().apps
        self.assertEqual([g.name for g in groups], ["Kernel threads"])
        self.assertEqual(groups[0].count, 4)

    def test_a_kernel_thread_has_no_command_line(self):
        write_machine(self.root, processes=())
        write_process(self.root, 1000.0, 11, "kworker/0:1", 4, 0, ppid=2, uid=0)
        self.assertTrue(Sampler(Sysroot(self.root)).sample().processes[0].kernel)

    def test_the_busiest_app_is_first(self):
        groups = group_apps(self.sampler().sample().processes)
        self.assertEqual(
            [g.cpu for g in groups], sorted((g.cpu for g in groups), reverse=True)
        )


class SignallingSomething(MachineTest):
    def test_a_fixture_never_signals_anything(self):
        # The demo data has a pid 1 in it, and os.kill(1, SIGKILL) in the
        # container this is developed in is not a mistake anybody gets to make
        # twice. A reel records the attempt instead.
        root = Reel(self.root)
        Sampler(root).end(4242, force=True)
        self.assertEqual(root.signalled, [(4242, signal.SIGKILL)])

    def test_asking_and_forcing_are_different_signals(self):
        root = Reel(self.root)
        sampler = Sampler(root)
        sampler.end(10, force=False)
        sampler.end(11, force=True)
        self.assertEqual(root.signalled, [(10, signal.SIGTERM), (11, signal.SIGKILL)])

    def test_init_is_refused_outright(self):
        with self.assertRaises(PermissionError):
            Sysroot("/").signal(1, signal.SIGTERM)


class TheReel(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.addCleanup(self.dir.cleanup)
        write_reel(self.root, frames=4)

    def test_a_directory_of_frames_is_read_one_per_sample(self):
        reel = Reel(self.root)
        sampler = Sampler(reel)
        sampler.sample()
        self.assertEqual(reel.index, 0)
        sampler.sample()
        self.assertEqual(reel.index, 1)

    def test_the_first_frame_is_not_skipped(self):
        reel = Reel(self.root)
        self.assertEqual(Sampler(reel).sample().uptime, 1000.0)

    def test_each_frame_is_a_step_further_on(self):
        sampler = Sampler(Reel(self.root))
        uptimes = [sampler.sample().uptime for _ in range(4)]
        self.assertEqual(uptimes, [1000.0, 1002.0, 1004.0, 1006.0])

    def test_what_a_frame_does_not_carry_comes_from_the_base(self):
        # Only what changes is written per frame; the rest would be the same
        # file two thousand times.
        sampler = Sampler(Reel(self.root))
        sampler.sample()
        self.assertEqual(sampler.sample().processes[0].user, "root")

    def test_a_reel_that_has_run_out_holds_its_last_reading(self):
        reel = Reel(self.root)
        sampler = Sampler(reel)
        for _ in range(4):
            last = sampler.sample()
        self.assertTrue(reel.exhausted)
        # No time passes, so there is nothing to divide by and the honest
        # answer is the reading already on screen.
        self.assertIs(sampler.sample(), last)

    def test_the_rates_across_a_reel_are_what_it_was_written_with(self):
        sampler = Sampler(Reel(self.root))
        sampler.sample()
        sample = sampler.sample()
        # 100 busy ticks of 200 elapsed on each core, which is half a core each.
        self.assertAlmostEqual(sample.cpu.total, 0.5, places=3)
        # 20 kB more received over two seconds.
        self.assertAlmostEqual(sample.interfaces[0].rx_rate, 10_000.0, places=1)

    def test_a_plain_directory_is_not_a_reel(self):
        plain = Path(self.dir.name) / "plain"
        write_machine(plain)
        self.assertNotIsInstance(sysroot_for(str(plain)), Reel)
        self.assertIsInstance(sysroot_for(str(self.root)), Reel)

    def test_no_directory_at_all_is_the_real_machine(self):
        self.assertEqual(sysroot_for(None).root, Path("/"))
        self.assertTrue(sysroot_for(None).live)


class KeepingAHistory(unittest.TestCase):
    def test_it_holds_the_last_n_and_drops_the_rest(self):
        history = History(3)
        for value in (1, 2, 3, 4):
            history.push(value)
        self.assertEqual(history.as_tuple(), (2.0, 3.0, 4.0))
        self.assertEqual(history.last, 4.0)
        self.assertEqual(history.peak, 4.0)

    def test_an_empty_history_has_no_peak_to_scale_to(self):
        self.assertEqual(History(3).peak, 0.0)


class SayingNumbers(unittest.TestCase):
    def test_bytes_in_the_units_the_phone_is_sold_in(self):
        self.assertEqual(human_bytes(0), "0 B")
        self.assertEqual(human_bytes(999), "999 B")
        self.assertEqual(human_bytes(1_500), "1.5 kB")
        self.assertEqual(human_bytes(1_500_000), "1.5 MB")
        self.assertEqual(human_bytes(3_072_000_000), "3.1 GB")

    def test_a_rate_is_bytes_with_a_second_on_it(self):
        self.assertEqual(human_rate(1_500_000), "1.5 MB/s")

    def test_a_duration_is_the_two_units_that_say_something(self):
        self.assertEqual(human_seconds(45), "45s")
        self.assertEqual(human_seconds(3 * 60 + 4), "3m 4s")
        self.assertEqual(human_seconds(3 * 3600 + 120), "3h 2m")
        self.assertEqual(human_seconds(50 * 3600), "2d 2h")

    def test_a_percentage_is_rounded_and_never_over_a_hundred(self):
        self.assertEqual(human_percent(0.126), "13%")
        self.assertEqual(human_percent(1.4), "100%")

    def test_a_task_list_needs_a_decimal_or_it_is_all_zeroes(self):
        self.assertEqual(task_percent(0.004), "0.4%")
        self.assertEqual(task_percent(0.0999), "10%")
        self.assertEqual(task_percent(0.42), "42%")


@unittest.skipUnless(Path("/proc/stat").exists(), "no /proc on this machine")
class OnThisMachine(unittest.TestCase):
    """The other half: the fixtures prove the parser, this proves the format.

    Nothing here asserts a value, because the machine running it is a container
    one day and a phone the next. What it asserts is that the real files parse
    at all -- which is the failure a fixture cannot catch, because a fixture is
    written by the same person as the parser.
    """

    def test_the_real_proc_reads(self):
        sample = Sampler(Sysroot("/")).sample()
        self.assertGreater(sample.memory.total, 0)
        self.assertGreaterEqual(sample.cpu.total, 0.0)
        self.assertLessEqual(sample.cpu.total, 1.0)
        self.assertGreater(len(sample.cpu.cores), 0)
        self.assertGreater(sample.uptime, 0.0)

    def test_this_very_process_is_in_the_list(self):
        sample = Sampler(Sysroot("/")).sample()
        self.assertIn(os.getpid(), {p.pid for p in sample.processes})

    def test_every_process_belongs_to_exactly_one_app(self):
        sample = Sampler(Sysroot("/")).sample()
        grouped = sum(group.count for group in sample.apps)
        self.assertEqual(grouped, len(sample.processes))

    def test_two_readings_in_a_row_give_a_believable_load(self):
        sampler = Sampler(Sysroot("/"))
        sampler.sample()
        for _ in range(400_000):  # something for the processor to have done
            pass
        sample = sampler.sample()
        self.assertGreaterEqual(sample.cpu.total, 0.0)
        self.assertLessEqual(sample.cpu.total, 1.0)


if __name__ == "__main__":
    unittest.main()
