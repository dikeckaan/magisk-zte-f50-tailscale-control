# tailscale-control

Tailscale 1.98.2 (arm64 static) packaged as a Magisk module that does **nothing on its own**. Start/stop is entirely under `statusbot`'s control via the `/tailscale` command.

## Why a separate module

- Tailscale binaries are big (~65 MB). Keeping them in their own module means you can disable/uninstall Tailscale entirely without touching `statusbot` or `bin-utils`.
- Daemon never auto-starts → 0 MB RAM cost unless you explicitly turn it on.
- Routing/iptables changes are scoped to `/tailscale on` and reverted by `/tailscale off`.

## What it ships

| Path | Purpose |
|---|---|
| `/system/bin/tailscale` | CLI client (28 MB) |
| `/system/bin/tailscaled` | Daemon (37 MB) |
| `/data/tailscale/` | State, socket, authkey, log (chmod 700) |

No init scripts. No `service.sh` work. No iptables changes at install time.

## How "adaptive routing" works (and why it won't break your VPN)

The hard rule: **never touch the VPN's tunnel, routing table, or iptables rules.**

How we achieve this:

1. **Daemon's own outbound (control + DERP + WireGuard peers)**
   tailscaled marks its own outbound packets with `fwmark 0x80000`. The kernel's policy router routes marked packets through the **main routing table** — i.e., whatever the *current* default route is.
   - VPN up → main default = `tun0` → daemon's packets ride the VPN
   - VPN down → main default = `sipa_eth0` (cellular) → daemon's packets ride cellular
   - This switches automatically; no reconfiguration needed when VPN toggles.

2. **Exit-node forwarded traffic** (packets coming in from tailnet peers, going out to the public internet)
   The only NAT rule we add is source-based:
   ```
   iptables -t nat -A POSTROUTING -s 100.64.0.0/10 -j MASQUERADE
   ```
   - **No `-o <iface>`** — packet egresses on whatever the kernel chose, again following the main default route.
   - Source range `100.64.0.0/10` is Tailscale's CGNAT range, so this rule **only** matches forwarded tailnet traffic, never VPN or local traffic.

3. **VPN preservation guarantees:**
   - We don't modify the main routing table (no `ip route add default …`)
   - We don't change `/etc/resolv.conf` (`--accept-dns=false` flag)
   - We don't import advertised peer routes (`--accept-routes=false`)
   - VPN's own iptables chain entries are untouched — we only `-A` (append) our own; `off` does targeted `-D` deletions of exactly those.
   - Tailscale uses Android's `VPNService` API → **NO** (the CLI daemon opens TUN directly), so it's not mutually exclusive with VPN apps.

4. **What happens when the VPN drops while Tailscale is active:**
   - Daemon's control-plane connection (controlplane.tailscale.com) momentarily fails, then reconnects via cellular automatically (typically 5-30 s).
   - Already-established peer WireGuard sessions may rebind to the new public-facing IP.
   - Exit-node service degrades briefly during the swap, then resumes.
   - The VPN itself is unaffected — Tailscale didn't cause the drop and doesn't observe it directly.

## RAM footprint

| State | tailscaled RSS |
|---|---|
| Off (no process) | 0 MB |
| On, idle, no peers active | ~25-35 MB |
| On, active exit-node traffic | ~35-60 MB |

On a 2 GB device: idle ≈ 1.5%, busy ≈ 3%. Toggle off when not needed.

## First-time setup

1. **Flash the module** in Magisk Manager. No reboot needed (binaries are immediately available on the next mount cycle, but in practice you may need to either reboot once or run `magisk --remount-system` for the overlay to take effect).
2. **Get an auth key** from <https://login.tailscale.com/admin/settings/keys>:
   - Reusable: yes (so you can rotate the device without regenerating)
   - Ephemeral: optional (auto-expires the device after disconnect)
   - Tags: optional
3. **From Telegram bot:**
   ```
   /tailscale auth tskey-auth-XXXXXXXXXX
   /tailscale on
   ```
4. **In the admin panel** → Machines → ZTE-F50 → **Edit route settings** → enable "Use as exit node". (This is a one-time admin approval; Tailscale advertises it but won't actually serve until you approve.)
5. **On client devices:** `tailscale up --exit-node=zte-f50` (or pick from the menu).

## Bot commands (provided by statusbot v2.9.0+)

```
/tailscale auth <key>     # store auth key (chmod 600, on disk)
/tailscale on             # start daemon + tailscale up + iptables rules
/tailscale off            # tailscale down + kill daemon + iptables cleanup
/tailscale status         # running? IP? exit-node ramp? (default if no arg)
/tailscale ip             # show 100.x.x.x address
/tailscale peers          # full tailscale status output (top 30)
/tailscale logout         # deregister + wipe state + clear authkey
/tailscale log            # last 20 lines of tailscaled.log
```

## Uninstall

Removing via Magisk Manager runs `uninstall.sh` which:
- Stops the daemon if running
- Deletes the iptables rules added by `/tailscale on` (idempotent — no error if absent)
- Removes `/data/tailscale/` entirely (state, authkey, log)
- Binaries vanish on next boot when the overlay unmounts

## Troubleshooting

```sh
# Daemon log
tail -f /data/tailscale/tailscaled.log

# Daemon status from shell
/system/bin/tailscale --socket=/data/tailscale/tailscaled.sock status

# Verify iptables rules added by /tailscale on
iptables -t nat -S POSTROUTING | grep 100.64.0.0
iptables -S FORWARD | grep tailscale0

# IP forwarding (should be 1 while on)
cat /proc/sys/net/ipv4/ip_forward
```

## License

Tailscale is BSD-3 licensed; binaries are unmodified from <https://pkgs.tailscale.com/stable/>. This module's glue scripts are public domain — do whatever.
