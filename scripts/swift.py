#!/usr/bin/env python3
"""Run SwiftPM with workspace-local caches and a narrow CLT installation repair.

Some upgraded CLT installations retain Swift 5 private PackageDescription
interfaces beside Swift 6 public interfaces/dylibs. Prefer a local copy without
those stale private interfaces; never edit the system toolchain.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def build_environment():
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / '.build/module-cache'),
               SWIFTPM_MODULECACHE_OVERRIDE=str(ROOT / '.build/module-cache'))
    env['CAMERALIVE_MACOS_SDK_VERSION'] = subprocess.check_output(
        ['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True).strip()
    if int(env['CAMERALIVE_MACOS_SDK_VERSION'].split('.')[0]) < 26:
        raise SystemExit('Camera Live requires a macOS 26 or newer SDK. Select Xcode 26 or newer, or update Command Line Tools.')
    compiler = Path(subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip())
    pm = compiler.parent.parent / 'lib/swift/pm'
    module = pm / 'ManifestAPI/PackageDescription.swiftmodule'
    stale = False
    for private in module.glob('*.private.swiftinterface'):
        public = private.with_name(private.name.replace('.private', ''))
        if public.exists() and private.read_text().splitlines()[1] != public.read_text().splitlines()[1]:
            stale = True
    if stale:
        local = ROOT / '.build/swiftpm-libraries'
        # Copy once per installed manifest library version.
        stamp = str((pm / 'ManifestAPI/libPackageDescription.dylib').stat().st_mtime_ns)
        marker = local / '.version'
        if not marker.exists() or marker.read_text() != stamp:
            if local.exists(): shutil.rmtree(local)
            shutil.copytree(pm / 'ManifestAPI', local / 'ManifestAPI', ignore=shutil.ignore_patterns('*.private.swiftinterface'))
            if (pm / 'PluginAPI').exists(): (local / 'PluginAPI').symlink_to(pm / 'PluginAPI', target_is_directory=True)
            marker.write_text(stamp)
        env['SWIFTPM_CUSTOM_LIBS_DIR'] = str(local)
    return env

if __name__ == '__main__':
    arguments = sys.argv[1:]
    if arguments and arguments[0] == 'test':
        compiler = Path(subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip())
        plugins = compiler.parent.parent / 'lib/swift/host/plugins/testing'
        if plugins.exists():
            # SwiftBuild in newer CLT releases can omit this search path when
            # incrementally rebuilding tests after a release configuration.
            arguments += ['-Xswiftc', '-plugin-path', '-Xswiftc', str(plugins)]
    raise SystemExit(subprocess.call(['swift', *arguments], cwd=ROOT, env=build_environment()))
