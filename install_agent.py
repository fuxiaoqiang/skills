#!/usr/bin/env python3
"""One entry point for installing the SDK agent and its packaged workflow."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', default='install', choices=['install', 'update', 'uninstall'])
    args = parser.parse_args()
    local = Path(__file__).resolve().parent / 'xcode-sdk-plugin/scripts/manage_codex_agent.py'
    if local.is_file():
        return subprocess.call([sys.executable, str(local), args.action])
    # Downloaded standalone entry: obtain the complete package, not a script from a game directory.
    with tempfile.TemporaryDirectory(prefix='fxq-sdk-agent-') as temporary:
        checkout = Path(temporary) / 'skills'
        subprocess.run(['git', 'clone', '--depth', '1', 'https://github.com/fuxiaoqiang/skills.git', str(checkout)], check=True)
        return subprocess.call([sys.executable, str(checkout / 'xcode-sdk-plugin/scripts/manage_codex_agent.py'), args.action])


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, subprocess.CalledProcessError) as error:
        print('安装未完成：' + str(error), file=sys.stderr)
        sys.exit(1)
