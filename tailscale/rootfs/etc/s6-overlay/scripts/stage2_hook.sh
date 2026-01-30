#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Community App: Tailscale
# S6 Overlay stage2 hook to customize services
# ==============================================================================

declare options
declare proxy funnel proxy_and_funnel_port

# This is to execute potentially failing supervisor api functions within conditions,
# where set -e is not propagated inside the function and bashio relies on set -e for api error handling
function try {
    set +e
    (set -e; "$@")
    declare -gx TRY_ERROR=$?
    set -e
}

# Load app options, even deprecated one to upgrade
options=$(bashio::addon.options)

# Upgrade configuration from 'proxy', 'funnel' and 'proxy_and_funnel_port' to 'share_homeassistant' and 'share_on_port'
# This step can be removed in a later version
proxy=$(bashio::jq "${options}" '.proxy | select(.!=null)')
funnel=$(bashio::jq "${options}" '.funnel | select(.!=null)')
proxy_and_funnel_port=$(bashio::jq "${options}" '.proxy_and_funnel_port | select(.!=null)')
# Upgrade to share_homeassistant
if bashio::var.true "${proxy}"; then
    if bashio::var.true "${funnel}"; then
        bashio::addon.option 'share_homeassistant' 'funnel'
        bashio::log.info "Successfully migrated proxy and funnel options to share_homeassistant: funnel"
    else
        bashio::addon.option 'share_homeassistant' 'serve'
        bashio::log.info "Successfully migrated proxy and funnel options to share_homeassistant: serve"
    fi
fi
# Upgrade to share_on_port
if bashio::var.has_value "${proxy_and_funnel_port}"; then
    try bashio::addon.option 'share_on_port' "^${proxy_and_funnel_port}"
    if ((TRY_ERROR)); then
        bashio::log.warning "The proxy_and_funnel_port option value '${proxy_and_funnel_port}' is invalid, proxy_and_funnel_port option is dropped, using default port."
    else
        bashio::log.info "Successfully migrated proxy_and_funnel_port option to share_on_port: ${proxy_and_funnel_port}"
    fi
fi
# Remove previous options
if bashio::var.has_value "${proxy}"; then
    bashio::log.info 'Removing deprecated proxy option'
    bashio::addon.option 'proxy'
fi
if bashio::var.has_value "${funnel}"; then
    bashio::log.info 'Removing deprecated funnel option'
    bashio::addon.option 'funnel'
fi
if bashio::var.has_value "${proxy_and_funnel_port}"; then
    bashio::log.info 'Removing deprecated proxy_and_funnel_port option'
    bashio::addon.option 'proxy_and_funnel_port'
fi

# Disable protect-subnets service when userspace-networking is enabled or accepting routes is disabled
if ! bashio::config.has_value "userspace_networking" || \
    bashio::config.true "userspace_networking" || \
    bashio::config.false "accept_routes";
then
    rm /etc/s6-overlay/s6-rc.d/post-tailscaled/dependencies.d/protect-subnets
fi

# If advertise_routes is configured, do not wait for the local network to be ready to collect subnet information
if bashio::config.exists "advertise_routes";
then
    rm /etc/s6-overlay/s6-rc.d/post-tailscaled/dependencies.d/local-network
fi

# Disable forwarding service when userspace-networking is enabled
if ! bashio::config.has_value "userspace_networking" || \
    bashio::config.true "userspace_networking";
then
    rm /etc/s6-overlay/s6-rc.d/user/contents.d/forwarding
fi

# Disable mss-clamping service when userspace-networking is enabled
if ! bashio::config.has_value "userspace_networking" || \
    bashio::config.true "userspace_networking";
then
    rm /etc/s6-overlay/s6-rc.d/user/contents.d/mss-clamping
fi

# Disable taildrop service when it has been explicitly disabled
if bashio::config.false 'taildrop'; then
    rm /etc/s6-overlay/s6-rc.d/user/contents.d/taildrop
fi

# Disable share-homeassistant service when share_homeassistant has not been explicitly enabled
if ! bashio::config.has_value 'share_homeassistant' || \
    bashio::config.equals 'share_homeassistant' 'disabled'
then
    rm /etc/s6-overlay/s6-rc.d/user/contents.d/share-homeassistant
fi
