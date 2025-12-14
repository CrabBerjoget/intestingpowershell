# =====================================================
# Step 0: Use AppID from caller
# =====================================================
if (-not $AppID) {
    Write-Host "Error: AppID not provided."
    exit
}

$AppID = $AppID.ToString().Trim()
Write-Host "Using AppID: $AppID"


# =====================================================
# Step 1: Detect Steam Path (REUSED)
# =====================================================
$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {
    Write-Host "Steam installation not found!"
    exit
}


# =====================================================
# Step 2: Find appmanifest (REUSED)
# =====================================================
Write-Host "Checking main Steam steamapps folder first..."

$appManifest = $null

$mainSteamApps = Join-Path $steamPath "steamapps"
if (Test-Path $mainSteamApps) {
    $acf = Get-ChildItem -Path $mainSteamApps -Filter "appmanifest_$AppID.acf" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($acf) { $appManifest = $acf }
}

if (-not $appManifest) {
    Write-Host "Not in main Steam folder. Scanning mounted drives..."

    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root

    foreach ($drive in $drives) {
        $libs = @(
            (Join-Path $drive "SteamLibrary"),
            (Join-Path $drive "Steam")
        )

        foreach ($lib in $libs) {
            $steamApps = Join-Path $lib "steamapps"
            if (-not (Test-Path $steamApps)) { continue }

            $acf = Get-ChildItem -Path $steamApps -Filter "appmanifest_$AppID.acf" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($acf) {
                $appManifest = $acf
                break
            }
        }

        if ($appManifest) { break }
    }
}

if (-not $appManifest) {
    Write-Host "AppID $AppID not found in any Steam library folder!"
    exit
}

Write-Host "Found manifest: $($appManifest.FullName)"


# =====================================================
# Step 3: Parse installdir (REUSED)
# =====================================================
$acfContent = Get-Content $appManifest.FullName
$installDirLine = $acfContent | Where-Object { $_ -match '"installdir"' }
$installDir = ($installDirLine -split '"')[3]

if (-not $installDir) {
    Write-Host "Failed to read installdir from manifest."
    exit
}


# =====================================================
# Step 4: Build REAL game path (REUSED)
# =====================================================
$libraryRoot = Split-Path (Split-Path $appManifest.FullName -Parent) -Parent
$gamePath = Join-Path (Join-Path $libraryRoot "steamapps\common") $installDir

if (-not (Test-Path $gamePath)) {
    Write-Host "Game folder not found: $gamePath"
    exit
}

Write-Host "Detected game folder:"
Write-Host " $gamePath"


# =====================================================
# Step 5: Download Steamless RAR
# =====================================================
$steamlessRar = Join-Path $env:TEMP "Steamless_CLI.rar"
$steamlessRarUrl = "https://github.com/CrabBerjoget/intestingpowershell/raw/Steamless/Steamless_CLI.rar"

if (-not (Test-Path $steamlessRar)) {
    Write-Host "Downloading Steamless_CLI.rar..."
    try {
        Invoke-WebRequest -Uri $steamlessRarUrl -OutFile $steamlessRar -UseBasicParsing
    } catch {
        Write-Host "Failed to download Steamless_CLI.rar!"
        exit
    }
}

# =====================================================
# Step 6: Ensure UnRAR.exe is ready (reuse your code)
# =====================================================
$unrarPath = Join-Path $gamePath "UnRAR.exe"
if (-not (Test-Path $unrarPath)) {
    Write-Host "Downloading UnRAR.exe..."
    try {
        Invoke-WebRequest -Uri "https://github.com/CrabBerjoget/intestingpowershell/raw/main/UnRAR.exe" -OutFile $unrarPath
    } catch {
        Write-Host "Failed to download UnRAR.exe. Extraction will be skipped."
        $unrarPath = $null
    }
}

# =====================================================
# Step 7: Extract Steamless into the game folder
# =====================================================
if ($unrarPath -and (Test-Path $unrarPath)) {
    Write-Host "Extracting Steamless to game folder..."
    try {
        Start-Process -FilePath $unrarPath `
            -ArgumentList "x `"$steamlessRar`" `"$gamePath`" -y -inul" `
            -WindowStyle Hidden `
            -Wait
        Remove-Item $steamlessRar -Force
        Write-Host "Steamless ready in game folder: $gamePath"
    } catch {
        Write-Host "Failed to extract Steamless!"
        exit
    }
} else {
    Write-Host "UnRAR.exe not available. Cannot extract Steamless."
    exit
}

# =====================================================
# Step 8: Steamless EXE processing (fixed & exclude CLI/UnRAR)
# =====================================================

# Steamless CLI path after extraction
$SteamlessCLI = Join-Path $gamePath "Steamless_CLI\Steamless.CLI.exe"
$WorkingDir = Split-Path $SteamlessCLI -Parent

if (-not (Test-Path $SteamlessCLI)) {
    Write-Host "Steamless CLI not found in game folder!"
    exit
}

Write-Host "Scanning for EXE files..."

$exeFiles = Get-ChildItem -Path $gamePath -Recurse -File -Filter *.exe |
    Where-Object { $_.Name -notmatch '\.bak$' -and $_.Name -notin @("Steamless.CLI.exe","UnRAR.exe") }

if (-not $exeFiles) {
    Write-Host "[INFO] No .exe files found."
    exit
}

Write-Host "[INFO] Found $($exeFiles.Count) .exe file(s). Processing..."

foreach ($exe in $exeFiles) {

    Write-Host "[PROCESS] $($exe.Name)"

    try {
        Start-Process `
            -FilePath $SteamlessCLI `
            -ArgumentList "`"$($exe.FullName)`"" `
            -WorkingDirectory $WorkingDir `
            -WindowStyle Hidden `
            -NoNewWindow `
            -Wait `
            -ErrorAction Stop
    }
    catch {
        Write-Host "[SKIP] Not packed or Steamless failed: $($exe.Name)"
        continue
    }

    # Check for .unpacked.exe
    $unpacked = "$($exe.FullName).unpacked.exe"

    if (Test-Path $unpacked) {
        try {
            # Backup original and replace with unpacked
            Move-Item $exe.FullName "$($exe.FullName).BAK" -Force
            Move-Item $unpacked $exe.FullName -Force
            Write-Host "[SUCCESS] Replaced with unpacked: $($exe.Name)"
        }
        catch {
            Write-Host "[ERROR] Failed to replace: $($exe.Name)"
        }
    }
    else {
        Write-Host "[FAIL] No unpacked output for: $($exe.Name)"
    }
}

Write-Host "[DONE] All files processed."
Write-Host "Happy Gaming!"

Write-Host "Happy Gaming!"
