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
