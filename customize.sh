#!/system/bin/sh
# tailscale-control — install binaries + create state dir, NEVER auto-start

SKIPUNZIP=0

ui_print " "
ui_print "  Tailscale Control"
ui_print "  ================="
ui_print " "
ui_print "  Tailscale 1.98.2 (arm64)"
ui_print "  Bot icin: /tailscale {on|off|status|auth|logout|ip|peers|log}"
ui_print " "
ui_print "  HICBIR otomatik baslatma yok. Bot komutuyla acilir."
ui_print "  Default route adaptif: VPN acikken VPN, kapaliyken cellular."
ui_print " "

# Create state dir on /data (survives reboots, NOT in module overlay)
mkdir -p /data/tailscale
chmod 700 /data/tailscale

# Permissions for binaries
set_perm "$MODPATH/system/bin/tailscale"  0 0 0755
set_perm "$MODPATH/system/bin/tailscaled" 0 0 0755

ui_print "  [OK] Binaries installed: /system/bin/tailscale{,d}"
ui_print "  [OK] State dir: /data/tailscale"
ui_print " "
ui_print "  Sonraki adimlar (bottan):"
ui_print "  1) /tailscale auth <tsauth-key>   -- bir kere"
ui_print "  2) /tailscale on                  -- baslat"
ui_print "  3) Tailscale admin paneli > Machines > bu cihaz > Edit route settings"
ui_print "     > Use as exit node -> ENABLE"
ui_print " "
