# PYLON

**Stealth & Control Wrapper for ALFA Wireless Adapters on Kali Linux**

PYLON is a simple shell framework to manage your ALFA USB WiFi adapter for **HTB labs**, **CEH practice**, or personal research.  
It provides easy toggling between **listen-only stealth mode** and **active managed mode** while minimizing unnecessary wireless footprint.

---

## Features

- 🔒 **Listen mode** (stealth):
  - Monitor mode enabled
  - Randomized MAC address
  - TX power lowered to reduce signal leakage
  - Outbound traffic blocked with `nftables`

- 📡 **Loud mode** (active):
  - Managed mode enabled
  - Randomized MAC address
  - Outbound traffic allowed

- 🔀 **Switch command** to toggle between listen/loud
- 📑 **Audit command** to print current adapter state (MACs, driver, nftables, etc.)
- ⚙️ **Boot mode** option — auto-start in LISTEN mode each boot
- Automatic **udev rule** renames your ALFA interface to `PYLON`

---

## Installation

```bash
git clone https://github.com/Exterus/PYLON.git
cd PYLON
sudo ./pylon.sh setup
Usage

After setup, you can toggle modes with:

sudo /usr/local/bin/pylon.sh listen     # Stealth mode (monitor, txpower 10, random MAC, outbound blocked)
sudo /usr/local/bin/pylon.sh loud       # Active mode (managed, random MAC, outbound allowed)
sudo /usr/local/bin/pylon.sh switch     # Toggle between modes
sudo /usr/local/bin/pylon.sh audit      # Print current PYLON state
sudo /usr/local/bin/pylon.sh boot-listen on   # Auto start in listen mode at boot

License

MIT License. See LICENSE for details.

Acknowledgment:
This project references and builds upon morrownr’s rtl8814au driver, which is GPLv2 licensed.
All credit for driver development goes to morrownr and contributors.
EOF
