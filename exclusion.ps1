cls
# ================== AUTO ADMIN ELEVATION (FIXED) ==================
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    $scriptPath = $MyInvocation.MyCommand.Path

    if (-not $scriptPath) {
        Write-Host "Cannot self-elevate. Please run as Administrator." -ForegroundColor Red
        pause
        exit
    }

    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -Verb RunAs

    exit
}

[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# ================== UI HELPERS ==================
function Show-Header($title) {
    $line = "═" * ($title.Length + 4)
    Write-Host "╔$line╗" -ForegroundColor Cyan
    Write-Host "║  $title  ║" -ForegroundColor Cyan
    Write-Host "╚$line╝" -ForegroundColor Cyan
}
function Info($m){ Write-Host "[INFO] $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "[OK]   $m" -ForegroundColor Green }
function Err($m){ Write-Host "[ERR]  $m" -ForegroundColor Red }

# ================== ADMIN CHECK ==================
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Err "Please run this script as Administrator."
    pause
    exit
}

Show-Header "Steam Defender Exclusion Tool"

# =====================================================
# Step 1: Detect Steam Path
# =====================================================
$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath

if (-not $steamPath) {
    $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
}

if (-not $steamPath) {
    Err "Steam installation not found!"
    exit
}

Info "Steam detected at: $steamPath"

# ================== ADD DEFENDER EXCLUSION ==================
try {
    Add-MpPreference -ExclusionPath $steamPath
    Ok "Steam folder added to Windows Defender exclusions."
} catch {
    Err "Failed to add exclusion."
    Err "Make sure Tamper Protection is OFF."
    exit
}

# ================== VERIFY ==================
Show-Header "Current Defender Exclusions"
(Get-MpPreference).ExclusionPath | ForEach-Object {
    Write-Host " - $_" -ForegroundColor Cyan
}

Ok "Happy Gaming!"
pause
