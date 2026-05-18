#!/system/bin/sh
# tailscale-control service — INTENTIONALLY does nothing.
#
# Tailscale is started/stopped on demand via the statusbot /tailscale command.
# This module ships the binaries only; auto-starting on boot would defeat the
# purpose (RAM-frugal, never touch the existing VPN's routing).
#
# To start manually (without bot):
#   tailscaled --tun=tailscale0 \
#     --state=/data/tailscale/tailscaled.state \
#     --socket=/data/tailscale/tailscaled.sock \
#     --statedir=/data/tailscale &
#   tailscale --socket=/data/tailscale/tailscaled.sock up \
#     --advertise-exit-node --accept-dns=false --accept-routes=false \
#     --auth-key=<key>
exit 0
