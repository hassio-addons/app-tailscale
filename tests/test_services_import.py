"""Regression checks for first-start imports of existing Tailscale Services."""

import os
import re
import shlex
import subprocess
import unittest
from pathlib import Path


RUN_SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "tailscale/rootfs/etc/s6-overlay/s6-rc.d/services/run"
)


class ServicesImportTests(unittest.TestCase):
    """Guard imports against target rewrites and duplicate configurations."""

    @classmethod
    def setUpClass(cls):
        cls.script = RUN_SCRIPT.read_text(encoding="utf-8")
        start = cls.script.index("    # Import services\n")
        end_marker = '    done <<<"$(bashio::jq "${importable_services}")"'
        end = cls.script.index(end_marker, start) + len(end_marker)
        cls.import_block = cls.script[start:end]

    def test_import_preserves_local_and_remote_targets(self):
        target_assignments = [
            line.strip()
            for line in self.import_block.splitlines()
            if re.match(r"^\s*target=", line)
        ]
        extraction = 'target=$(bashio::jq "${service}" \'.target\')'
        self.assertEqual([extraction], target_assignments)

        targets = (
            "http://127.0.0.1:8123",
            "http://localhost:8123",
            "http://192.168.1.131:80",
            "http://server.local:8080",
            "http://[fd00::1]:8080",
        )
        for target in targets:
            with self.subTest(target=target):
                env = {"PATH": os.defpath, "IMPORT_TARGET": target}
                result = subprocess.run(
                    [
                        "bash",
                        "-c",
                        "bashio::jq() { printf '%s' \"$IMPORT_TARGET\"; }; "
                        "service='{}'; "
                        f"{extraction}; "
                        "printf '%s\\n' \"$target\"",
                    ],
                    capture_output=True,
                    text=True,
                    env=env,
                    check=True,
                )
                self.assertEqual(f"{target}\n", result.stdout)

    def test_matching_existing_service_is_not_imported_twice(self):
        marker = "    # The right hand side is quoted on purpose: the space padded values are"
        start = self.import_block.index(marker)
        match = re.search(
            r"      if \[\[ .*?\n      fi\n", self.import_block[start:], re.DOTALL
        )
        self.assertIsNotNone(match, "could not locate the import duplicate guard")
        guard = match.group(0)
        service = (
            '{"name":"svc:test","target":"http://192.168.1.131:80",'
            '"protocol":"http","port":80}'
        )
        program = "\n".join(
            (
                f"configured_services=({shlex.quote(service)})",
                f"service_config={shlex.quote(service)}",
                "anything_imported=false",
                "bashio::log.notice() { :; }",
                guard,
                "printf 'count=%d imported=%s\\n' "
                '"${#configured_services[@]}" "$anything_imported"',
            )
        )
        result = subprocess.run(
            ["bash", "-c", program], capture_output=True, text=True, check=True
        )
        self.assertEqual("count=1 imported=false\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
