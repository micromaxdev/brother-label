# VMS Kiosk — Printer Setup Checklist

## For use by service delivery team at each site deployment

---

## Overview

There are three parts to each deployment:

| Part                                          | Who                | When                                            |
| --------------------------------------------- | ------------------ | ----------------------------------------------- |
| **Part 1** — One-time printer firmware config | Any technician     | Once per physical printer, before going to site |
| **Part 2** — Per-kiosk installation           | On-site technician | On every kiosk tablet                           |
| **Part 3** — Post-reboot verification         | On-site technician | After every installation                        |

> **Important:** Each step below has a verification check. Do not proceed to the next step until the check passes. If a check fails, refer to the Troubleshooting section at the bottom.

---

## Part 1 — One-Time Printer Firmware Configuration

### (Do this once per physical printer before it goes to site)

This setting is stored in the printer's hardware and survives reboots, USB moves, and reinstalls. Once set, it never needs to be done again for that printer unit.

**You will need:**

- Any Windows PC (does not need to be a kiosk tablet)
- USB cable
- `stw16013b.exe` (Printer Setting Tool — included in the installer folder)

---

### 1.1 — Connect and launch

1. Connect the QL-810W to the PC via USB
2. Power on the printer (green power light steady)
3. Run `stw16013b.exe` and complete the installation if prompted
4. Open **Printer Setting Tool** from the Windows Start Menu

**Verify before continuing:**

- [ ] Printer Setting Tool opens without error
- [ ] The tool shows "Brother QL-810W" as the connected printer

---

### 1.2 — Disable Auto Power Off

1. Click **Device Settings**
2. Go to the **Basic** tab
3. Set **Auto Power Off (AC/DC)** → `None`
4. Set **Auto Power Off (Li-ion)** → `None`
5. Click **Apply** — the tool will write the settings directly to the printer firmware
6. Wait for the confirmation message
7. Close the tool and disconnect USB

**Verify before continuing:**

- [ ] Apply completed without error
- [ ] Re-open Device Settings and confirm both fields still show `None`

> If Auto Power Off is not disabled, the printer will go offline during quiet periods and print jobs will silently fail or queue as errors.

---

## Part 2 — Per-Kiosk Installation

### (Do this on every kiosk tablet)

**You will need:**

- USB stick with the installer folder and dist folder
- The configured Brother QL-810W connected via USB to the kiosk
- Windows Administrator access on the kiosk

**Folder structure required on USB stick:**

```
USB:\
  installer\
    install.bat
    bsq16aw1101cuk.exe
    bcciw32001.msi
    nssm.exe
    stw16013b.exe
    PRINTER-SETUP-CHECKLIST.md
  dist\
    print_server.exe
    QL-visitor-custom.lbx
```

---

### 2.1 — Pre-installation checks

Before running the installer, confirm:

- [ ] Brother QL-810W is plugged in via USB
- [ ] Brother QL-810W is powered on (green light steady, not flashing)
- [ ] USB stick is plugged into the kiosk
- [ ] You can see both the `installer` and `dist` folders on the USB stick

---

### 2.2 — Run the installer

1. Open File Explorer and navigate to the USB stick `installer` folder
2. Right-click **`install.bat`** → **Run as administrator**
3. Click **Yes** on the UAC prompt

The installer runs through **6 steps** with a pause at each one. Do not close the window.

---

### 2.3 — Step-by-step guide through the installer

#### Step 1 — Pre-Installation Cleanup

The installer removes any previous installation and clears stuck print jobs.

**Verify before pressing any key:**

- [ ] Output shows `[OK]` for service removal (or "No existing service found")
- [ ] Output shows `[OK]` for install directory removal
- [ ] Output shows `[OK]` for print spooler cleared

---

#### Step 2 — Brother Printer Driver

The installer launches the Brother driver installer GUI.

When the GUI opens:

1. Select **QL-810W** as the printer model
2. Select **Local Connection (USB)**
3. Complete the installation
4. If prompted to restart — select **Restart Later** (the script will handle this)

**Verify before pressing any key:**

- [ ] Output shows `[OK] Brother driver found in driver store`
- [ ] Open **Device Manager** (`Win + X` → Device Manager)
- [ ] Confirm **Brother QL-810W** appears under **Print queues**
- [ ] Confirm there is **no yellow warning triangle** on it
- [ ] Confirm it does **not** appear under **Other devices**

---

#### Step 3 — Force Correct Driver Binding

This step fixes a Windows 11 issue where it silently swaps the Brother driver for its own generic "Microsoft IPP Class Driver", which prevents bPAC from printing.

**Verify before pressing any key:**

- [ ] Output shows `DriverName : Brother QL-810W`
- [ ] Output does **not** show `Microsoft IPP Class Driver`

> This step is the most common failure point on fresh Windows 11 machines. If the driver name is wrong here, printing will silently fail even though the service reports success.

---

#### Step 4 — bPAC Client Component

Installs the Brother bPAC COM library that `print_server.exe` uses to generate labels.

**Verify before pressing any key:**

- [ ] Output shows `[OK] bPAC installed successfully` (or "already installed")
- [ ] Output shows `[OK] bPAC COM object registered`

---

#### Step 5 — Service Installation

Copies files, configures USB power settings, and registers the Windows service.

**Verify before pressing any key:**

- [ ] Output shows `[OK] USB selective suspend disabled`
- [ ] Output shows `[OK] Both service files found in dist`
- [ ] Output shows `[OK] Files copied to C:\VMS\PrintService`
- [ ] Output shows `[OK] Service registered`

---

#### Step 6 — Full Verification

The installer performs four automatic checks and sends a real test print.

**Verify before pressing any key:**

- [ ] `[1/4]` Service is RUNNING
- [ ] `[2/4]` Health endpoint responded with `{"status": "ok", ...}`
- [ ] `[3/4]` Driver confirmed: `Brother QL-810W`
- [ ] `[4/4]` Test print sent — **a label physically printed from the printer**

> If a label did not print despite `[4/4]` showing OK, do not proceed. Check the service log at `C:\VMS\PrintService\print_server.log`.

---

### 2.4 — Post-installer steps

After the **Installation Complete** screen:

1. Note the reminder about Auto Power Off (Part 1 of this guide)
2. Press any key to close the installer
3. **Reboot the kiosk**

---

## Part 3 — Post-Reboot Verification

### (Complete after every installation)

After the kiosk reboots, verify the service starts automatically and printing still works end-to-end through the kiosk application.

---

### 3.1 — Service auto-start check

1. Open an admin PowerShell or CMD
2. Run:
   ```
   sc query BrotherPrintServer
   ```
3. Confirm output shows `STATE : 4 RUNNING`

- [ ] Service is RUNNING after reboot without any manual intervention

---

### 3.2 — Health endpoint check

In admin PowerShell:

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:5050/health
```

- [ ] Returns `StatusCode : 200`
- [ ] Content shows correct printer name and template path

---

### 3.3 — End-to-end kiosk test

1. Open the kiosk application
2. Complete a full test check-in with a real name and company
3. Confirm a badge label prints correctly
4. Confirm the badge shows name, date, and barcode
5. Scan the barcode with the built-in scanner and confirm it reads

- [ ] Badge printed with correct content
- [ ] Barcode on badge scanned correctly

---

## Barcode Scanner Setup

### (Verify on each tablet — settings are stored on the scanner hardware)

The Honeywell N6703 scanner must be in **USB PC Keyboard** mode.
If it was reset or is not responding:

1. Open **HotTab** from the Start Menu or front panel button
2. Tap **Device ON/OFF** → enable the **Barcode** icon (shows orange when on)
3. Open **EZConfig-Scanning** from the Start Menu
4. Click **Connected Device** and wait for the Honeywell N6703 to appear
5. Click **Configure Device**
6. Go to **Interfaces / Communications** → set active interface to **USB PC Keyboard**
7. Click **Save to Device**
8. Go to **Data Formatting → Suffix → Editor** → add **CR (Carriage Return)** as suffix
9. Click **Save to Device**
10. Open Notepad and scan a barcode — value should appear as a line of text

- [ ] Scanner reads barcodes and output appears in Notepad

---

## Troubleshooting

| Symptom                                                  | Likely cause                               | Action                                                                                               |
| -------------------------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------- | -------------- |
| UAC prompt does not appear                               | Script not run as admin                    | Right-click `install.bat` → Run as administrator                                                     |
| Step 2 fails — driver not in store                       | Brother installer silently failed          | Run `bsq16aw1101cuk.exe` manually, complete the GUI, then re-run `install.bat`                       |
| Step 2 — printer in "Other devices" with yellow triangle | Driver mismatch or install error           | Uninstall from Device Manager → delete driver → rerun `bsq16aw1101cuk.exe` manually                  |
| Step 3 — driver still shows "Microsoft IPP Class Driver" | Windows re-grabbed the printer             | Run `printui.exe /Xs /n "Brother QL-810W" DriverName "Brother QL-810W"` in admin CMD, then re-verify |
| Step 4 fails — COM object not registered                 | bPAC MSI failed silently                   | Right-click `bcciw32001.msi` → Install, complete GUI, then re-run `install.bat`                      |
| Step 6 — service not running                             | print_server.exe crash on start            | Check `C:\VMS\PrintService\print_server.log` for the error                                           |
| Step 6 — health check fails                              | Port 5050 blocked or service not up        | Check log, confirm no other process on port 5050: `netstat -ano                                      | findstr :5050` |
| Step 6 — test print sent OK but no label printed         | Driver reverted to IPP after service start | Re-run Step 3 manually then restart service                                                          |
| Service stops working after reboot                       | Windows reassigned IPP driver on boot      | Run Step 3 commands manually and restart service — add a startup task if this recurs                 |
| Printer turns off during the day                         | Auto Power Off not disabled                | Run Printer Setting Tool (`stw16013b.exe`), set both Auto Power Off values to None, apply            |
| Badge prints but barcode does not scan                   | Scanner not configured                     | Follow Barcode Scanner Setup section above                                                           |
| Scanner beeps but nothing appears                        | Wrong interface mode                       | Set to USB PC Keyboard in EZConfig-Scanning                                                          |

---

## Manual Recovery Commands

### (For IT use only — run CMD or PowerShell as Administrator)

**Check service status:**

```cmd
sc query BrotherPrintServer
```

**Restart service:**

```cmd
C:\Users\VMS\Downloads\installer\nssm.exe restart BrotherPrintServer
```

**Check what driver Windows is using:**

```powershell
Get-Printer | Where-Object { $_.Name -eq "Brother QL-810W" } | Select-Object Name, DriverName, PortName | Format-List
```

**Force correct driver (run if driver has reverted to IPP):**

```cmd
printui.exe /Xs /n "Brother QL-810W" DriverName "Brother QL-810W"
```

**Send a manual test print:**

```powershell
Invoke-WebRequest -UseBasicParsing -Uri http://localhost:5050/print -Method POST -ContentType 'application/json' -Body '{"visitorName":"Test User","visitorCompany":"Micromax","visitorDate":"2026/06/12","visitorType":"Visitor","visitorId":"","visitorHost":""}'
```

**View live service log:**

```powershell
Get-Content C:\VMS\PrintService\print_server.log -Tail 30 -Wait
```

**Check health endpoint:**

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:5050/health
```

**Clear stuck print jobs:**

```cmd
net stop spooler
del /q /f /s "%SystemRoot%\System32\spool\PRINTERS\*.*"
net start spooler
```

---

## File Locations Reference

| Item               | Path                                        |
| ------------------ | ------------------------------------------- |
| Service executable | `C:\VMS\PrintService\print_server.exe`      |
| Label template     | `C:\VMS\PrintService\QL-visitor-custom.lbx` |
| Service log        | `C:\VMS\PrintService\print_server.log`      |
| Install log        | `<USB stick>\installer\install_log.txt`     |
| Health endpoint    | `http://localhost:5050/health`              |
| Print endpoint     | `http://localhost:5050/print` (POST)        |
