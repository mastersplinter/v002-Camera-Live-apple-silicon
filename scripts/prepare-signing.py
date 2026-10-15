#!/usr/bin/env python3
"""Prepare a local private key and public CSR for Apple Developer ID signing."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / '.signing'
KEY = DIRECTORY / 'CameraLive.key'
CSR = DIRECTORY / 'CameraLive.certSigningRequest'

def main():
    os.umask(0o077)
    DIRECTORY.mkdir(mode=0o700, exist_ok=True)
    if KEY.exists() or CSR.exists():
        raise SystemExit('Signing request already exists. Keep its matching private key; do not replace it after requesting a certificate.')
    subprocess.run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(KEY), '-out', str(CSR), '-subj', '/CN=Camera Live Developer ID/'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    subprocess.run(['openssl', 'req', '-in', str(CSR), '-noout', '-verify'], check=True)
    print(f'Upload this public certificate request to Apple: {CSR}')
    print('The matching private key is protected locally and ignored by Git. Do not upload or share it.')

if __name__ == '__main__': main()
