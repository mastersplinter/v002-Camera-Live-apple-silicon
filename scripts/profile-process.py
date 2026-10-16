#!/usr/bin/env python3
"""Measure a finite macOS diagnostic command, excluding startup from steady state.

Example: python3 scripts/profile-process.py --output .build/profile.json -- \
    'dist/Camera Live.app/Contents/MacOS/camera-live-diagnostics' --test-pattern

Uses the kernel's process CPU counters and physical footprint, which includes
memory charged to the process beyond RSS (for example, graphics allocations).
CPU percent is relative to one core. This is not a whole-system energy measure.
"""
import argparse
import ctypes
import json
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import time


class Usage(ctypes.Structure):
    # RUSAGE_INFO_V2 from the macOS SDK's sys/resource.h.
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        'user_time', 'system_time', 'pkg_idle_wkups', 'interrupt_wkups', 'pageins',
        'wired_size', 'resident_size', 'phys_footprint', 'proc_start_abstime',
        'proc_exit_abstime', 'child_user_time', 'child_system_time',
        'child_pkg_idle_wkups', 'child_interrupt_wkups', 'child_pageins',
        'child_elapsed_abstime', 'diskio_bytesread', 'diskio_byteswritten')]


class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]


def summarize(samples):
    first, last = samples[0], samples[-1]
    duration = last['seconds'] - first['seconds']
    return dict(measured_seconds=duration,
                cpu_percent=100 * (last['cpu_seconds'] - first['cpu_seconds']) / duration,
                median_footprint_mib=statistics.median(s['footprint_bytes'] for s in samples) / 2**20,
                max_footprint_mib=max(s['footprint_bytes'] for s in samples) / 2**20,
                first_footprint_mib=first['footprint_bytes'] / 2**20,
                last_footprint_mib=last['footprint_bytes'] / 2**20,
                idle_wakeups_per_second=(last['idle_wakeups'] - first['idle_wakeups']) / duration,
                interrupt_wakeups_per_second=(last['interrupt_wakeups'] - first['interrupt_wakeups']) / duration)


def phase_summaries(log, samples):
    markers = []
    for line in log.splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and 'phase' in entry and 'uptime_seconds' in entry:
            markers.append(entry)
    results = {}
    for index, marker in enumerate(markers):
        end = markers[index + 1]['uptime_seconds'] if index + 1 < len(markers) else samples[-1]['uptime_seconds']
        # Ignore setup/transitions within each state, not just process startup.
        selected = [s for s in samples if marker['uptime_seconds'] + 2 <= s['uptime_seconds'] < end - 0.2]
        if len(selected) >= 2:
            results[marker['phase']] = summarize(selected)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--warmup', type=float, default=5)
    parser.add_argument('--timeout', type=float, default=90)
    parser.add_argument('--duration', type=float,
                        help='Measure for this many seconds, then terminate only the process started by this tool')
    parser.add_argument('--related-pid', type=int, action='append', default=[],
                        help='Also sample an existing related process, without controlling its lifecycle')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if platform.system() != 'Darwin' or not command or args.warmup < 0 or args.timeout <= args.warmup:
        parser.error('Requires macOS, a command and timeout greater than warmup >= 0.')
    if args.duration is not None and not args.warmup + 1 < args.duration < args.timeout:
        parser.error('Duration must exceed warmup + 1 and be shorter than the timeout.')
    libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    libproc.proc_pid_rusage.restype = ctypes.c_int
    clock = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    clock.mach_timebase_info.argtypes = [ctypes.POINTER(Timebase)]
    clock.mach_timebase_info.restype = ctypes.c_int
    timebase = Timebase()
    if clock.mach_timebase_info(ctypes.byref(timebase)) != 0 or not timebase.denom:
        raise SystemExit('Cannot read the Mach CPU-counter timebase')
    # XNU fill_task_rusage uses absolute-time units, not nanoseconds. The
    # conversion is essential on Apple Silicon (commonly 125/3 nanoseconds).
    seconds_per_tick = timebase.numer / timebase.denom / 1e9
    args.output.parent.mkdir(parents=True, exist_ok=True)
    samples = []
    related = {pid: [] for pid in args.related_pid}
    identities = {}
    controlled_stop = False
    start = time.monotonic()

    def sample(pid, elapsed):
        usage = Usage()
        if libproc.proc_pid_rusage(pid, 2, ctypes.byref(usage)) != 0:
            return None
        if pid in identities and identities[pid] != usage.proc_start_abstime:
            raise RuntimeError(f'Process {pid} was replaced during measurement; repeat with its new PID')
        identities[pid] = usage.proc_start_abstime
        return dict(seconds=elapsed, uptime_seconds=time.monotonic(), cpu_ticks=usage.user_time + usage.system_time,
                    cpu_seconds=(usage.user_time + usage.system_time) * seconds_per_tick,
                    footprint_bytes=usage.phys_footprint, rss_bytes=usage.resident_size,
                    idle_wakeups=usage.pkg_idle_wkups, interrupt_wakeups=usage.interrupt_wkups)

    with args.output.with_suffix('.log').open('w') as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            while process.poll() is None:
                now = time.monotonic() - start
                if now > args.timeout:
                    raise TimeoutError('Diagnostic exceeded the configured timeout')
                if args.duration is not None and now >= args.duration:
                    controlled_stop = True
                    break
                if entry := sample(process.pid, now):
                    samples.append(entry)
                for pid, collected in related.items():
                    if entry := sample(pid, now):
                        collected.append(entry)
                time.sleep(0.5)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    steady = [sample for sample in samples if sample['seconds'] >= args.warmup]
    expected_exit = process.returncode == 0 or (controlled_stop and process.returncode == -signal.SIGTERM)
    if not expected_exit or len(steady) < 2:
        raise SystemExit(f'Diagnostic failed or insufficient samples: see {args.output.with_suffix(".log")}')
    result = dict(command=command, macOS=platform.mac_ver()[0], machine=platform.machine(),
                  mach_timebase=dict(numer=timebase.numer, denom=timebase.denom),
                  warmup_seconds=args.warmup, stop_reason='duration_limit' if controlled_stop else 'completed', **summarize(steady))
    result['max_footprint_mib'] = max(s['footprint_bytes'] for s in samples) / 2**20
    result['phases'] = phase_summaries(args.output.with_suffix('.log').read_text(), samples)
    result['related_processes'] = {}
    for pid, collected in related.items():
        selected = [s for s in collected if s['seconds'] >= args.warmup]
        if len(selected) >= 2:
            result['related_processes'][str(pid)] = dict(**summarize(selected),
                phases=phase_summaries(args.output.with_suffix('.log').read_text(), collected))
        else:
            result['related_processes'][str(pid)] = dict(unavailable=True)
    args.output.write_text(json.dumps(dict(**result, samples=samples, related_samples=related), indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
