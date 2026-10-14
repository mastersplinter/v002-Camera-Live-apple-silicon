#!/usr/bin/env python3
"""Build pinned arm64 dependencies in the checkout; no Homebrew or Xcode.app needed."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.dependencies'
SRC = WORK / 'src'
PREFIX = WORK / 'usr'
LOGS = WORK / 'logs'
REV = 'f4761677a45b8034a3c2069ec0f3d2553da81fba'
PACKAGES = {
    'pkgconf-2.5.1': ('https://distfiles.ariadne.space/pkgconf/pkgconf-2.5.1.tar.xz', 'cd05c9589b9f86ecf044c10a2269822bc9eb001eced2582cfffd658b0a50c243'),
    'libusb-1.0.30': ('https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2', 'fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf'),
    'libtool-2.5.4': ('https://ftp.gnu.org/gnu/libtool/libtool-2.5.4.tar.gz', 'da8ebb2ce4dcf46b90098daf962cffa68f4b4f62ea60f798d0ef12929ede6adf'),
    'libgphoto2-2.5.34': ('https://github.com/gphoto/libgphoto2/releases/download/v2.5.34/libgphoto2-2.5.34.tar.gz', '37b476bf1af073219394210d34904d987b6cb8bfb64d5cc5b6e87c7d453d421a'),
    f'Syphon-Framework-{REV}': (f'https://codeload.github.com/Syphon/Syphon-Framework/tar.gz/{REV}', 'a3766088c46588c42b087f4e5ff7ae7bb0f83292af59a0aeb8bba69eba5311c5'),
}

def run(args, cwd=ROOT, env=None, log=None):
    if log:
        with open(LOGS / log, 'a') as out:
            subprocess.run([str(a) for a in args], cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True)

def fetch(name):
    url, digest = PACKAGES[name]
    archive = SRC / (name + '.archive')
    if not archive.exists():
        run(['curl', '-fLsS', '--retry', '3', url, '-o', archive])
    if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f'Checksum mismatch: {archive}. Delete it and retry.')
    path = SRC / name
    if not path.exists():
        with tarfile.open(archive) as tar:
            # Pinned sources, with an additional path traversal guard.
            for member in tar.getmembers():
                if not (SRC / member.name).resolve().is_relative_to(SRC.resolve()):
                    raise RuntimeError('Unsafe archive member')
            tar.extractall(SRC)
    return path

def main():
    if any(character.isspace() for character in str(ROOT)):
        raise SystemExit('The Autotools dependencies require a checkout path without whitespace.')
    if os.uname().machine != 'arm64':
        raise SystemExit('Build on an Apple Silicon Mac in a native terminal (not Rosetta).')
    for path in (SRC, PREFIX, LOGS):
        path.mkdir(parents=True, exist_ok=True)
    developer = os.environ.get('DEVELOPER_DIR', subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    env = dict(os.environ, DEVELOPER_DIR=developer, MACOSX_DEPLOYMENT_TARGET='13.0',
               CLANG_MODULE_CACHE_PATH=str(WORK / 'module-cache'))
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], env=env, text=True).strip()
    cc = subprocess.check_output(['xcrun', '--find', 'clang'], env=env, text=True).strip()
    env.update(CC=cc, CXX=cc+'++', CFLAGS=f'-O2 -arch arm64 -isysroot {sdk}',
               CPPFLAGS=f'-I{PREFIX}/include', LDFLAGS=f'-L{PREFIX}/lib -Wl,-headerpad_max_install_names',
               PKG_CONFIG_PATH=str(PREFIX / 'lib/pkgconfig'),
               lt_cv_sys_max_cmd_len='262144', ac_cv_func_pipe2='no',
               PKG_CONFIG=str(PREFIX / 'bin/pkgconf'))
    # libgphoto2's configure honours these without a global pkg-config install.
    env.update(LIBUSB1_CFLAGS=f'-I{PREFIX}/include/libusb-1.0', LIBUSB1_LIBS=f'-L{PREFIX}/lib -lusb-1.0',
               LTDLINCL=f'-I{PREFIX}/include', LIBLTDL=f'-L{PREFIX}/lib -lltdl')
    builds = [
        ('pkgconf-2.5.1', ['--disable-shared', '--enable-static'], 'bin/pkgconf'),
        ('libusb-1.0.30', [], 'lib/libusb-1.0.dylib'),
        ('libtool-2.5.4', ['--enable-ltdl-install'], 'lib/libltdl.dylib'),
        ('libgphoto2-2.5.34', ['--with-camlibs=ptp2', '--disable-nls', '--disable-docs', '--without-jpeg',
                              '--with-libexif=no', '--with-libxml-2.0=no', '--with-libusb=no', '--disable-rpath'], 'lib/libgphoto2.dylib'),
    ]
    if '--syphon-only' in sys.argv:
        builds = []
    for name, flags, output in builds:
        required = [PREFIX / output]
        if name.startswith('libgphoto2-'):
            required += [PREFIX / 'lib/libgphoto2/2.5.34/ptp2.so', PREFIX / 'lib/libgphoto2_port/0.12.2/usb1.so']
        if all(path.exists() for path in required):
            print(f'Already built {name}', flush=True)
            continue
        source = fetch(name)
        print(f'Building {name} (log: .dependencies/logs/{name}.log)', flush=True)
        log = name + '.log'
        run([source / 'configure', f'--prefix={PREFIX}', '--disable-static', *flags], cwd=source, env=env, log=log)
        run(['make', '-j', str(min(os.cpu_count() or 4, 8))], cwd=source, env=env, log=log)
        run(['make', 'install'], cwd=source, env=env, log=log)
    framework = PREFIX / 'Frameworks/Syphon.framework'
    if not (framework / 'Syphon').exists():
        print('Building Syphon Metal for arm64', flush=True)
        source = fetch(f'Syphon-Framework-{REV}')
        version = framework / 'Versions/A'
        for name in ('Headers', 'Resources', 'Modules'):
            (version / name).mkdir(parents=True, exist_ok=True)
        (framework / 'Versions/Current').symlink_to('A') if not (framework / 'Versions/Current').exists() else None
        for name in ('Headers', 'Resources', 'Modules', 'Syphon'):
            link = framework / name
            if not link.is_symlink():
                link.symlink_to('Versions/Current/' + name)
        project = (source / 'Syphon.xcodeproj/project.pbxproj').read_text()
        public_headers = set(re.findall(r'/\* (\w+\.h) in Headers \*/ = [^\n]*ATTRIBUTES = \(Public,', project))
        for header in source.glob('*.h'):
            if header.name in public_headers:
                shutil.copy2(header, version / 'Headers')
        shutil.copy2(source / 'Syphon.modulemap', version / 'Modules/module.modulemap')
        # Command Line Tools cannot compile .metallib. Use the same upstream shader
        # source with Metal's supported runtime compiler, once per server creation.
        shader = (source / 'SyphonMetalShaders.metal').read_text().replace(
            '#include "SyphonServerMetalTypes.h"', (source / 'SyphonServerMetalTypes.h').read_text())
        renderer = (source / 'SyphonServerRendererMetal.m').read_text()
        renderer = renderer.replace('[device newDefaultLibraryWithBundle:bundle error:&error]',
                                    '[device newLibraryWithSource:@' + json.dumps(shader) + ' options:nil error:&error]')
        patched = source / 'CameraLiveRenderer.m'
        patched.write_text(renderer)
        project = (source / 'Syphon.xcodeproj/project.pbxproj').read_text()
        names = sorted(set(re.findall(r'/\* (\w+\.[mc]) in Sources \*/ =', project)))
        objects = []
        for name in names:
            path = patched if name == 'SyphonServerRendererMetal.m' else source / name
            obj = source / (name + '.o')
            args = [cc, '-arch', 'arm64', '-mmacosx-version-min=13.0', '-isysroot', sdk, '-O2',
                    '-fmodules', '-DSYPHON_CORE_SHARE', '-DGL_SILENCE_DEPRECATION', '-Wno-deprecated-declarations',
                    '-F', framework.parent, '-I', source, '-include', source / 'Syphon_Prefix.pch']
            if path.suffix == '.m':
                args += ['-fobjc-arc']
            run([*args, '-c', path, '-o', obj], env=env, log='Syphon.log')
            objects.append(obj)
        run([cc, '-arch', 'arm64', '-mmacosx-version-min=13.0', '-isysroot', sdk, '-dynamiclib',
             '-install_name', '@rpath/Syphon.framework/Versions/A/Syphon',
             *objects, '-framework', 'Cocoa', '-framework', 'Metal', '-framework', 'IOSurface',
             '-framework', 'OpenGL', '-o', version / 'Syphon'], env=env, log='Syphon.log')
        (version / 'Resources/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'info.v002.Syphon', 'CFBundleName': 'Syphon', 'CFBundleExecutable': 'Syphon',
            'CFBundlePackageType': 'FMWK', 'CFBundleVersion': '6', 'CFBundleShortVersionString': '6.0',
            'NSPrincipalClass': 'SyphonServerDirectory'}))
        shutil.copy2(source / 'License.txt', version / 'Resources/License.txt')
    # Only the upstream public headers belong in a framework module.
    source = SRC / f'Syphon-Framework-{REV}'
    if source.exists():
        project = (source / 'Syphon.xcodeproj/project.pbxproj').read_text()
        public_headers = set(re.findall(r'/\* (\w+\.h) in Headers \*/ = [^\n]*ATTRIBUTES = \(Public,', project))
        for header in (framework / 'Headers').glob('*.h'):
            if header.name not in public_headers:
                header.unlink()
        shutil.copy2(source / 'Syphon.modulemap', framework / 'Modules/module.modulemap')
    print('Native dependencies ready.', flush=True)

if __name__ == '__main__':
    main()
