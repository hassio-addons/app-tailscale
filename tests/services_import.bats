#!/usr/bin/env bats
# Runs the real services/run script against the real bashio library, with only
# the Supervisor, /data and the tailscale binary replaced (helpers/).
#
# Needs bats, and jq >= 1.8 (as shipped in the base image, the run script's jq
# does not compile with older releases). BASHIO_LIB is bashio's lib directory.
# The easiest way to get the exact production tools is the app's base image:
#   docker run --rm --entrypoint sh -v "$PWD:/repo:ro" -w /repo \
#     "$(sed -n 's/^ARG BUILD_FROM=//p' tailscale/Dockerfile)" \
#     -c 'apk add --no-cache bats && BASHIO_LIB=/usr/lib/bashio bats tests'


setup() {
  [[ -f "${BASHIO_LIB:-}/bashio.sh" ]] || { echo "BASHIO_LIB must point to bashio's lib directory" >&2; return 1; }
  export TEST_DIR="${BATS_TEST_TMPDIR}"
  export STUBS="${BATS_TEST_DIRNAME}/helpers/services-stubs.bash"
  export RUN_SCRIPT="${BATS_TEST_DIRNAME}/../tailscale/rootfs/etc/s6-overlay/s6-rc.d/services/run"
  export SERVE_STATUS="${BATS_TEST_DIRNAME}/fixtures/serve-status-empty.json"
  echo '{"services": []}' > "${TEST_DIR}/options.json"
}

# Usage: run_services [<fixture>]; set the services option and marker beforehand.
run_services() {
  [[ -z "${1:-}" ]] || SERVE_STATUS="${BATS_TEST_DIRNAME}/fixtures/${1}"
  export SERVE_STATUS
  # Same shell options as the bashio launcher
  run bash -c '
    set -o errexit -o errtrace -o nounset -o pipefail
    shopt -s inherit_errexit
    source "${BASHIO_LIB}/bashio.sh"
    source "${STUBS}"
    source "${RUN_SCRIPT}"
  '
}

options_services() { jq -S -c '.services' "${TEST_DIR}/options.json"; }
advertised() { grep '^serve --service' "${TEST_DIR}/tailscale.log"; }

@test "first start imports local and remote targets unchanged" {
  run_services serve-status-importable.json
  [ "${status}" -eq 0 ]
  [ "$(options_services)" = "$(jq -S -c . "${BATS_TEST_DIRNAME}/fixtures/imported-services.json")" ]
  [ "$(advertised)" = "$(cat <<'LOG'
serve --service=svc:db --tcp=5432 tcp://192.168.1.20:5432
serve --service=svc:dns --http=80 http://nas.local:8080
serve --service=svc:tls --tls-terminated-tcp=8443 tcp://[fd00::10]:443
serve --service=svc:web --https=443 http://localhost:8123
serve --service=svc:web --https=443 --set-path=/api https+insecure://192.168.1.50:8443
serve --service=svc:web --http=80 http://127.0.0.1:8123
LOG
)" ]
  [ -f "${TEST_DIR}/services_import_is_done" ]
}

@test "first start does not import a service that is already configured" {
  jq '{services: .}' "${BATS_TEST_DIRNAME}/fixtures/imported-services.json" > "${TEST_DIR}/options.json"
  run_services serve-status-importable.json
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already present in the services option, skipping import"* ]]
  [[ "${output}" == *"Nothing to import"* ]]
  [ "$(options_services)" = "$(jq -S -c . "${BATS_TEST_DIRNAME}/fixtures/imported-services.json")" ]
}

@test "import runs only on the first start" {
  touch "${TEST_DIR}/services_import_is_done"
  run_services serve-status-importable.json
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"Importing"* ]]
  [ "$(options_services)" = "[]" ]
  [ -z "$(advertised)" ]
  grep -qx 'serve clear svc:web' "${TEST_DIR}/tailscale.log"
}

@test "services that cannot be imported are reported and cleared" {
  run_services serve-status-not-importable.json
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"can't be imported to the new services option"* ]]
  [[ "${output}" == *"Nothing to import"* ]]
  [ "$(options_services)" = "[]" ]
  grep -qx 'serve clear svc:files' "${TEST_DIR}/tailscale.log"
}

@test "nothing is imported without a current Tailscale Services configuration" {
  run_services serve-status-empty.json
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Nothing to import"* ]]
  [ "$(options_services)" = "[]" ]
}

@test "a rejected import leaves the services option untouched" {
  OPTIONS_FAIL=1 run_services serve-status-importable.json
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"can't be imported to the new services option"* ]]
  [ "$(options_services)" = "[]" ]
}
