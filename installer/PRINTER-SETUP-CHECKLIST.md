# VMS Kiosk — Printer Setup Checklist
## For use by service delivery team at each site deployment

---

## Overview

There are two parts to each deployment:

1. **One-time printer configuration** — done once per physical printer before it goes to site
2. **Per-tablet installation** — run `install.bat` on each tablet

---

## Part 1 — One-Time Printer Configuration
### (Do this once per printer before deployment)

This setting is stored in the printer's firmware and survives power cycles
and USB moves. Once set, it never needs to be done again for that printer.

**You will need:**
- Any Windows PC (does not need to be the kiosk tablet)
- USB cable
- `stw16013b.exe` (included in the installer folder)

**Steps:**

1. Connect the QL-810W to the PC via USB and power it on
2. Run `stw16013b.exe` from the installer folder and complete the installation
3. Open **Printer Setting Tool** from the Windows Start Menu
4. Click **Device Settings**
5. Go to the **Basic** tab
6. Set **Auto Power Off (AC/DC)** to **None**
7. Set **Auto Power Off (Li-ion)** to **None**
8. Click **Apply** — settings are written directly to the printer firmware
9. Close the tool and disconnect USB

The printer will now stay on indefinitely while connected to power.

---

## Part 2 — Per-Tablet Installation
### (Do this on every kiosk tablet)

**You will need:**
- USB drive with installer contents
- The configured Brother QL-810W connected via USB
- Windows Administrator password for the tablet (if applicable)

**Steps:**

1. Plug the USB drive into the tablet
2. Open File Explorer and navigate to the USB drive
3. Open the `installer` folder
4. Double-click **`install.bat`**
5. Click **Yes** on the UAC administrator prompt
6. The installer will run through 5 steps automatically — do not close the window
7. Wait for the final success screen

The installer will display one of two outcomes:

- **Installation Complete** — proceed to verification below
- **Installation Failed** — check `installer\install_log.txt` for the error

---

## Verification Checklist

Complete these checks after every tablet installation:

- [ ] `install.bat` completed with **Installation Complete** screen
- [ ] Brother QL-810W connected via USB and powered on
- [ ] Tablet rebooted after installation
- [ ] After reboot: open kiosk app and complete a test check-in
- [ ] Visitor badge printed correctly with name, date and barcode
- [ ] Barcode on printed badge scans correctly using the built-in scanner
- [ ] Checkout confirmed in the kiosk app after scanning

---

## Barcode Scanner Setup
### (Check on each tablet — settings are stored on the scanner hardware)

The Honeywell N6703 scanner must be in **USB PC Keyboard** mode.
If it was reset or is not working:

1. Open **HotTab** from the Start Menu or front panel button
2. Tap **Device ON/OFF** and enable the **Barcode** icon (must show orange)
3. Open **EZConfig-Scanning** from the Start Menu
4. Click **Connected Device** and wait for the Honeywell N6703 to appear
5. Click **Configure Device**
6. Go to **Interfaces / Communications**
7. Set active interface to **USB PC Keyboard**
8. Click **Save to Device**
9. Go to **Data Formatting** → **Suffix** → **Editor**
10. Add **CR (Carriage Return)** as suffix
11. Click **Save to Device**
12. Test by opening Notepad, scanning a barcode — value should appear as a line of text

---

## Troubleshooting

| Symptom | Action |
|---|---|
| UAC prompt does not appear on double-click | Right-click `install.bat` → Run as administrator |
| Installation Failed at Step 1 (driver) | Install `bsq16aw1101cuk.exe` manually, then re-run `install.bat` |
| Installation Failed at Step 2 (bPAC) | Install `bcciw32001.msi` manually via right-click → Install, then re-run |
| Health check fails at Step 5 | Check `C:\VMS\PrintService\print_server.log` for errors |
| Badge does not print after reboot | Confirm printer is on and USB connected, check log file |
| Printer turns off after idle | Confirm Auto Power Off was set to None via Printer Setting Tool |
| Scanner beeps but nothing appears on screen | Check EZConfig interface is set to USB PC Keyboard |
| Scanner not detected in EZConfig | Scan the USB HID barcode then USB Keyboard barcode from Honeywell programming guide |

---

## File Locations on Installed Tablet

| Item | Path |
|---|---|
| Service executable | `C:\VMS\PrintService\print_server.exe` |
| Label template | `C:\VMS\PrintService\QL-visitor-custom.lbx` |
| Service log | `C:\VMS\PrintService\print_server.log` |
| Install log | `<USB drive>\installer\install_log.txt` |
| Health endpoint | `http://localhost:5050/health` |

---

## Service Management Commands
### (For IT use only — run PowerShell as Administrator)

```powershell
# Check service status
Get-Service BrotherPrintServer

# Restart service
C:\Scripts\nssm.exe restart BrotherPrintServer

# View live log
Get-Content C:\VMS\PrintService\print_server.log -Tail 30 -Wait

# Test health endpoint
Invoke-WebRequest -UseBasicParsing http://localhost:5050/health
```
