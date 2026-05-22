# install.ps1
# VMS Print Service Installer
# Run as Administrator from the installer folder

$ErrorActionPreference = "Stop"

$SERVICE_NAME = "BrotherPrintServer"
$INSTALL_DIR  = "C:\VMS\PrintService"
$SERVICE_USER = "VMS"
$SERVICE_PORT = "5050"
$SCRIPT_DIR   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DIST_DIR     = Join-Path (Split-Path -Parent $SCRIPT_DIR) "dist"

function Write-Step($msg) {
    Write-Host ""
    Write-Host ">>> $msg" -ForegroundColor Cyan
}

function Write-OK($msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Fail($msg) {
    Write-Host "    [FAIL] $msg" -ForegroundColor Red
    exit 1
}

# Check Administrator
Write-Step "Checking administrator privileges..."
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-NOT $isAdmin) {
    Write-Fail "Must be run as Administrator."
}
Write-OK "Running as Administrator."

# Stop and remove existing service
Write-Step "Checking for existing service..."
$existing = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "    Found existing service. Removing..." -ForegroundColor Yellow
    & "$SCRIPT_DIR\nssm.exe" stop $SERVICE_NAME 2>$null
    Start-Sleep 2
    Get-Process -Name "print_server" -ErrorAction SilentlyContinue | Stop-Process -Force
    & "$SCRIPT_DIR\nssm.exe" remove $SERVICE_NAME confirm
    Start-Sleep 2
    Write-OK "Existing service removed."
} else {
    Write-OK "No existing service found."
}

# Install bPAC
Write-Step "Installing Brother bPAC Client Component..."
$msi = Join-Path $SCRIPT_DIR "bcciw32001.msi"
if (-NOT (Test-Path $msi)) {
    Write-Fail "bPAC MSI not found at: $msi"
}
$msiResult = Start-Process "msiexec.exe" -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait -PassThru
if ($msiResult.ExitCode -ne 0 -and $msiResult.ExitCode -ne 1603) {
    Write-Fail "bPAC installation failed. Exit code: $($msiResult.ExitCode)"
}
Write-OK "bPAC Client Component installed."

# Create install directory
Write-Step "Creating install directory..."
if (-NOT (Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
}
Write-OK "Directory ready: $INSTALL_DIR"

# Copy files
Write-Step "Copying service files..."
$exe = Join-Path $DIST_DIR "print_server.exe"
if (-NOT (Test-Path $exe)) {
    Write-Fail "print_server.exe not found at: $exe"
}
Copy-Item $exe $INSTALL_DIR -Force
Write-OK "Copied print_server.exe"

$lbx = Join-Path $DIST_DIR "QL-visitor-custom.lbx"
if (-NOT (Test-Path $lbx)) {
    Write-Fail "QL-visitor-custom.lbx not found at: $lbx"
}
Copy-Item $lbx $INSTALL_DIR -Force
Write-OK "Copied QL-visitor-custom.lbx"

# Register service
Write-Step "Registering Windows Service..."
$exeTarget = Join-Path $INSTALL_DIR "print_server.exe"
& "$SCRIPT_DIR\nssm.exe" install $SERVICE_NAME $exeTarget
& "$SCRIPT_DIR\nssm.exe" set $SERVICE_NAME AppDirectory $INSTALL_DIR
& "$SCRIPT_DIR\nssm.exe" set $SERVICE_NAME AppStdout "$INSTALL_DIR\print_server.log"
& "$SCRIPT_DIR\nssm.exe" set $SERVICE_NAME AppStderr "$INSTALL_DIR\print_server.log"
& "$SCRIPT_DIR\nssm.exe" set $SERVICE_NAME AppRestartDelay 3000
& "$SCRIPT_DIR\nssm.exe" set $SERVICE_NAME Start SERVICE_AUTO_START
& "$SCRIPT_DIR\nssm.exe" set $SERVICE_NAME ObjectName ".\$SERVICE_USER" ""
Write-OK "Service registered."

# Start service
Write-Step "Starting service..."
& "$SCRIPT_DIR\nssm.exe" start $SERVICE_NAME
Start-Sleep 5

# Verify
Write-Step "Verifying service health..."
$svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
if (-NOT $svc -or $svc.Status -ne "Running") {
    Write-Fail "Service is not running. Check $INSTALL_DIR\print_server.log"
}

try {
    $response = Invoke-WebRequest -UseBasicParsing "http://localhost:$SERVICE_PORT/health" -TimeoutSec 10
    $json = $response.Content | ConvertFrom-Json
    if ($json.status -eq "ok") {
        Write-OK "Health check passed: $($response.Content)"
    } else {
        Write-Fail "Unexpected health response: $($response.Content)"
    }
} catch {
    Write-Fail "Health check failed. Check $INSTALL_DIR\print_server.log"
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  VMS Print Service installed successfully." -ForegroundColor Green
Write-Host "  Installed to : $INSTALL_DIR" -ForegroundColor Green
Write-Host "  Service name : $SERVICE_NAME" -ForegroundColor Green
Write-Host "  Port         : $SERVICE_PORT" -ForegroundColor Green
Write-Host "  Log file     : $INSTALL_DIR\print_server.log" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""