"""Rebuilds screenshots printed by integration_test/app_test.dart on Android.

Usage: python tool/collect_screenshots.py <test log> <output dir>
"""
import base64
import collections
import os
import re
import sys

log, out = sys.argv[1], sys.argv[2]
parts = collections.defaultdict(list)
for line in open(log, encoding='utf8', errors='replace'):
    m = re.search(r'\[shot:(\w+)\] (\S+)', line)
    if m:
        parts[m.group(1)].append(m.group(2))
os.makedirs(out, exist_ok=True)
for name, chunks in parts.items():
    with open(os.path.join(out, name + '.png'), 'wb') as f:
        f.write(base64.b64decode(''.join(chunks)))
    print('wrote', name)
