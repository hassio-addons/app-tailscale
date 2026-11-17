"""Regression tests for the services.target schema in tailscale/config.yaml.

Run with: python3 -m unittest discover --start-directory tests --verbose
Requires PyYAML and voluptuous (the validator used by Home Assistant Supervisor).
"""

import unittest
from pathlib import Path

import voluptuous as vol
import yaml

CONFIG_PATH = Path(__file__).resolve().parents[1] / "tailscale" / "config.yaml"
SCHEMES = ("http", "https", "https+insecure", "tcp")


class ServicesTargetTests(unittest.TestCase):
    """Exercise the actual YAML schema with Supervisor's match validator."""

    @classmethod
    def setUpClass(cls):
        config = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
        schema = config["schema"]["services"][0]["target"]
        if not schema.startswith("match(") or not schema.endswith(")"):
            raise AssertionError("services.target must use a match validator")
        cls.validate_target = staticmethod(vol.Match(schema[len("match(") : -1]))

    def test_localhost_remains_valid_for_all_schemes(self):
        for scheme in SCHEMES:
            for port in (1, 80, 443, 8123, 9999, 10000, 65535):
                target = f"{scheme}://127.0.0.1:{port}"
                with self.subTest(target=target):
                    self.assertEqual(self.validate_target(target), target)

    def test_remote_ipv4_targets_for_all_schemes(self):
        for scheme in SCHEMES:
            for host in ("10.0.0.2", "172.16.0.2", "192.168.1.100", "100.64.0.2"):
                target = f"{scheme}://{host}:8080"
                with self.subTest(target=target):
                    self.assertEqual(self.validate_target(target), target)

    def test_ipv4_octet_boundaries(self):
        for position in range(4):
            for octet in range(1000):
                parts = ["1", "2", "3", "4"]
                parts[position] = str(octet)
                target = f"http://{'.'.join(parts)}:8080"
                with self.subTest(target=target):
                    if octet <= 255:
                        self.assertEqual(self.validate_target(target), target)
                    else:
                        with self.assertRaises(vol.Invalid):
                            self.validate_target(target)

    def test_dns_targets_for_all_schemes(self):
        hosts = (
            "localhost",
            "server",
            "server.local",
            "my-server.home.arpa",
            "SERVICE.Example.COM",
            "server.example.com.",
            "xn--bcher-kva.example",
            "a",
            "123",
            "999.999.999.999.example",
            "999.999.999.999x",
        )
        for scheme in SCHEMES:
            for host in hosts:
                target = f"{scheme}://{host}:8080"
                with self.subTest(target=target):
                    self.assertEqual(self.validate_target(target), target)

    def test_invalid_ipv4_cannot_fall_back_to_dns(self):
        hosts = (
            "256.168.1.1",
            "999.999.999.999",
            "1.256.1.1",
            "1.1.256.1",
            "1.1.1.256",
            "256.0.0.0",
            "0.0.0.256",
            "1000.1.1.1",
            "-1.2.3.4",
            "1.-1.3.4",
            "1.2.-1.4",
            "1.2.3.-1",
            "01.2.3.4",
            "1.02.3.4",
            "1.2.03.4",
            "1.2.3.04",
        )
        for scheme in SCHEMES:
            for host in hosts:
                for suffix in ("", "."):
                    target = f"{scheme}://{host}{suffix}:8080"
                    with self.subTest(target=target), self.assertRaises(vol.Invalid):
                        self.validate_target(target)

    def test_ipv4_boundaries_for_all_schemes(self):
        hosts = (
            "0.0.0.0",
            "255.255.255.255",
            "9.99.199.249",
            "10.100.200.250",
            "172.30.32.1",
            "192.0.2.1",
        )
        for scheme in SCHEMES:
            for host in hosts:
                for suffix in ("", "."):
                    target = f"{scheme}://{host}{suffix}:8090"
                    with self.subTest(target=target):
                        self.assertEqual(self.validate_target(target), target)

    def test_bracketed_ipv6_targets_for_all_schemes(self):
        hosts = (
            "[::1]",
            "[::]",
            "[fd00::1]",
            "[2001:db8::1]",
            "[2001:DB8:0:1:2:3:4:5]",
            "[::ffff:192.0.2.1]",
        )
        for scheme in SCHEMES:
            for host in hosts:
                target = f"{scheme}://{host}:8080"
                with self.subTest(target=target):
                    self.assertEqual(self.validate_target(target), target)

    def test_port_range(self):
        for host in ("127.0.0.1", "192.168.1.100", "server.local", "[fd00::1]"):
            for port in range(1, 65536):
                target = f"http://{host}:{port}"
                self.assertEqual(self.validate_target(target), target)
        for scheme in SCHEMES:
            for host in ("127.0.0.1", "server.local", "[::1]"):
                for port in ("0", "65536", "99999", "100000", "-1", "1.5", "080", ""):
                    target = f"{scheme}://{host}:{port}"
                    with self.subTest(target=target), self.assertRaises(vol.Invalid):
                        self.validate_target(target)

    def test_malformed_and_unsupported_targets(self):
        targets = (
            "",
            "192.168.1.100:8080",
            "http://192.168.1.100",
            "ftp://192.168.1.100:8080",
            "udp://192.168.1.100:8080",
            "https+invalid://192.168.1.100:8080",
            "http:/192.168.1.100:8080",
            "http://user:password@192.168.1.100:8080",
            "http://192.168.1.100:8080/path",
            "http://192.168.1.100:8080?query=1",
            "http://192.168.1.100:8080#fragment",
            " http://192.168.1.100:8080",
            "http://192.168.1.100:8080 ",
            "http://192.168.1.100:8080\nextra",
            "http://192.168.1.100:8080;echo",
            "http://192.168.1.100:8080$(id)",
            "http://:8080",
            "http://[]:8080",
            "http://::1:8080",
            "http://[::1:8080",
            "http://::1]:8080",
            "http://[[::1]]:8080",
            "http://[server.local]:8080",
            "http://[256.168.1.1]:8080",
            "http://[999.999.999.999]:8080",
            "http://[192.168.1.1]:8080",
            "http://[abcdef]:8080",
            "http://[fd00::1]:8080/path",
            "http://user@server.local:8080",
            "http://server local:8080",
            "http://server.local:8080?query=1",
        )
        for target in targets:
            with self.subTest(target=target), self.assertRaises(vol.Invalid):
                self.validate_target(target)


if __name__ == "__main__":
    unittest.main()
