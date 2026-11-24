#!/usr/bin/env python3
"""Make mpv's transitive dynamic libraries resolve inside the application."""
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
for library in sorted(root.glob('*.dylib')):
    dependencies = subprocess.check_output(['otool', '-L', str(library)], text=True)
    paths = set(line.strip().split(' (')[0] for line in dependencies.splitlines() if line.startswith('\t'))
    for original in paths:
        if original.startswith('@rpath/'):
            target = root / pathlib.Path(original).name
            if not target.exists():
                if target.name.startswith('libswift'):
                    replacement = '/usr/lib/swift/' + target.name
                else:
                    raise SystemExit(f'Missing dependency: {target.name}')
            else:
                replacement = '@loader_path/' + target.name
            subprocess.run(['install_name_tool', '-change', original, replacement, str(library)], check=True, capture_output=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(library)], check=True, capture_output=True)
