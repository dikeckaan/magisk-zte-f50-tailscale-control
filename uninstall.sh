#!/system/bin/sh
# Stop tailscale if running, then remove state dir
PID=$(cat /data/tailscale/tailscaled.pid 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    /system/bin/tailscale --socket=/data/tailscale/tailscaled.sock down 2>/dev/null
    kill "$PID" 2>/dev/null
    sleep 1
    kill -9 "$PID" 2>/dev/null
fi
# Remove iptables rules we may have added (idempotent)
iptables -t nat -D POSTROUTING -s 100.64.0.0/10 -j MASQUERADE 2>/dev/null
iptables -D FORWARD -i tailscale0 -j ACCEPT 2>/dev/null
iptables -D FORWARD -o tailscale0 -j ACCEPT 2>/dev/null
# Wipe state
rm -rf /data/tailscale
