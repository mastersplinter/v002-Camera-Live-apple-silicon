#!/usr/bin/env python3
"""Create a relocatable, ad-hoc-signed Apple Silicon application bundle."""
import os
from pathlib import Path
import shutil
import subprocess
import struct
import sys
from swift import build_environment

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / '.dependencies/usr'
APP = ROOT / 'dist/Camera Live.app'

def run(*args, capture=False):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, env=ENV, check=True,
                            stdout=subprocess.PIPE if capture else None, text=True)
    return result.stdout.strip() if capture else None

ENV = build_environment()

def main():
    if os.uname().machine != 'arm64': raise SystemExit('Use a native Apple Silicon terminal.')
    run(sys.executable, ROOT / 'scripts/build-dependencies.py')
    run('swift', 'build', '--disable-sandbox', '-c', 'release', '--arch', 'arm64')
    binary_dir = Path(run('swift', 'build', '--disable-sandbox', '-c', 'release', '--arch', 'arm64', '--show-bin-path', capture=True))
    if APP.exists(): shutil.rmtree(APP)
    frameworks = APP / 'Contents/Frameworks'
    resources = APP / 'Contents/Resources'
    executables = APP / 'Contents/MacOS'
    for path in (frameworks, resources, executables): path.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'Resources/Info.plist', APP / 'Contents/Info.plist')
    for name in ('CameraLive', 'camera-live-diagnostics'): shutil.copy2(binary_dir / name, executables / name)
    shutil.copytree(PREFIX / 'Frameworks/Syphon.framework', frameworks / 'Syphon.framework', symlinks=True)
    for name in ('libgphoto2.6.dylib', 'libgphoto2_port.12.dylib', 'libusb-1.0.0.dylib', 'libltdl.7.dylib'):
        shutil.copy2(PREFIX / 'lib' / name, frameworks / name)
    drivers = resources / 'CameraDrivers'
    for name, pattern in [('camlibs', 'libgphoto2/*/ptp2.so'), ('iolibs', 'libgphoto2_port/*/usb1.so')]:
        directory = drivers / name
        directory.mkdir(parents=True)
        files = list((PREFIX / 'lib').glob(pattern))
        if len(files) != 1: raise RuntimeError(f'Expected exactly one driver for {name}: {files}')
        shutil.copy2(files[0], directory / files[0].name)
    # Patch every copied Mach-O dependency. Absolute checkout paths must never be
    # required after moving the app, including dlopened camera/USB driver modules.
    binaries = [*executables.iterdir(), *frameworks.glob('*.dylib'),
                frameworks / 'Syphon.framework/Versions/A/Syphon', *drivers.rglob('*.so')]
    for binary in binaries:
        output = run('otool', '-L', binary, capture=True)
        for line in output.splitlines()[1:]:
            dependency = line.strip().split(' (')[0]
            if dependency.startswith(str(PREFIX / 'lib') + '/'):
                run('install_name_tool', '-change', dependency, '@rpath/' + Path(dependency).name, binary)
        if binary.suffix == '.dylib': run('install_name_tool', '-id', '@rpath/' + binary.name, binary)
        load_commands = run('otool', '-l', binary, capture=True).splitlines()
        for index, line in enumerate(load_commands):
            if line.strip() == 'cmd LC_RPATH':
                rpath = load_commands[index+2].strip().removeprefix('path ').split(' (')[0]
                if rpath.startswith(str(ROOT)):
                    run('install_name_tool', '-delete_rpath', rpath, binary)
        if binary.suffix == '.so':
            run('install_name_tool', '-add_rpath', '@loader_path/../../../Frameworks', binary)
        # Each dependency can also resolve its siblings when loaded by dlopen.
        if binary.suffix == '.dylib': run('install_name_tool', '-add_rpath', '@loader_path', binary)
    # Retain the original project's artwork.
    iconset = ROOT / '.build/CameraLive.iconset'
    iconset.mkdir(parents=True, exist_ok=True)
    artwork = ROOT / 'Resources/AppIcon.png'
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            run('sips', '-z', str(size*scale), str(size*scale), artwork, '--out', iconset / name, capture=True)
    # ICNS is a length-prefixed collection of PNG representations. Writing the
    # container directly also works on CLT hosts where iconutil's service fails.
    chunks = []
    representations = [('icp4', 16, 1), ('icp5', 32, 1), ('ic07', 128, 1),
                       ('ic08', 256, 1), ('ic09', 512, 1), ('ic10', 512, 2),
                       ('ic11', 16, 2), ('ic12', 32, 2), ('ic13', 128, 2), ('ic14', 256, 2)]
    for code, size, scale in representations:
        name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        data = (iconset / name).read_bytes()
        chunks.append(struct.pack('>4sI', code.encode(), len(data) + 8) + data)
    payload = b''.join(chunks)
    (resources / 'CameraLive.icns').write_bytes(struct.pack('>4sI', b'icns', len(payload) + 8) + payload)
    licenses = resources / 'Licenses'; licenses.mkdir()
    shutil.copy2(ROOT / 'LICENSE', licenses / 'Camera-Live.txt')
    shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', licenses / 'Third-Party-Notices.md')
    for pattern, filename, target in [('libgphoto2-*', 'COPYING', 'libgphoto2-LGPL.txt'),
                                      ('libusb-*', 'COPYING', 'libusb-LGPL.txt'),
                                      ('libtool-*', 'libltdl/COPYING.LIB', 'libltdl-LGPL.txt')]:
        source = next(path for path in (ROOT / '.dependencies/src').glob(pattern) if path.is_dir())
        shutil.copy2(source / filename, licenses / target)
    for binary in binaries:
        if run('lipo', '-archs', binary, capture=True) != 'arm64': raise RuntimeError(f'Not arm64: {binary}')
        for line in run('otool', '-L', binary, capture=True).splitlines()[1:]:
            dependency = line.strip().split(' (')[0]
            if dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                raise RuntimeError(f'Unbundled dependency in {binary}: {dependency}')
        run('codesign', '--force', '--sign', '-', binary)
    run('codesign', '--force', '--sign', '-', frameworks / 'Syphon.framework')
    run('codesign', '--force', '--sign', '-', APP)
    run('codesign', '--verify', '--deep', '--strict', APP)
    print(f'Built {APP}')

if __name__ == '__main__': main()
