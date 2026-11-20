# shellcheck shell=bash
# ==============================================================================
# Test doubles for tailscale/rootfs/etc/s6-overlay/s6-rc.d/services/run
#
# Sourced after the real bashio library and before the real run script, so only
# what talks to the outside world is replaced: the Supervisor API, /data and the
# tailscale binary. bashio's own jq, var, try, log and exit helpers stay real.
#
# Inputs (environment):
#   TEST_DIR       scratch directory holding options.json and the /data marker
#   SERVE_STATUS   file returned by `tailscale serve status --json`
#   OPTIONS_FAIL   when set, writing the app options fails (Supervisor rejects)
# Outputs:
#   ${TEST_DIR}/options.json    app options as the Supervisor would store them
#   ${TEST_DIR}/tailscale.log   one line per /opt/tailscale invocation
# ==============================================================================

function bashio::app.config() {
  cat "${TEST_DIR}/options.json"
}

# Called with a slug to read the options, with a slug and JSON to write them.
function bashio::app.options() {
  if (($# == 2)); then
    [[ -z "${OPTIONS_FAIL:-}" ]] || return 1
    printf '%s' "${2}" > "${TEST_DIR}/options.json"
  else
    cat "${TEST_DIR}/options.json"
  fi
}

function touch() {
  command touch "${1/#\/data\//${TEST_DIR}/}"
}

function bashio::fs.file_exists() {
  [[ -f "${1/#\/data\//${TEST_DIR}/}" ]]
}

function /opt/tailscale() {
  printf '%s\n' "$*" >> "${TEST_DIR}/tailscale.log"
  case "$*" in
    "serve status --json") cat "${SERVE_STATUS}" ;;
    "status --self=true --peers=false --json") echo '{"Self":{"CapMap":{"https":[]}}}' ;;
  esac
}
