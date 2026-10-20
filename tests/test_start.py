import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class V6InterfaceTests(unittest.TestCase):
    def run_config(self, **settings):
        with tempfile.TemporaryDirectory() as tmp:
            ip = Path(tmp) / 'ip'
            ip.write_text('''#!/bin/sh
if [ "$1 $2 $3" = "-o link show" ]; then
  printf '1: lo: <UP>\n2: eth0@if19: <UP>\n3: eth1: <UP>\n'
else
  [ "$4" = eth0 ] || [ "$4" = eth1 ]
fi
''')
            ip.chmod(0o755)
            env = {k: v for k, v in os.environ.items()
                   if k not in ('PIHOLE_INTERFACE', 'FTLCONF_dns_interface')}
            env.update(settings)
            env['PATH'] = tmp + ':' + env['PATH']
            return subprocess.run(
                ['bash', '-c', 'source "$1"; configure_interface; printf "%s" "$FTLCONF_dns_interface"',
                 'test', str(ROOT / 'scripts/start.sh')],
                env=env, capture_output=True, text=True)

    def test_auto_detect_strips_peer_suffix(self):
        result = self.run_config()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'eth0')

    def test_native_setting_takes_precedence(self):
        result = self.run_config(FTLCONF_dns_interface='eth1', PIHOLE_INTERFACE='eth0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'eth1')

    def test_legacy_alias(self):
        result = self.run_config(PIHOLE_INTERFACE='eth1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'eth1')

    def test_invalid_and_missing_interfaces_fail(self):
        for iface in ('lo', 'missing', 'eth0;echo bad', '../eth0'):
            with self.subTest(iface=iface):
                result = self.run_config(FTLCONF_dns_interface=iface)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
