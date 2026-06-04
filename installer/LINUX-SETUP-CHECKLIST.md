# VMS Kiosk — Linux Printer Setup Checklist
## Ubuntu 20.04+ — For use by service delivery team at each site deployment

---

## Overview

There are two parts to each deployment:

1. **One-time printer configuration** — done once per physical printer before it goes to site
2. **Per-machine installation** — run `install.sh` on each Ubuntu kiosk machine

The Linux installer replaces the Windows `bPAC` SDK and NSSM service manager with:
- `brother_ql` Python library (drives the QL printer directly over USB — no CUPS needed)
- `systemd` (manages the service instead of NSSM)

---

## USB Drive Contents Required

Place the following on the USB drive before deployment:

```
USB/
  installer/
    install.sh              ← Linux installer (this file's companion)
    install_log_linux.txt   ← written during install
    install.bat             ← Windows installer (unchanged)
    install.ps1             ← Windows installer (unchanged)
    bcciw32001.msi          ← Windows only
    bsq16aw1101cuk.exe      ← Windows only
    nssm.exe                ← Windows only
    wheels/                 ← OPTIONAL: pre-downloaded pip wheels for offline install
  dist/
    print_server_linux.py   ← Linux print server
    print_server.exe        ← Windows print server (unchanged)
    QL-visitor-custom.lbx   ← Windows label template (not used on Linux)
```

### Offline wheel bundle (optional)

If the kiosk machine will not have internet access, pre-download the wheels
on a machine that does, then copy the `wheels/` folder to the installer:

```bash
pip download brother_ql Pillow python-barcode pyusb \
    --dest installer/wheels \
    --platform manylinux2014_x86_64 \
    --python-version 3.8 \
    --only-binary=:all:
```

The installer automatically detects the `wheels/` folder and installs offline.

---

## Part 1 — One-Time Printer Configuration
### (Do this once per printer before deployment)

This is identical to the Windows procedure. The Printer Setting Tool only runs on
Windows, but the setting is stored in the printer's firmware — configure it once
on any Windows PC and it will work on Linux deployments.

**You will need:**
- Any Windows PC (does not need to be the kiosk machine)
- USB cable
- `stw16013b.exe` (included in the Windows installer folder)

**Steps:**

1. Connect the QL-810W to the Windows PC via USB and power it on
2. Run `stw16013b.exe` and complete the installation
3. Open **Printer Setting Tool** from the Windows Start Menu
4. Click **Device Settings**
5. Go to the **Basic** tab
6. Set **Auto Power Off (AC/DC)** to **None**
7. Set **Auto Power Off (Li-ion)** to **None**
8. Click **Apply** — settings are written directly to the printer firmware
9. Close the tool and disconnect USB

Once set, this never needs to be done again for that printer.

---

## Part 2 — Per-Machine Installation
### (Do this on every Ubuntu kiosk machine)

**You will need:**
- USB drive with installer contents
- The configured Brother QL-810W connected via USB
- `sudo` password (or root access) for the machine

**Steps:**

1. Plug the USB drive into the machine
2. Open a terminal
3. Find the USB mount point:
   ```bash
   lsblk -o NAME,MOUNTPOINT,LABEL | grep -v "^loop"
   ```
   The USB will typically mount to `/media/$USER/<drive-label>`.

4. Navigate to the installer folder:
   ```bash
   cd /media/$USER/<drive-label>/installer
   ```

5. Run the installer as root:
   ```bash
   sudo bash install.sh
   ```

6. Press **ENTER** when prompted to begin.

7. The installer runs through 5 steps automatically — do not close the terminal.

8. Wait for the final **Installation Complete!** screen.

The installer displays one of two outcomes:

- **Installation Complete!** — proceed to verification below
- **[FAIL]** message — check `installer/install_log_linux.txt` for the error

---

## Verification Checklist

Complete these checks after every machine installation:

- [ ] `install.sh` completed with **Installation Complete!** screen
- [ ] Brother QL-810W connected via USB and powered on
- [ ] Machine rebooted after installation
- [ ] After reboot: service starts automatically
  ```bash
  systemctl status BrotherPrintServer
  ```
- [ ] Health endpoint responds:
  ```bash
  curl http://localhost:5050/health
  ```
  Expected: `{"status": "ok", "printer": "usb://0x04f9:0x...", ...}`
- [ ] Open kiosk app and complete a test check-in
- [ ] Visitor badge prints correctly with name, date, and barcode
- [ ] Barcode on printed badge scans correctly using the built-in scanner
- [ ] Checkout confirmed in the kiosk app after scanning

---

## Label Layout

On Linux the label is generated in Python (no `.lbx` template). The layout on
62 mm × ~90 mm continuous tape is:

```
+---------------------------+
| VISITOR                   |  ← visitorType (white on black banner)
|                           |
| John Smith                |  ← visitorName (large bold)
| ACME Corp                 |  ← visitorCompany
| Host: Jane Doe            |  ← visitorHost
| 2026/06/03                |  ← visitorDate
| ─────────────────────── |
| [||||||||||||||||||||||||] |  ← Code128 barcode of visitorId
+---------------------------+
```

To adjust label height or font sizes, edit `LABEL_H` and the `get_font` size
calls in `dist/print_server_linux.py`. A 1000 px height ≈ 84 mm at 300 DPI.

---

## Troubleshooting

| Symptom | Action |
|---|---|
| `Permission denied` on `install.sh` | Run with `sudo bash install.sh`, not `./install.sh` |
| `[FAIL] Ubuntu 20.04 or later required` | Upgrade the OS before installing |
| `[FAIL] Missing dependency` on first run | Ensure internet access; check `install_log_linux.txt` |
| Service shows `failed` after install | Run `journalctl -u BrotherPrintServer -n 50` for details |
| Health check returns `"printer": "not detected"` | Check USB cable; try unplugging and re-plugging the printer |
| Badge does not print (printer found) | Check `journalctl -u BrotherPrintServer -n 30`; confirm tape is loaded |
| Printer turns off after idle | Confirm Auto Power Off was set to None via Printer Setting Tool on Windows |
| `usb.core.USBError: [Errno 13]` | Unplug and re-plug the printer (udev rule not applied to already-connected device) |
| Label appears blank or white | Ensure correct tape (62 mm continuous) is loaded in the printer |

---

## File Locations After Installation

| Item | Path |
|---|---|
| Service Python script | `/opt/vms/print-service/print_server_linux.py` |
| Python virtual environment | `/opt/vms/print-service/venv/` |
| Service log | `/opt/vms/print-service/print_server.log` |
| systemd unit file | `/etc/systemd/system/BrotherPrintServer.service` |
| udev rule | `/etc/udev/rules.d/99-brother-ql.rules` |
| Install log | `<USB drive>/installer/install_log_linux.txt` |
| Health endpoint | `http://localhost:5050/health` |

---

## Service Management Commands

```bash
# Check service status
systemctl status BrotherPrintServer

# Restart service
systemctl restart BrotherPrintServer

# View live log
journalctl -u BrotherPrintServer -f

# View log file directly
tail -f /opt/vms/print-service/print_server.log

# Test health endpoint
curl http://localhost:5050/health

# Test a print job
curl -X POST http://localhost:5050/print \
  -H "Content-Type: application/json" \
  -d '{
    "visitorName":    "Test Visitor",
    "visitorCompany": "ACME Corp",
    "visitorType":    "Visitor",
    "visitorHost":    "Jane Doe",
    "visitorDate":    "2026/06/03",
    "visitorId":      "VIS-00001",
    "copies":         1
  }'

# Stop service
systemctl stop BrotherPrintServer

# Uninstall completely
systemctl stop BrotherPrintServer
systemctl disable BrotherPrintServer
rm /etc/systemd/system/BrotherPrintServer.service
rm /etc/udev/rules.d/99-brother-ql.rules
rm -rf /opt/vms/print-service
systemctl daemon-reload
udevadm control --reload-rules
```
