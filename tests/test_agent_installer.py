"""Offline checks for agent provisioning, migration and conflict protection."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('installer', ROOT / 'xcode-sdk-plugin/scripts/manage_codex_agent.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def test_new_install_provisions_workflow(self):
        calls = []
        installed = {'pluginId': installer.PLUGIN_ID, 'installed': True, 'enabled': True}

        def command(args, **kwargs):
            calls.append(args[2:])
            payload = {'installed': [installed] if len(calls) > 1 else []}
            return type('Result', (), {'returncode': 0, 'stdout': json.dumps(payload), 'stderr': ''})()

        with patch.object(installer.shutil, 'which', return_value='codex'), patch.object(installer.subprocess, 'run', side_effect=command):
            installer.installed_plugin('install')
        self.assertEqual(calls[1], ['marketplace', 'add', 'fuxiaoqiang/skills', '--json'])
        self.assertEqual(calls[2], ['add', installer.PLUGIN_ID, '--json'])

    def test_failed_provisioning_stops_installation(self):
        with patch.object(installer.shutil, 'which', return_value='codex'), patch.object(installer.subprocess, 'run', return_value=type('Result', (), {'returncode': 1, 'stdout': '', 'stderr': 'network unavailable'})()):
            with self.assertRaisesRegex(ValueError, 'network unavailable'):
                installer.installed_plugin('install')

    def test_migration_idempotency_uninstall_and_conflict(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'CODEX_HOME': directory}), patch.object(installer, 'installed_plugin'):
            target = Path(directory) / 'agents' / installer.AGENT
            target.parent.mkdir()
            previous = installer.MARKER + 'name = "old"\n'
            target.write_text(previous)
            with patch('sys.argv', ['installer', 'install']):
                installer.main()
            self.assertEqual(list(target.parent.glob('*.bak-*'))[0].read_text(), previous)
            content = target.read_text()
            with patch('sys.argv', ['installer', 'install']):
                installer.main()
            self.assertEqual(target.read_text(), content)
            self.assertEqual(len(list(target.parent.glob('*.bak-*'))), 1)
            with patch('sys.argv', ['installer', 'uninstall']):
                installer.main()
            self.assertFalse(target.exists())
            target.write_text('name = "user_owned"\n')
            for action in ('install', 'update', 'uninstall'):
                with patch('sys.argv', ['installer', action]), self.assertRaisesRegex(ValueError, '同名 agent'):
                    installer.main()
            self.assertEqual(target.read_text(), 'name = "user_owned"\n')


if __name__ == '__main__':
    unittest.main()
