#!/system/bin/sh
# tailscale-control service — opt-in autostart.
#
# Tailscale is normally started/stopped on demand via statusbot's /tailscale
# command, since it shouldn't always touch the local-VPN routing. However the
# bot's "on" branch now leaves a marker file at /data/tailscale/autostart to
# express the user's wish ("keep tailscale up across reboots"). This boot
# hook honours that marker:
#
#   * marker missing → do nothing (default RAM-frugal behaviour).
#   * marker present → bring tailscaled + `tailscale up` back, with the same
#                      arguments the bot would have used. Idempotent: bails
#                      out if the daemon already binds the control socket.
#
# `/tailscale off` and `/tailscale logout` clear the marker, so a "stop"
# from the bot is honoured on the next boot without manual intervention.

TS_DIR=/data/tailscale
TS_AUTOSTART="$TS_DIR/autostart"
TS_STATE="$TS_DIR/tailscaled.state"
TS_SOCK="$TS_DIR/tailscaled.sock"
TS_PID="$TS_DIR/tailscaled.pid"
TS_LOG="$TS_DIR/tailscaled.log"
TS_AUTHKEY="$TS_DIR/authkey"
TSD_BIN=/system/bin/tailscaled
TS_BIN=/system/bin/tailscale

# No-op when the marker isn't there
[ -f "$TS_AUTOSTART" ] || exit 0

# Wait for the rootfs to settle and the network to come up before launching.
# Late_start services normally fire ~5-30 s after Magisk hands off, but TUN
# creation depends on the kernel netd being responsive.
sleep 15

# Idempotency: if a previous boot's tailscaled is somehow still around, exit.
if [ -S "$TS_SOCK" ] && [ -f "$TS_PID" ] && kill -0 "$(cat "$TS_PID" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

# Clean stale runtime files left over from a previous unclean stop.
rm -f "$TS_SOCK" "$TS_PID"
ip link delete tailscale0 2>/dev/null

# ip_forward (idempotent — already 1 on Android hotspot builds).
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null

# Mirror the bot's start flags exactly so the resulting node looks identical.
HOME="$TS_DIR" XDG_CACHE_HOME="$TS_DIR/cache" \
TS_DEBUG_FIREWALL_MODE=iptables \
nohup "$TSD_BIN" \
    --tun=tailscale0 \
    --state="$TS_STATE" \
    --socket="$TS_SOCK" \
    --statedir="$TS_DIR" \
    >> "$TS_LOG" 2>&1 &
echo $! > "$TS_PID"

# Wait for the control socket so `tailscale up` can talk to the daemon.
i=0
while [ "$i" -lt 30 ]; do
    [ -S "$TS_SOCK" ] && break
    sleep 1
    i=$((i + 1))
done
[ -S "$TS_SOCK" ] || exit 1

# Re-assert the previously-active node config. The state file holds the
# auth identity; --auth-key is included only if the user explicitly stored
# one via `/tailscale auth`, otherwise we rely on the saved state.
upargs="--advertise-exit-node --accept-dns=false --accept-routes=false --hostname=ZTE-F50"
if [ -s "$TS_AUTHKEY" ]; then
    key=$(cat "$TS_AUTHKEY")
    upargs="$upargs --auth-key=$key"
fi
"$TS_BIN" --socket="$TS_SOCK" up $upargs >> "$TS_LOG" 2>&1 || true

# Source-based iptables for hotspot clients to use tailscale0 as adaptive
# default — same matching as the bot's ts_add_iptables.
iptables -t nat -C POSTROUTING -o tailscale0 -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -o tailscale0 -j MASQUERADE
