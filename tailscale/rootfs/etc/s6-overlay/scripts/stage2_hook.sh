#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Community App: Tailscale
# S6 Overlay stage2 hook to customize services
# ==============================================================================

declare options
declare proxy funnel proxy_and_funnel_port
declare advertise_routes
declare -a routes=()
declare tags
declare taildrive_addons taildrive_config
declare share_service_name

readonly MAGIC_DNS_IPV4="100.100.100.100"
readonly MAGIC_DNS_IPV6="fd7a:115c:a1e0::53"
declare dns
declare invalid_dns_config

# Load app options, even deprecated one to upgrade
options=$(bashio::app.options)

# Upgrade configuration from 'proxy', 'funnel' and 'proxy_and_funnel_port' to 'share_homeassistant' and 'share_on_port'
# This step can be removed in a later version
proxy=$(bashio::jq "${options}" '.proxy | select(.!=null)')
funnel=$(bashio::jq "${options}" '.funnel | select(.!=null)')
proxy_and_funnel_port=$(bashio::jq "${options}" '.proxy_and_funnel_port | select(.!=null)')
# Upgrade to share_homeassistant
if bashio::var.true "${proxy}"; then
    if bashio::var.true "${funnel}"; then
        bashio::app.option 'share_homeassistant' 'funnel'
        bashio::log.info "Successfully migrated proxy and funnel options to share_homeassistant: funnel"
    else
        bashio::app.option 'share_homeassistant' 'serve'
        bashio::log.info "Successfully migrated proxy and funnel options to share_homeassistant: serve"
    fi
fi
# Upgrade to share_on_port
if bashio::var.has_value "${proxy_and_funnel_port}"; then
    bashio::try bashio::app.option 'share_on_port' "^${proxy_and_funnel_port}"
    if bashio::try.failed; then
        bashio::log.warning "The proxy_and_funnel_port option value '${proxy_and_funnel_port}' is invalid, proxy_and_funnel_port option is dropped, using default port."
    else
        bashio::log.info "Successfully migrated proxy_and_funnel_port option to share_on_port: ${proxy_and_funnel_port}"
    fi
fi
# Remove previous options
if bashio::var.has_value "${proxy}"; then
    bashio::log.info 'Removing deprecated proxy option'
    bashio::app.option 'proxy'
fi
if bashio::var.has_value "${funnel}"; then
    bashio::log.info 'Removing deprecated funnel option'
    bashio::app.option 'funnel'
fi
if bashio::var.has_value "${proxy_and_funnel_port}"; then
    bashio::log.info 'Removing deprecated proxy_and_funnel_port option'
    bashio::app.option 'proxy_and_funnel_port'
fi

# Rename changed options
tags=$(bashio::jq "${options}" '.tags | select(.!=null)')
if bashio::var.has_value "${tags}"; then
    bashio::try bashio::app.option 'advertise_tags' "^${tags}"
    if bashio::try.failed; then
        bashio::log.warning "The tags option value is invalid, tags option is dropped, using default no advertise_tags."
        bashio::log.warning "The invalid tags option value is: '${tags}'"
    else
        bashio::log.info "Successfully renamed tags option to advertise_tags"
    fi
    bashio::app.option 'tags'
fi

# Update changed options
taildrive_addons=$(bashio::jq "${options}" '.taildrive.addons | select(.!=null)')
if bashio::var.has_value "${taildrive_addons}"; then
    bashio::log.info 'Updating taildrive option to match new schema'
    taildrive_config=$(bashio::jq "${options}" '
        .taildrive
        | if has("addons") then .local_apps = .addons end | del(.addons)
        | if has("addon_configs") then .app_configs = .addon_configs end | del(.addon_configs)')
    bashio::app.option 'taildrive' "^${taildrive_config}"
fi

# Remove deprecated share_service_name option
share_service_name=$(bashio::jq "${options}" '.share_service_name | select(.!=null)')
if bashio::var.has_value "${share_service_name}"; then
    bashio::log.info 'Removing deprecated share_service_name option'
    bashio::app.option 'share_service_name'
fi

# Migrate advertise_routes option, replace "local_subnets" with the actual values
advertise_routes=$(bashio::jq "${options}" '.advertise_routes | select(.!=null)')
if bashio::var.has_value "${advertise_routes}" && \
    bashio::jq.has_value "${advertise_routes}" '.[] | select(.|test("^local_subnets$"))'
then
    bashio::log.info "Migrating advertise_routes option, replacing \"local_subnets\" with the actual values"
    if ! wait-for-local-network; then
        bashio::log.warning \
            "The local network is temporarily down, can't get local subnet information, can't migrate to actual values." \
            "You have to add the local subnets to the advertise_routes option manually."
        # Keep only user defined other subnets
        readarray -t routes < <(bashio::jq "${advertise_routes}" '.[] | select(.|test("^local_subnets$")|not)')
        # Save it
        advertise_routes=$(bashio::var.json_array "${routes[@]}")
        bashio::app.option 'advertise_routes' "^${advertise_routes}"
    else
        # Read local subnets
        readarray -t routes < <(subnet-routes local)
        if (( 0 == ${#routes[@]} )); then
            bashio::log.warning "There are no local subnets to add in place of \"local_subnets\"!"
        fi
        # Add user defined other subnets
        readarray -t -O "${#routes[@]}" routes < <(bashio::jq "${advertise_routes}" '.[] | select(.|test("^local_subnets$")|not)')
        # Save it
        advertise_routes=$(bashio::var.json_array "${routes[@]}")
        bashio::app.option 'advertise_routes' "^${advertise_routes}"
        # Reread to sanitize values, remove duplicates
        readarray -t routes < <(subnet-routes advertised)
        # Save it again
        advertise_routes=$(bashio::var.json_array "${routes[@]}")
        bashio::app.option 'advertise_routes' "^${advertise_routes}"
    fi
fi

# Check DNS configuration
# This is identical with the check in init-magicdns-proxies/run
# This check is to modify the configuration to prevent the check in init-magicdns-proxies/run from stopping the app startup
invalid_dns_config="false"
for dns in $(bashio::dns.locals); do
    if bashio::var.equals "${dns}" "dns://${MAGIC_DNS_IPV4}" || \
        bashio::var.equals "${dns}" "dns://${MAGIC_DNS_IPV6}"
    then
        bashio::log.warning \
            "Do not configure MagicDNS's IP address (${dns:6}) as DNS server under Settings -> System -> Network"
        invalid_dns_config="true"
    fi
done
if bashio::var.true "${invalid_dns_config}"; then
    bashio::log.warning \
        "Due to invalid networking DNS configuration, userspace_networking option will be enabled to disable MagicDNS"
    bashio::log.warning \
        "Please check your configuration based on the app's documentation under the \"DNS\" section"
    bashio::log.warning \
        "After the issue is fixed you can disable userspace_networking option again and restart the app"
    bashio::app.option 'userspace_networking' '^true'
fi

# MagicDNS related service dependencies:
#
#   user
#   |  ˅
#   |  magicdns-proxies-reconfigurator
#   ˅  ˅
#   magicdns-ingress-proxy
#   |  ˅
#   |  magicdns-proxies-configurator
#   |  ˅
#   |  post-tailscaled
#   |  ˅
#   |  tailscaled
#   |  ˅
#   |  magicdns-egress-proxy
#   ˅  ˅
#   init-magicdns-proxies
#
if bashio::config.true "userspace_networking"; then
    # Disable MagicDNS egress and ingress proxy related services when userspace_networking is enabled
    rm /etc/s6-overlay/user-bundles.d/user/contents.d/magicdns-proxies-reconfigurator
    rm /etc/s6-overlay/user-bundles.d/user/contents.d/magicdns-ingress-proxy
    rm /etc/s6-overlay/s6-rc.d/tailscaled/dependencies.d/magicdns-egress-proxy
elif bashio::config.false "accept_dns"; then
    # Disable MagicDNS egress and ingress proxy reconfigurator when userspace_networking is disabled but accept_dns is also disabled
    rm /etc/s6-overlay/user-bundles.d/user/contents.d/magicdns-proxies-reconfigurator
fi

# Disable protect-subnets service when userspace-networking is enabled or accepting routes is disabled
if bashio::config.true "userspace_networking" || \
    bashio::config.false "accept_routes";
then
    rm /etc/s6-overlay/s6-rc.d/post-tailscaled/dependencies.d/protect-subnets
fi

# If local subnets are not configured in advertise_routes, do not wait for the local network to be ready to collect subnet information
if ! bashio::config "advertise_routes" | grep -Fxq "local_subnets"; then
    rm /etc/s6-overlay/s6-rc.d/post-tailscaled/dependencies.d/local-network
fi

# Disable forwarding service when userspace-networking is enabled
if bashio::config.true "userspace_networking"; then
    rm /etc/s6-overlay/user-bundles.d/user/contents.d/forwarding
fi

# Disable mss-clamping service when userspace-networking is enabled
if bashio::config.true "userspace_networking"; then
    rm /etc/s6-overlay/user-bundles.d/user/contents.d/mss-clamping
fi

# Disable taildrop service when it has been explicitly disabled
if bashio::config.false 'taildrop'; then
    rm /etc/s6-overlay/user-bundles.d/user/contents.d/taildrop
fi

# Disable share-homeassistant service when it has been explicitly disabled
if bashio::config.equals 'share_homeassistant' 'disabled'; then
    rm /etc/s6-overlay/user-bundles.d/user/contents.d/share-homeassistant
fi
