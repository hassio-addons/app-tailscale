#!/usr/bin/env bats
# Checks the services.target schema in tailscale/config.yaml. Only the syntax
# and the port are validated there, Tailscale validates the host itself when the
# service is advertised. jq's regular expressions (Oniguruma) understand the
# same syntax as the one Supervisor evaluates, and jq is already in the image.

setup() {
  # Unescape the YAML double-quoted string: match(<regex>)
  regex=$(sed -n 's/^ *target: "match(\(.*\))"$/\1/p' "${BATS_TEST_DIRNAME}/../tailscale/config.yaml" | sed 's/\\\\/\\/g')
  [[ -n "${regex}" ]]
}

matches() {
  jq -en --arg regex "${regex}" --arg target "$1" '$target | test($regex)' > /dev/null
}

@test "accepts localhost, IPv4, IPv6 and DNS targets with every scheme and a port" {
  for target in \
    http://127.0.0.1:13378 \
    https://localhost:8123 \
    https+insecure://192.168.1.100:8443 \
    tcp://10.0.0.2:5432 \
    http://[::1]:8080 \
    http://[fd00::1]:8080 \
    tcp://[2001:DB8::1]:1 \
    http://server.local:8080 \
    https://my-server.home.arpa:65535 \
    http://server.example.com.:8080; do
    matches "${target}" || { echo "rejected: ${target}"; return 1; }
  done
}

@test "rejects what is not scheme://host:port" {
  for target in \
    192.168.1.100:8080 \
    http://192.168.1.100 \
    http://192.168.1.100:0 \
    http://192.168.1.100:65536 \
    http://192.168.1.100:08080 \
    http://192.168.1.100:8080/path \
    http://192.168.1.100:8080?q=1 \
    http://user@192.168.1.100:8080 \
    ftp://192.168.1.100:8080 \
    udp://192.168.1.100:8080 \
    "http://192.168.1.100:8080 " \
    http://:8080 \
    http://[]:8080 \
    http://::1:8080 \
    "http://server local:8080"; do
    ! matches "${target}" || { echo "accepted: ${target}"; return 1; }
  done
}
