#!/usr/bin/env python3
"""Notarize the signed app using credentials already stored by notarytool."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/Camera Live.app'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--keychain-profile', default='CameraLive', help='Existing notarytool keychain credential profile')
    args = parser.parse_args()
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    signature = subprocess.run(['codesign', '-d', '--verbose=4', str(APP)], capture_output=True, text=True, check=True).stderr
    if not info.get('CameraLiveVirtualCameraInstallable') or 'Authority=Developer ID Application:' not in signature:
        raise SystemExit('Build with a Developer ID Application identity and a valid app provisioning profile first.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    directory = ROOT / '.build/notary'; directory.mkdir(parents=True, exist_ok=True)
    archive = directory / 'CameraLive.zip'
    if archive.exists(): archive.unlink()
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(APP), str(archive)], check=True)
    print('Submitting the signed Camera Live app to Apple for notarization…', flush=True)
    # Confirm the upload and persist its ID before waiting. A connection failure
    # during submit --wait otherwise hides whether the archive reached Apple.
    uploaded = subprocess.run(['xcrun', 'notarytool', 'submit', str(archive), '--keychain-profile', args.keychain_profile,
                               '--no-wait', '--output-format', 'json'], capture_output=True, text=True)
    (directory / 'submission.json').write_text(uploaded.stdout)
    if uploaded.returncode:
        raise SystemExit(f'Notarization upload failed: {uploaded.stderr.strip()}')
    submission_id = json.loads(uploaded.stdout)['id']
    print(f'Upload confirmed; waiting for Apple submission {submission_id}…', flush=True)
    result = subprocess.run(['xcrun', 'notarytool', 'wait', submission_id, '--keychain-profile', args.keychain_profile,
                             '--output-format', 'json'], capture_output=True, text=True)
    (directory / 'result.json').write_text(result.stdout)
    if result.returncode:
        raise SystemExit(f'Waiting for submission {submission_id} failed: {result.stderr.strip()}')
    reply = json.loads(result.stdout)
    if reply.get('status') != 'Accepted':
        if reply.get('id'):
            subprocess.run(['xcrun', 'notarytool', 'log', reply['id'], '--keychain-profile', args.keychain_profile,
                            str(directory / 'log.json')], check=True)
        raise SystemExit(f'Apple did not accept the app. See {directory} for the result and log.')
    subprocess.run(['xcrun', 'stapler', 'staple', str(APP)], check=True)
    subprocess.run(['xcrun', 'stapler', 'validate', str(APP)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(APP)], check=True)
    print('Notarization accepted and stapled. The signed app is ready for installation and macOS camera-extension approval.')

if __name__ == '__main__': main()
