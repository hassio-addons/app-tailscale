"""Regression checks for first-start imports of existing Tailscale Services."""

import json
import os
import subprocess
import unittest
from pathlib import Path


RUN_SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "tailscale/rootfs/etc/s6-overlay/s6-rc.d/services/run"
)


class ServicesImportTests(unittest.TestCase):
    """Exercise the production import loop with small bashio stubs."""

    @classmethod
    def setUpClass(cls):
        script = RUN_SCRIPT.read_text(encoding="utf-8")
        start = script.index("    while IFS= read -r service\n", script.index("    # Import services\n"))
        end_marker = '    done <<<"$(bashio::jq "${importable_services}")"'
        end = script.index(end_marker, start) + len(end_marker)
        cls.import_loop = script[start:end]

    def run_import(self, target, existing=""):
        service = json.dumps(
            {"name": "svc:test", "target": target, "port": 80}, separators=(",", ":")
        )
        stubs = r'''
 bashio::jq() {
   local input=$1 query=${2:-}
   if [[ $# -eq 1 ]]; then
     printf '%s\n' "$input"
   else
     python3 -c 'import json,sys; obj=json.loads(sys.argv[1]); key=sys.argv[2].split()[0].lstrip("."); value=obj.get(key); print("" if value is None else value)' "$input" "$query"
   fi
 }
 bashio::var.equals() { [[ "$1" == "$2" ]]; }
 bashio::var.has_value() { [[ -n "$1" ]]; }
 bashio::var.json() {
   python3 -c 'import json,sys; a=sys.argv[1:]; d={};
for k,v in zip(a[::2],a[1::2]):
 d[k]=int(v[1:]) if k=="port" and v.startswith("^") else v
print(json.dumps(d,separators=(",",":")),end="")' "$@"
 }
 bashio::log.info() { :; }
 bashio::log.notice() { :; }
'''
        setup = "\n".join(
            (
                'declare -A service_protocols=(["svc:test|80"]="http")',
                'declare -a configured_services=()',
                'if [[ -n "${EXISTING_SERVICE:-}" ]]; then configured_services+=("${EXISTING_SERVICE}"); fi',
                'declare service service_name target protocol port path service_config anything_imported=false',
                'declare -a service_config_args=()',
                f"importable_services={json.dumps(service)}",
                stubs,
            )
        )
        script = "\n".join(
            (
                "set -e",
                setup,
                self.import_loop,
                'printf "COUNT=%d\\nIMPORTED=%s\\n" "${#configured_services[@]}" "$anything_imported"',
                'printf "CONFIG=%s\\n" "${configured_services[@]}"',
            )
        )
        env = {"PATH": os.defpath, "EXISTING_SERVICE": existing}
        result = subprocess.run(
            ["bash", "-c", script], capture_output=True, text=True, env=env, check=True
        )
        fields = dict(line.split("=", 1) for line in result.stdout.splitlines())
        return fields

    def test_import_preserves_local_and_remote_targets(self):
        targets = (
            "http://127.0.0.1:8123",
            "http://localhost:8123",
            "http://192.168.1.131:80",
            "http://server.local:8080",
            "http://[fd00::1]:8080",
        )
        for target in targets:
            with self.subTest(target=target):
                result = self.run_import(target)
                imported = json.loads(result["CONFIG"])
                self.assertEqual(target, imported["target"])
                self.assertEqual("1", result["COUNT"])
                self.assertEqual("true", result["IMPORTED"])

    def test_matching_existing_service_is_not_imported_twice(self):
        target = "http://192.168.1.131:80"
        imported = self.run_import(target)
        existing = imported["CONFIG"]

        result = self.run_import(target, existing=existing)
        self.assertEqual("1", result["COUNT"])
        self.assertEqual("false", result["IMPORTED"])
        self.assertEqual(existing, result["CONFIG"])


if __name__ == "__main__":
    unittest.main()
