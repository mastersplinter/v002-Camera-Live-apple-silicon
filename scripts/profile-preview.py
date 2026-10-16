#!/usr/bin/env python3
"""Compare original/current preview resources on an unlocked, visible display.

Builds a local native fixture, then runs both previews serially. A temporary
display-sleep assertion lasts only while each finite test runs. Never controls
the installed Camera Live app, its extension, or any existing camera feed.
Requires the native dependencies and this checkout's SwiftBuild toolchain.
"""
import argparse
import json
from pathlib import Path
import platform
import subprocess
import sys

from swift import build_environment

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref', default='v2.4.2')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/preview-profile')
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('Requires an Apple Silicon Mac.')
    env = build_environment()

    def run(command, capture=False):
        result = subprocess.run(command, cwd=ROOT, env=env, check=True,
                                text=True, stdout=subprocess.PIPE if capture else None)
        return result.stdout.strip() if capture else None

    # Resolve the reference before using it in a source path; no remote access.
    commit = run(['git', 'rev-parse', '--verify', '--end-of-options',
                  args.baseline_ref + '^{commit}'], capture=True)
    original = run(['git', 'show', commit + ':Sources/CameraLiveCore/CameraPreviewView.swift'], capture=True)
    if 'class CameraPreviewView:' not in original:
        raise SystemExit('The selected baseline does not contain CameraPreviewView.')
    run(['swift', 'build', '-c', 'release', '--disable-sandbox'])
    products = Path(run(['swift', 'build', '-c', 'release', '--disable-sandbox', '--show-bin-path'], capture=True))
    output = args.output.resolve()
    fixture = output / 'fixture'
    fixture.mkdir(parents=True, exist_ok=True)
    baseline = fixture / 'Baseline.swift'
    baseline.write_text('import CameraLiveCore\n' +
                        original.replace('CameraPreviewView', 'BaselineCameraPreviewView') + '\n')
    objects = [products / (target + '.o') for target in
               ['CameraLiveCore', 'CameraLiveNative', 'VirtualCameraShared', 'CameraLiveVirtualCamera']]
    module_map = products.parents[1] / 'Intermediates.noindex/GeneratedModuleMaps/CameraLiveNative.modulemap'
    missing = [str(path) for path in [*objects, module_map] if not path.exists()]
    if missing:
        raise SystemExit('Expected native SwiftBuild products are unavailable: ' + ', '.join(missing))
    dependencies = ROOT / '.dependencies/usr'
    binary = fixture / 'preview-visibility'
    command = ['xcrun', 'swiftc', '-target', 'arm64-apple-macos26.0', '-parse-as-library',
               '-Xlinker', '-platform_version', '-Xlinker', 'macos', '-Xlinker', '26.0',
               '-Xlinker', env['CAMERALIVE_MACOS_SDK_VERSION'],
               '-module-cache-path', str(ROOT / '.build/module-cache'), '-I', str(products),
               '-Xcc', '-fmodule-map-file=' + str(module_map),
               '-I', str(ROOT / 'Sources/CameraLiveNative/include'), '-I', str(dependencies / 'include'),
               '-F', str(dependencies / 'Frameworks'), '-L', str(dependencies / 'lib'), '-lgphoto2', '-lgphoto2_port']
    for framework in ['Syphon', 'Metal', 'MetalKit', 'CoreImage', 'ImageIO', 'IOKit',
                      'CoreMediaIO', 'SystemExtensions', 'CoreVideo', 'CoreMedia', 'CoreText']:
        command += ['-framework', framework]
    for directory in ['lib', 'Frameworks']:
        command += ['-Xlinker', '-rpath', '-Xlinker', str(dependencies / directory)]
    command += [str(path) for path in objects]
    command += [str(baseline), str(ROOT / 'scripts/fixtures/PreviewVisibility.swift'), '-o', str(binary)]
    run(command)
    (output / 'comparison.json').write_text(json.dumps(dict(
        baseline_ref=args.baseline_ref, baseline_commit=commit,
        current_commit=run(['git', 'rev-parse', 'HEAD'], capture=True),
        tracked_changes=run(['git', 'diff', '--stat'], capture=True),
        sdk=env['CAMERALIVE_MACOS_SDK_VERSION'], binary=str(binary)), indent=2) + '\n')
    if args.build_only:
        print(f'Built preview fixture: {binary}')
        return
    for name, extra in [('baseline', ['--baseline']), ('current', [])]:
        run(['caffeinate', '-d', '-t', '70', sys.executable, str(ROOT / 'scripts/profile-process.py'),
             '--output', str(output / (name + '.json')), '--timeout', '65', '--', str(binary), *extra])
    print(f'Both preview visibility comparisons passed. Results: {output}')


if __name__ == '__main__':
    main()
