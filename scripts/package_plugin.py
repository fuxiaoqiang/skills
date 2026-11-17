#!/usr/bin/env python3
"""Rebuild the Claude desktop archive from the shared plugin sources."""
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parent.parent
plugin = root / 'xcode-sdk-plugin'
portable = json.loads((plugin / 'plugin.json').read_text())
claude = json.loads((plugin / '.claude-plugin/plugin.json').read_text())
for key in ('name', 'version', 'description', 'author', 'keywords'):
    if portable[key] != claude[key]:
        raise SystemExit(f'Manifest mismatch: {key}')
if (plugin / 'LICENSE').read_bytes() != (root / 'LICENSE').read_bytes():
    raise SystemExit('Keep xcode-sdk-plugin/LICENSE in sync with root LICENSE')
output = root / 'xcode-sdk-setup.plugin'
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path in sorted(plugin.rglob('*')):
        if path.is_file() and not any(part in {'.DS_Store', '__pycache__', '.git'} for part in path.relative_to(plugin).parts):
            archive.write(path, path.relative_to(plugin))
print(f'Packaged {portable["name"]} {portable["version"]}: {output}')
