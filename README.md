This is a fork of the Home Assistant Tailscale Community app that allows you to:

- Run a second instance of Tailscale, giving you another subdomain on your tailnet (e.g. `immich.your-tailnet.ts.net` in addititon to `homeassistant.your-tailnet.ts.net`)
- Set a custom internal port for proxying, enabling you to serve things other than the Home Assistant UI using Tailscale Funnel

For documentation, please refer to the [official Tailscale addon](https://github.com/hassio-addons/addon-tailscale).

## Installation

1. Add this app repository to Home Assistant:

[![Open your Home Assistant instance and show the add app repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Frayanamal%2Fapp-tailscale)

2. In the app store, install the **Tailscale (2)** app.

3. In the app configuration, set the share option to `funnel` and the `Internal port to proxy` to the internal port you want to proxy.

4. Start the app. Go to the logs. There, you'll see a link like this:

```
https://login.tailscale.com/...
```
 
Open that link to authenticate with Tailscale.

5. In the Tailscale admin console, change the machine name from `homeassistant` to the subdomain prefix you want, e.g. a machine named `immich` will be accessed from `immich.<your-tailnet>.ts.net`. It's also recommended to disable key expiry in machine settings.

6. Restart the app.

## FAQ

### How does this work?

The Tailscale app is a container with the tailscale client running in it. This app has a reverse proxy which forwards requests sent to your tailscale domain (aka tailnet name) to local port 8123, which is the port Home Assistant UI is served from.
The end result is: https://home-assistant.my-tailnet.ts.net → localhost port 8123.

With this knowledge, we can simply duplicate the Tailscale app, give it any name (e.g. my-app) in Tailscale admin console and modify it to forward requests to whatever local port we want (e.g 8080).
The end result is: https://<my-app>.my-tailnet.ts.net → localhost port 8080

### Can I set up a *third* Funnel subdomain with this app?

No. If you want to do this, fork this repo, replace the 3 occurences of `25898` with `25897` in the repository and then load your forked addon. 

Until somebody fixes that hardcoded port number to be randomly selected, or enables an option to disable the Tailscale web interface, this is how it's done.
