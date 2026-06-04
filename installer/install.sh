#!/usr/bin/env bash
# install.sh
# VMS Print Service Installer — Ubuntu 20.04+
# Run as root from the installer folder:
#   sudo bash install.sh

set -euo pipefail

SERVICE_NAME="BrotherPrintServer"
INSTALL_DIR="/opt/vms/print-service"
SERVICE_PORT="5050"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$(dirname "$SCRIPT_DIR")/dist"
LOG="$SCRIPT_DIR/install_log_linux.txt"
VENV_DIR="$INSTALL_DIR/venv"
PY_SCRIPT="print_server_linux.py"

REQUIRED_PKGS="python3 python3-venv python3-pip libusb-1.0-0"
PIP_PKGS="brother_ql Pillow 'qrcode[pil]' pyusb"

# ── Helpers ──────────────────────────────────────────────────────

log()  { echo "$*" | tee -a "$LOG"; }
step() { echo ""; echo ">>> $*" | tee -a "$LOG"; }
ok()   { echo "    [OK] $*"   | tee -a "$LOG"; }
fail() { echo "    [FAIL] $*" | tee -a "$LOG"; exit 1; }

header() {
    clear
    echo "================================================"
    echo "  $*"
    echo "================================================"
    echo ""
}

# ── Bootstrap log ────────────────────────────────────────────────

echo ""  > "$LOG"
echo "VMS Print Service Installer (Linux)" >> "$LOG"
echo "Started: $(date)"                    >> "$LOG"
echo ""                                    >> "$LOG"

# ── Welcome ──────────────────────────────────────────────────────

header "VMS Print Service Installer (Ubuntu)"
echo "This will install all required components."
echo "Please do not close this terminal."
echo ""
echo "Log file: $LOG"
echo ""
read -rp "Press ENTER to begin..."


# ============================================================
# Pre-flight checks
# ============================================================

step "Checking prerequisites..."

# Root check
if [[ $EUID -ne 0 ]]; then
    fail "Must be run as root. Re-run with: sudo bash install.sh"
fi
ok "Running as root."

# Ubuntu 20.04+ check
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        fail "This installer requires Ubuntu. Detected: ${PRETTY_NAME:-unknown}"
    fi
    VER_MAJOR="${VERSION_ID%%.*}"
    if [[ "$VER_MAJOR" -lt 20 ]]; then
        fail "Ubuntu 20.04 or later required. Detected: ${PRETTY_NAME:-unknown}"
    fi
    ok "OS check passed: ${PRETTY_NAME}"
else
    fail "Cannot read /etc/os-release — unsupported OS."
fi

# dist folder check
if [[ ! -f "$DIST_DIR/$PY_SCRIPT" ]]; then
    fail "$PY_SCRIPT not found at: $DIST_DIR/$PY_SCRIPT"
fi
ok "Found $PY_SCRIPT in dist folder."


# ============================================================
# STEP 1 — System packages
# ============================================================

header "STEP 1 of 5: System Dependencies"
echo "Installing required system packages..."
echo "(Requires internet access)"
echo ""

log "apt-get update..."
# Use --ignore-missing so a broken third-party PPA does not abort the update.
# Core Ubuntu repos (which have our packages) will still be refreshed.
apt-get update --ignore-missing 2>&1 | tee -a "$LOG" || {
    echo "    [WARN] apt-get update reported errors (likely a broken PPA on this machine)." | tee -a "$LOG"
    echo "    [WARN] Attempting to continue — package install will fail if repos are truly missing." | tee -a "$LOG"
}

log "Installing: $REQUIRED_PKGS"
# shellcheck disable=SC2086
if ! apt-get install -y $REQUIRED_PKGS 2>&1 | tee -a "$LOG"; then
    echo "" | tee -a "$LOG"
    echo "    [HINT] If the error above mentions a broken PPA, fix it first:" | tee -a "$LOG"
    echo "           sudo add-apt-repository --remove ppa:<name>" | tee -a "$LOG"
    echo "           Then re-run: sudo bash install.sh" | tee -a "$LOG"
    fail "Package installation failed. See hints above and check $LOG"
fi

ok "System packages installed."
sleep 2


# ============================================================
# STEP 2 — USB power & permissions
# ============================================================

header "STEP 2 of 5: USB Power & Permissions"

# Stop and disable every daemon that auto-claims the USB printer port.
# All three (usblp kernel module, CUPS, ipp-usb) will cause [Errno 16]
# Resource busy and block brother_ql from accessing the device directly.

# 1. usblp kernel module
BLACKLIST_FILE="/etc/modprobe.d/blacklist-usblp.conf"
echo "blacklist usblp" > "$BLACKLIST_FILE"
update-initramfs -u 2>&1 | tee -a "$LOG"
modprobe -r usblp 2>/dev/null || true
ok "usblp kernel module blacklisted."

# 2. CUPS print server
systemctl stop    cups cups-browsed 2>/dev/null || true
systemctl disable cups cups-browsed 2>/dev/null || true
ok "CUPS stopped and disabled."

# 3. ipp-usb — Ubuntu 20.04+ daemon that grabs USB printers as IPP devices.
#    Runs independently of CUPS and will hold the device even when CUPS is off.
systemctl stop    ipp-usb 2>/dev/null || true
systemctl disable ipp-usb 2>/dev/null || true
ok "ipp-usb stopped and disabled."

# Disable USB autosuspend for Brother printers (replaces Windows powercfg)
# Also unbind usblp immediately on plug-in as a belt-and-suspenders fallback.
UDEV_RULE_FILE="/etc/udev/rules.d/99-brother-ql.rules"
cat > "$UDEV_RULE_FILE" <<'UDEV'
# Brother QL label printers — disable USB autosuspend, allow open access
# Unbind usblp immediately when the printer is plugged in so brother_ql
# can claim the device via libusb without getting "Resource busy".
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="04f9", RUN+="/bin/sh -c 'for f in /sys%p/*/usblp*/driver/unbind; do [ -e \"$f\" ] && echo -n $(basename $(dirname $(dirname $f))) > $f; done'"
SUBSYSTEM=="usb", ATTRS{idVendor}=="04f9", MODE="0666", ATTR{power/control}="on"
UDEV

udevadm control --reload-rules 2>&1 | tee -a "$LOG"
udevadm trigger            2>&1 | tee -a "$LOG"

ok "udev rule written to $UDEV_RULE_FILE"
ok "USB autosuspend disabled for Brother printers."
echo ""
echo "NOTE: If the printer is already connected, unplug and re-plug it"
echo "      after installation so the udev rule takes effect."
sleep 2


# ============================================================
# STEP 3 — Copy service files
# ============================================================

header "STEP 3 of 5: Installing Service Files"

# Stop and remove existing service if present
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "Found existing service. Stopping..." | tee -a "$LOG"
    systemctl stop "$SERVICE_NAME"
    sleep 2
    ok "Existing service stopped."
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME" 2>&1 | tee -a "$LOG"
fi

if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    ok "Old service unit removed."
fi

# Create install directory
mkdir -p "$INSTALL_DIR"
ok "Directory ready: $INSTALL_DIR"

# Copy Python server script
cp "$DIST_DIR/$PY_SCRIPT" "$INSTALL_DIR/"
ok "Copied $PY_SCRIPT to $INSTALL_DIR"

log "Files installed to $INSTALL_DIR"
sleep 2


# ============================================================
# STEP 4 — Python virtual environment & service
# ============================================================

header "STEP 4 of 5: Python Environment & Service"

# Create venv
echo "Creating Python virtual environment..."
python3 -m venv "$VENV_DIR" 2>&1 | tee -a "$LOG"
ok "Virtual environment created at $VENV_DIR"

# Upgrade pip quietly
"$VENV_DIR/bin/pip" install --quiet --upgrade pip 2>&1 | tee -a "$LOG"

# Install pip packages — prefer bundled wheels if present, else use PyPI
WHEELS_DIR="$SCRIPT_DIR/wheels"
if [[ -d "$WHEELS_DIR" ]]; then
    echo "Found bundled wheels — installing offline from $WHEELS_DIR"
    "$VENV_DIR/bin/pip" install --quiet --no-index --find-links "$WHEELS_DIR" $PIP_PKGS \
        2>&1 | tee -a "$LOG"
    ok "Python packages installed from bundled wheels."
else
    echo "Installing Python packages from PyPI..."
    echo "(Requires internet access)"
    # shellcheck disable=SC2086
    "$VENV_DIR/bin/pip" install --quiet $PIP_PKGS 2>&1 | tee -a "$LOG"
    ok "Python packages installed from PyPI."
fi

# Create systemd service unit
SERVICE_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_UNIT" <<UNIT
[Unit]
Description=VMS Brother Label Print Service
After=network.target

[Service]
Type=simple
ExecStart=${VENV_DIR}/bin/python3 ${INSTALL_DIR}/${PY_SCRIPT}
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=3
StandardOutput=append:${INSTALL_DIR}/print_server.log
StandardError=append:${INSTALL_DIR}/print_server.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" 2>&1 | tee -a "$LOG"
ok "systemd service registered and enabled."

echo ""
echo "Starting service..."
systemctl start "$SERVICE_NAME"
sleep 5

ok "Print service started."
sleep 2


# ============================================================
# STEP 5 — Verify
# ============================================================

header "STEP 5 of 5: Verifying Installation"

echo "Checking service status..."
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo ""
    echo "Service log (last 20 lines):"
    tail -n 20 "$INSTALL_DIR/print_server.log" 2>/dev/null || true
    fail "Service is not running. Check $INSTALL_DIR/print_server.log"
fi
ok "Service is running."

echo ""
echo "Checking health endpoint..."
if command -v curl &>/dev/null; then
    HEALTH=$(curl -sf --max-time 10 "http://localhost:$SERVICE_PORT/health" || true)
else
    HEALTH=$(python3 -c "
import urllib.request, json
try:
    r = urllib.request.urlopen('http://localhost:$SERVICE_PORT/health', timeout=10)
    print(r.read().decode())
except Exception as e:
    print('ERROR:' + str(e))
" || true)
fi

if echo "$HEALTH" | grep -q '"status":"ok"' 2>/dev/null || \
   echo "$HEALTH" | grep -q '"status": "ok"' 2>/dev/null; then
    ok "Health check passed: $HEALTH"
    log "Health check: $HEALTH"
else
    fail "Health check failed. Response: ${HEALTH:-none}. Check $INSTALL_DIR/print_server.log"
fi

log "SUCCESS: $(date)"


# ============================================================
# SUCCESS
# ============================================================

clear
echo ""
echo "================================================"
echo "  Installation Complete!"
echo "================================================"
echo ""
echo "  Installed to : $INSTALL_DIR"
echo "  Service name : $SERVICE_NAME"
echo "  Port         : $SERVICE_PORT"
echo "  Log file     : $INSTALL_DIR/print_server.log"
echo ""
echo "------------------------------------------------"
echo "  IMPORTANT — Printer setup reminder:"
echo "------------------------------------------------"
echo ""
echo "  Connect the Brother QL-810W via USB."
echo "  The Auto Power Off setting must be disabled"
echo "  on the printer firmware (one-time per printer)."
echo "  See LINUX-SETUP-CHECKLIST.md for instructions."
echo ""
echo "================================================"
echo ""
