#!/usr/bin/env python3
"""Install/update/remove the companion Codex agent without changing config.toml."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

AGENT = 'xcode_sdk_setup.toml'
MARKER = '# Managed by fxq-skills/xcode-sdk-setup\n'
PLUGIN_ID = 'xcode-sdk-setup@fxq-skills'


def installed_plugin(action):
    executable = shutil.which('codex')
    bundled = Path('/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex')
    if not executable and bundled.is_file():
        executable = str(bundled)
    if not executable:
        raise ValueError('找不到 codex，请先安装 Codex CLI 并加入 PATH。')

    def command(*args):
        result = subprocess.run([executable, 'plugin', *args], capture_output=True, text=True)
        if result.returncode:
            raise ValueError('Codex 插件配置失败：' + result.stderr.strip() + result.stdout.strip())
        return result.stdout

    data = json.loads(command('list', '--json'))
    current = next((item for item in data.get('installed', [])
                    if item.get('pluginId') == PLUGIN_ID and item.get('installed')
                    and item.get('enabled')), None)
    if current and action != 'update':
        return
    # Users install the agent; its workflow package is provisioned here automatically.
    command('marketplace', 'add', 'fuxiaoqiang/skills', '--json')
    if action == 'update':
        command('marketplace', 'upgrade', 'fxq-skills')
    command('add', PLUGIN_ID, '--json')
    data = json.loads(command('list', '--json'))
    if not any(item.get('pluginId') == PLUGIN_ID and item.get('installed')
               and item.get('enabled') for item in data.get('installed', [])):
        raise ValueError('工作流包未成功安装并启用，未注册 agent。')
    print('SDK 工作流包已就绪。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'update', 'uninstall'])
    args = parser.parse_args()
    codex_home = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex').expanduser()
    target = codex_home / 'agents' / AGENT
    if target.is_symlink():
        raise ValueError('目标是软链接，请先自行检查：' + str(target))
    exists = target.exists()
    old = target.read_text() if exists else ''
    if exists and not old.startswith(MARKER):
        raise ValueError('已有非本工具管理的同名 agent，未覆盖或删除：' + str(target))
    if args.action == 'uninstall':
        if exists:
            target.unlink()
            print('已卸载：' + str(target))
        else:
            print('尚未安装，无需卸载。')
        return
    installed_plugin(args.action)
    source = Path(__file__).resolve().parent.parent / 'codex-agents' / AGENT
    content = MARKER + source.read_text()
    if old == content:
        print('已是当前版本：' + str(target))
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    if exists:
        backup = target.with_name(target.name + '.bak-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        shutil.copy2(target, backup)
        print('备份：' + str(backup))
    # Exclusive creation prevents an initial install from overwriting another file.
    if not exists:
        with target.open('x') as stream:
            stream.write(content)
    else:
        temporary = target.with_suffix('.toml.tmp-' + str(os.getpid()))
        try:
            with temporary.open('x') as stream:
                stream.write(content)
            temporary.replace(target)
        finally:
            if temporary.exists():
                temporary.unlink()
    print('已安装：' + str(target))
    print('请新建 Codex 对话；未识别时重启客户端。')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
