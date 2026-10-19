"""Run with python3 -m unittest discover -s tests -v; no services are started."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'start.sh'


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.setup = self.root / 'setupVars.conf'
        self.dns = self.root / '01-pihole.conf'
        self.env = dict(os.environ, PATH=str(self.root) + ':' + os.environ['PATH'])
        self.env.pop('PIHOLE_INTERFACE', None)
        self.env['TEST_LOG'] = str(self.root / 'services.log')
        self.stub('sudo', 'echo "$*" >> "$TEST_LOG"\nexit 0')
        self.network()

    def stub(self, name, body):
        path = self.root / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def network(self, names=('eth0',), up='2: eth0@if12: <UP>'):
        self.stub('ip', 'if [ "$1" = "-o" ]; then\n'
                  + "printf '%s\\n' '" + up + "'\nexit 0\nfi\n"
                  + 'case "$4" in\n' + '|'.join(names)
                  + ') exit 0;;\n*) exit 1;;\nesac')

    def config(self, mode='bind', dns='interface=old\nbind-interfaces\n'):
        self.setup.write_text('PIHOLE_INTERFACE=old\nDNSMASQ_LISTENING=' + mode + '\n')
        self.dns.write_text(dns)

    def run_script(self, services=False):
        code = 'source "$1"; configure_network "$2" "$3"'
        if services:
            code += '; start_services'
        return subprocess.run(['bash', '-c', code, 'test', str(SCRIPT),
                               str(self.setup), str(self.dns)],
                              env=self.env, capture_output=True, text=True)

    def test_bind_and_single(self):
        for mode in ('bind', 'single'):
            with self.subTest(mode=mode):
                self.config(mode)
                self.assertEqual(self.run_script().returncode, 0)
                self.assertIn('interface=eth0\n', self.dns.read_text())
                first = (self.setup.read_text(), self.dns.read_text())
                self.assertEqual(self.run_script().returncode, 0)
                self.assertEqual(first, (self.setup.read_text(), self.dns.read_text()))

    def test_preserve_local_and_all(self):
        for mode, config in [('local', 'local-service\n'),
                             ('all', 'except-interface=nonexisting\n')]:
            with self.subTest(mode=mode):
                self.config(mode, config)
                self.assertEqual(self.run_script().returncode, 0)
                self.assertEqual(self.dns.read_text(), config)

    def test_prefer_veth1(self):
        self.network(('eth0', 'veth1'))
        self.config()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertIn('interface=veth1\n', self.dns.read_text())

    def test_explicit_interface(self):
        self.network(('eth0', 'veth1', 'veth0'))
        self.env['PIHOLE_INTERFACE'] = 'veth0'
        self.config()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertIn('interface=veth0\n', self.dns.read_text())

    def test_invalid_interfaces_do_not_modify_files(self):
        for iface in ('missing0', 'lo', 'bad/name', 'eth0&bad'):
            with self.subTest(iface=iface):
                self.env['PIHOLE_INTERFACE'] = iface
                self.config()
                before = (self.setup.read_text(), self.dns.read_text())
                self.assertNotEqual(self.run_script().returncode, 0)
                self.assertEqual(before, (self.setup.read_text(), self.dns.read_text()))

    def test_only_loopback(self):
        self.network(('lo',), '1: lo: <UP>')
        self.config()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertIn('interface=old', self.dns.read_text())

    def test_missing_files(self):
        self.assertNotEqual(self.run_script().returncode, 0)

    def test_unknown_mode(self):
        self.config('invalid')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertIn('interface=old', self.dns.read_text())

    def test_ftl_failure_stops_startup(self):
        self.config()
        self.stub('sudo', 'echo "$*" >> "$TEST_LOG"\necho "FTL failure" >&2\nexit 1')
        result = self.run_script(services=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('FTL failure', result.stderr)
        self.assertEqual((self.root / 'services.log').read_text(),
                         'service pihole-FTL start\n')


if __name__ == '__main__':
    unittest.main()
