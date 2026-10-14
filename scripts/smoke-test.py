#!/usr/bin/env python3
"""Cross-process Syphon/Metal test, without camera hardware."""
import argparse
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', nargs='?', type=Path, default=ROOT / 'dist/Camera Live.app')
parser.add_argument('--preview', action='store_true', help='Also validate actual on-screen preview delivery; keep its window visible')
args = parser.parse_args()
APP = args.app.resolve()
BINARY = APP / 'Contents/MacOS/camera-live-diagnostics'
name = 'Camera Live verification ' + uuid.uuid4().hex[:8]
producer = subprocess.Popen([str(BINARY), '--test-pattern', name, *(['--preview'] if args.preview else [])],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    consumer = subprocess.run([str(BINARY), '--receive', name, '--verify-pattern'], capture_output=True, text=True, timeout=30)
    print(consumer.stdout, end='')
    if consumer.returncode:
        print(consumer.stderr, file=sys.stderr, end='')
        raise RuntimeError('Syphon receiver failed')
    out, err = producer.communicate(timeout=35)
    print(out, end='')
    if producer.returncode:
        print(err, file=sys.stderr, end='')
        raise RuntimeError('Syphon producer failed')
finally:
    if producer.poll() is None:
        producer.terminate()
        try: producer.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            producer.kill(); producer.communicate()
