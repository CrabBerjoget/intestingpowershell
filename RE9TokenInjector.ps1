# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "WARNING: You are not running PowerShell as an Administrator!" -ForegroundColor Red
    Write-Host "Please close this window, right-click the script or PowerShell, and select 'Run as Administrator'." -ForegroundColor Yellow
    Pause
    exit
}

# Hardcoded AppID for RE9
$AppID = "3764200"

# Ask user for the new token
$newToken = Read-Host "Please paste your new token"

# --- Step 1: Detect Steam Path ---
Write-Host "Detecting Steam installation path..."
$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {
    Write-Host "Steam installation not found!" -ForegroundColor Red
    Pause
    exit
}
Write-Host "Steam found at: $steamPath" -ForegroundColor Green

# --- Target library search including alternate libraries ---
$libraryFoldersFile = Join-Path $steamPath "steamapps\libraryfolders.vdf"
$searchPaths = @("$steamPath\steamapps")

if (Test-Path $libraryFoldersFile) {
    $vdfContent = Get-Content $libraryFoldersFile
    $paths = $vdfContent | Select-String -Pattern '"path"\s+"([^"]+)"'
    foreach ($match in $paths.Matches) {
        $libPath = $match.Groups[1].Value.Replace("\\", "\")
        # Only add to search paths if the drive/path actually exists
        if (Test-Path $libPath) {
            $steamAppsPath = Join-Path $libPath "steamapps"
            if ($searchPaths -notcontains $steamAppsPath) {
                $searchPaths += $steamAppsPath
            }
        }
    }
}

# --- Step 2: Find appmanifest for the AppID ---
Write-Host "Searching for AppID $AppID in Steam libraries..."
$appManifest = $null
foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        $manifestPath = Join-Path $path "appmanifest_$AppID.acf"
        if (Test-Path $manifestPath) {
            $appManifest = Get-Item $manifestPath
            break
        }
    }
}

if (-not $appManifest) {
    Write-Host "AppID $AppID not found in Steam libraries!" -ForegroundColor Red
    Pause
    exit
}

# Determine actual game installation directory
$manifestContent = Get-Content $appManifest.FullName
$installDirLine = $manifestContent | Select-String -Pattern '"installdir"\s+"([^"]+)"'
if ($installDirLine) {
    $installDirName = $installDirLine.Matches[0].Groups[1].Value
}
else {
    $installDirName = $AppID
}

$gameFolder = Join-Path $appManifest.Directory.FullName "common\$installDirName"
if (-not (Test-Path $gameFolder)) {
    Write-Host "Game folder not found: $gameFolder" -ForegroundColor Red
    Pause
    exit
}
Write-Host "Found Game Folder: $gameFolder" -ForegroundColor Green

# --- Step 3: Download required files ---
$tempDir = Join-Path $env:TEMP "RE9Patch"
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Converting blob URLs from GitHub to raw download URLs
$unrarUrl = "https://github.com/CrabBerjoget/intestingpowershell/raw/RE9_GBE/UnRAR.exe"
$part1Url = "https://github.com/CrabBerjoget/intestingpowershell/raw/RE9_GBE/PatchFile.part1.rar"
$part2Url = "https://github.com/CrabBerjoget/intestingpowershell/raw/RE9_GBE/PatchFile.part2.rar"

$unrarPath = Join-Path $tempDir "UnRAR.exe"
$part1Path = Join-Path $tempDir "PatchFile.part1.rar"
$part2Path = Join-Path $tempDir "PatchFile.part2.rar"

Write-Host "Downloading UnRAR.exe..."
Invoke-WebRequest -Uri $unrarUrl -OutFile $unrarPath

Write-Host "Downloading PatchFile.part1.rar..."
Invoke-WebRequest -Uri $part1Url -OutFile $part1Path

Write-Host "Downloading PatchFile.part2.rar..."
Invoke-WebRequest -Uri $part2Url -OutFile $part2Path

# --- Step 4: Extract files to game folder using UnRAR ---
Write-Host "Extracting files to $gameFolder..."
# 'x' for extract with full paths, '-y' to assume yes on queries, '-o+' to overwrite existing files
# For multi-part rar files, pointing UnRAR to part1 automatically extracts the rest
$unrarArgs = @("x", "-y", "-o+", $part1Path, "$gameFolder\")
$unrarProcess = Start-Process -FilePath $unrarPath -ArgumentList $unrarArgs -Wait -NoNewWindow -PassThru

if ($unrarProcess.ExitCode -ne 0) {
    Write-Host "Extraction might have completed with warnings or failed. (Exit code: $($unrarProcess.ExitCode))" -ForegroundColor Yellow
}
else {
    Write-Host "Extraction successful!" -ForegroundColor Green
}

# --- Step 5: Edit the configs.user.ini file ---
$iniPath = Join-Path $gameFolder "steam_settings\configs.user.ini"
if (Test-Path $iniPath) {
    Write-Host "Updating token in configs.user.ini..."
    $iniContent = Get-Content $iniPath -Raw
    
    # Replace the target literal strings with the token provided by the user
    $iniContent = $iniContent.Replace("account_steamid=76561199077633888", "account_steamid=$newToken")
    $iniContent = $iniContent.Replace("ticket={change_here}", "ticket=$newToken")
    
    Set-Content -Path $iniPath -Value $iniContent -Encoding UTF8
    Write-Host "Successfully replaced the tokens!" -ForegroundColor Green
}
else {
    Write-Host "Warning: $iniPath not found. Extraction may have failed or the expected file is missing." -ForegroundColor Yellow
}

Write-Host "All tasks completed!" -ForegroundColor Cyan
Pause
