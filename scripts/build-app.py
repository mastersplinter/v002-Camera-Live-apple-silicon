#!/usr/bin/env python3
"""Create a relocatable Apple Silicon app with optional Apple Developer signing."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import plistlib
from swift import build_environment
from signing import Signing, APP_ID, EXTENSION_ID

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
    signing = Signing()
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
    extension = APP / 'Contents/Library/SystemExtensions' / (EXTENSION_ID + '.systemextension')
    extension_executable = extension / 'Contents/MacOS/CameraLiveCameraExtension'
    extension_executable.parent.mkdir(parents=True)
    shutil.copy2(binary_dir / 'CameraLiveCameraExtension', extension_executable)
    extension_info = plistlib.loads((ROOT / 'Resources/CameraExtension-Info.plist').read_bytes())
    extension_info['CMIOExtension']['CMIOExtensionMachServiceName'] = signing.group
    (extension / 'Contents/Info.plist').write_bytes(plistlib.dumps(extension_info))
    app_info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    app_info['CameraLiveVirtualCameraInstallable'] = signing.enabled
    (APP / 'Contents/Info.plist').write_bytes(plistlib.dumps(app_info))
    shutil.copy2(ROOT / 'VIRTUAL_CAMERA.md', resources / 'VIRTUAL_CAMERA.md')
    entitlements_directory = ROOT / '.build/signing'
    entitlements_directory.mkdir(parents=True, exist_ok=True)
    app_entitlements = entitlements_directory / 'App.entitlements'
    extension_entitlements = entitlements_directory / 'Extension.entitlements'
    diagnostics_entitlements = entitlements_directory / 'Diagnostics.entitlements'
    app_entitlements.write_bytes(plistlib.dumps(signing.app_entitlements))
    extension_entitlements.write_bytes(plistlib.dumps(signing.extension_entitlements))
    diagnostics_entitlements.write_bytes(plistlib.dumps({'com.apple.security.device.camera': True}))
    if signing.enabled:
        shutil.copy2(signing.app_profile, APP / 'Contents/embedded.provisionprofile')
        if signing.extension_profile:
            shutil.copy2(signing.extension_profile, extension / 'Contents/embedded.provisionprofile')
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
                frameworks / 'Syphon.framework/Versions/A/Syphon', *drivers.rglob('*.so'), extension_executable]
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
    # Let macOS encode every representation, including the small icons used by
    # System Settings. Hand-assembling PNG chunks can produce corrupt thumbnails.
    icon = resources / 'CameraLive.icns'
    run('iconutil', '-c', 'icns', iconset, '-o', icon)
    extension_resources = extension / 'Contents/Resources'
    extension_resources.mkdir(parents=True, exist_ok=True)
    shutil.copy2(icon, extension_resources / icon.name)
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
        diagnostic = binary.name == 'camera-live-diagnostics'
        signing.sign(binary, run, identifier=APP_ID + '.Diagnostics' if diagnostic else None,
                     entitlements=diagnostics_entitlements if diagnostic and signing.enabled else None)
    signing.sign(frameworks / 'Syphon.framework', run)
    signing.sign(extension, run, entitlements=extension_entitlements)
    signing.sign(APP, run, entitlements=app_entitlements if signing.enabled else None)
    run('codesign', '--verify', '--deep', '--strict', APP)
    if signing.enabled:
        details = subprocess.run(['codesign', '-d', '--verbose=4', str(APP)], capture_output=True, text=True, check=True)
        if f'TeamIdentifier={signing.team}' not in details.stderr:
            raise RuntimeError('The selected signing certificate does not belong to CAMERALIVE_TEAM_ID.')
    print(f'Built {APP}')
    if not signing.enabled:
        print('Preview/Syphon build only: virtual-camera activation requires Apple signing. See VIRTUAL_CAMERA.md.')

if __name__ == '__main__': main()
