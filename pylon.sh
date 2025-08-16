#!/usr/bin/env bash
# pylon.sh — One-stop Alfa (AWUS1900 / RTL8814AU) setup + mode switcher for Kali
set -euo pipefail

REQ_PKGS=(iw rfkill macchanger ethtool nftables)
UDEV_RULE="/etc/udev/rules.d/10-pylon.rules"
NFT_FILE="/etc/nftables-pylon.nft"
IFACE="PYLON"

need_root() { [[ $EUID -eq 0 ]] || { echo "Run as root (sudo $0 $*)"; exit 1; }; }
exists()    { ip link show "$1" &>/dev/null; }
curr_mode() { iw dev "$IFACE" info 2>/dev/null | awk '/type/ {print $2; exit}'; }

detect_vidpid() {
  # Prefer Realtek (0bda) devices; narrow to 8812/8813/8814 family if present
  local line
  line="$(lsusb | grep -Ei 'Realtek|0bda' || true)"
  [[ -z "$line" ]] && { echo "No Realtek USB Wi-Fi detected. Plug the Alfa, then re-run."; exit 1; }
  # Extract first VID:PID from the matched line
  local id; id="$(sed -nE 's/.*ID ([0-9a-f]{4}):([0-9a-f]{4}).*/\1:\2/p' <<<"$line" | head -n1)"
  [[ -z "$id" ]] && { echo "Could not parse VID:PID from: $line"; exit 1; }
  echo "$id"
}

write_udev_rule() {
  local vidpid="$1"
  local vid="${vidpid%:*}" ; local pid="${vidpid#*:}"
  cat > "$UDEV_RULE" <<EOF
# Persistently name the Alfa (Realtek USB $vid:$pid) as $IFACE
SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="$vid", ATTRS{idProduct}=="$pid", NAME="$IFACE"
EOF
  udevadm control --reload
  udevadm trigger || true
  echo "[pylon] udev rule written: $UDEV_RULE  (VID:PID=$vid:$pid)"
  echo "[pylon] If interface name didn't change immediately, unplug/replug the Alfa."
}

ensure_packages() {
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y "${REQ_PKGS[@]}"
}

ensure_nft_base() {
  # Minimal nftables base with a set for iface names and a drop chain for egress
  [[ -f "$NFT_FILE" ]] || cat > "$NFT_FILE" <<'EOF'
flush ruleset
table inet pylon {
  set ifaces { type ifname; flags interval; }
  chain egress_pylon {
    type filter hook output priority 0; policy accept;
    oifname @ifaces counter drop
  }
}
EOF
  systemctl enable nftables >/dev/null 2>&1 || true
  if ! nft list tables 2>/dev/null | grep -q '^table inet pylon$'; then
    nft -f "$NFT_FILE"
  fi
}

add_iface_to_drop() {
  ensure_nft_base
  nft add element inet pylon ifaces { "$IFACE" } 2>/dev/null || true
}

remove_iface_from_drop() {
  nft list tables 2>/dev/null | grep -q '^table inet pylon$' || return 0
  nft delete element inet pylon ifaces { "$IFACE" } 2>/dev/null || true
}

listen_mode() {
  # Stealth: monitor mode, randomized MAC, low TX power, no outbound frames
  exists "$IFACE" || { echo "Interface $IFACE not found. Is udev rule applied + device replugged?"; exit 1; }
  nmcli device set "$IFACE" managed no 2>/dev/null || true
  ip link set "$IFACE" down
  macchanger -r "$IFACE" >/dev/null || true
  iw dev "$IFACE" set type monitor 2>/dev/null || true
  ip link set "$IFACE" up
  iwconfig "$IFACE" txpower 10 >/dev/null 2>&1 || true  # quiet default
  add_iface_to_drop
  echo "[pylon] $IFACE => LISTEN: monitor mode, MAC randomized, txpower=10 dBm, outbound blocked."
}

loud_mode() {
  # Active: managed mode, randomized MAC, outbound allowed
  exists "$IFACE" || { echo "Interface $IFACE not found."; exit 1; }
  ip link set "$IFACE" down
  macchanger -r "$IFACE" >/dev/null || true
  iw dev "$IFACE" set type managed 2>/dev/null || true
  ip link set "$IFACE" up
  remove_iface_from_drop
  # Optional: let NM manage it again (comment out if you prefer manual)
  # nmcli device set "$IFACE" managed yes 2>/dev/null || true
  echo "[pylon] $IFACE => LOUD: managed mode, MAC randomized, outbound permitted."
}

switch_mode() {
  local m; m="$(curr_mode || true)"
  if [[ "$m" == "monitor" ]]; then
    echo "[pylon] Detected LISTEN -> switching to LOUD"
    loud_mode
  else
    echo "[pylon] Detected LOUD/unknown -> switching to LISTEN"
    listen_mode
  fi
}

audit() {
  echo "==== PYLON audit ===="
  if exists "$IFACE"; then
    echo -n "Interface: "; ip link show "$IFACE" | head -n1
    echo -n "  MACs: "; macchanger -s "$IFACE" | sed 's/^/  /'
    echo "  Mode: $(curr_mode || echo unknown)"
    echo -n "  Driver: "; ethtool -i "$IFACE" | awk -F': ' '/^driver|^version/{print $1": "$2}' | sed 's/^/  /'
    echo -n "  iwconfig: "; iwconfig "$IFACE" 2>/dev/null | sed 's/^/  /' || true
  else
    echo "Interface $IFACE not present. Replug device or check udev rule."
  fi
  echo "---- nftables ----"
  nft list ruleset 2>/dev/null | sed -n '/table inet pylon/,$p' | sed 's/^/  /' || echo "  (no pylon table)"
  echo "-------------------"
}

boot_listen_enable() {
  cat > /etc/systemd/system/pylon-listen.service <<EOF
[Unit]
Description=Set $IFACE to LISTEN (monitor) mode with low TX and egress block
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pylon.sh listen

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable pylon-listen.service
  echo "[pylon] Boot service enabled: will enter LISTEN mode on startup."
}

boot_listen_disable() {
  systemctl disable pylon-listen.service 2>/dev/null || true
  rm -f /etc/systemd/system/pylon-listen.service
  systemctl daemon-reload
  echo "[pylon] Boot service disabled."
}

setup() {
  need_root
  ensure_packages
  local vidpid; vidpid="$(detect_vidpid)"
  write_udev_rule "$vidpid"
  echo "[pylon] If the interface name isn't '$IFACE' yet, unplug/replug the Alfa and re-run 'pylon.sh audit'."
}
tx_toggle() {
  IFACE="PYLON"
  LOW_MBM=1000   # 10 dBm
  HIGH_MBM=2000  # 20 dBm

  # Get current mode and current txpower (mutes errors if hidden)
  CURR_MODE="$(iw dev "$IFACE" info 2>/dev/null | awk '/type/ {print $2; exit}')"
  CURR_PWR="$(iw dev "$IFACE" info 2>/dev/null | awk '/txpower/ {printf "%.0f", $2}')"

  # Choose target power (flip)
  if [[ -n "$CURR_PWR" && "$CURR_PWR" -ge 20 ]]; then
    TARGET="$LOW_MBM"
    LABEL="10 dBm (stealth)"
  else
    TARGET="$HIGH_MBM"
    LABEL="20 dBm (full)"
  fi

  echo "[pylon] Target txpower -> $LABEL"

  # Try set directly
  if sudo iw dev "$IFACE" set txpower fixed "$TARGET" 2>/dev/null; then
    :
  else
    # Some 8814au builds require managed mode for txpower set — try that path
    echo "[pylon] Direct set failed; trying managed-mode set."
    PREV="$CURR_MODE"
    sudo ip link set "$IFACE" down
    sudo iw dev "$IFACE" set type managed
    sudo ip link set "$IFACE" up
    sudo iw dev "$IFACE" set txpower fixed "$TARGET"
    # Return to previous mode if it was monitor
    if [[ "$PREV" == "monitor" ]]; then
      sudo ip link set "$IFACE" down
      sudo iw dev "$IFACE" set type monitor
      sudo ip link set "$IFACE" up
    fi
  fi

  # Show result
  iw dev "$IFACE" info | grep -i txpower || echo "[pylon] (Driver hides txpower in this mode)"
}

usage() {
  cat <<EOF
Usage: sudo pylon.sh <command>

Commands:
  setup           Install deps, detect Alfa (VID:PID), write udev rule -> $IFACE
  listen          Stealth mode (monitor, rand MAC, txpower 10, outbound blocked)
  loud            Active mode  (managed, rand MAC, outbound allowed)
  switch          Toggle between listen/loud based on current mode
  audit           Print current $IFACE mode, MACs, driver, nftables state
  boot-listen on  Start in LISTEN mode each boot
  boot-listen off Disable auto LISTEN at boot

Tips:
  - After 'setup', unplug/replug the Alfa so udev renames it to $IFACE.
  - Use 'audit' to verify before running labs.
EOF
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    setup)           setup ;;
    listen)          listen_mode ;;
    loud)            loud_mode ;;
    switch)          switch_mode ;;
    toggle)         tx_toggle ;; 
    audit)           audit ;;
    boot-listen)
      case "${1:-}" in
        on)  boot_listen_enable ;;
        off) boot_listen_disable ;;
        *)   echo "Use: sudo pylon.sh boot-listen on|off"; exit 1 ;;
      esac
      ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
toggle)
        IFACE="PYLON"
        LOW=10
        HIGH=20
        current=$(iw dev $IFACE info | awk '/txpower/ {print int($2)}')

        if [ "$current" -ge "$HIGH" ]; then
            echo "[*] Switching $IFACE Tx power -> $LOW dBm (stealth mode)"
            sudo iw dev $IFACE set txpower fixed ${LOW}00
        else
            echo "[*] Switching $IFACE Tx power -> $HIGH dBm (full power)"
            sudo iw dev $IFACE set txpower fixed ${HIGH}00
        fi

        iw dev $IFACE info | grep txpower
        ;;
