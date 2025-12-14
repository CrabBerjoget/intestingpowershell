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
# Step 5: Fetch Steamless CLI (REPLACED)
# =====================================================
$RootDir = Join-Path $env:TEMP "Steamless"
$SteamlessDir = Join-Path $RootDir "Steamless_CLI"
$PluginsDir = Join-Path $SteamlessDir "Plugins"
$SteamlessCLI = Join-Path $SteamlessDir "Steamless.CLI.exe"

# Use the raw branch URL pointing to the actual files
$BaseRaw = "https://raw.githubusercontent.com/CrabBerjoget/intestingpowershell/Steamless/Steamless_CLI/main"

if (-not (Test-Path $SteamlessCLI)) {

    Write-Host "Downloading Steamless CLI..."

    # Ensure directories exist
    New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null

    # Core files
    $CoreFiles = @(
        "Steamless.CLI.exe",
        "Steamless.CLI.exe.config",
        "infos.txt"
    )

    foreach ($f in $CoreFiles) {
        $outPath = Join-Path $SteamlessDir $f
        Write-Host "Downloading $f..."
        Invoke-WebRequest -Uri "$BaseRaw/$f" -OutFile $outPath -UseBasicParsing
    }

    # Plugin DLLs
    $PluginFiles = @(
        "ExamplePlugin.dll",
        "SharpDisasm.dll",
        "Steamless.API.dll",
        "Steamless.Unpacker.Variant10.x86.dll",
        "Steamless.Unpacker.Variant20.x86.dll",
        "Steamless.Unpacker.Variant21.x86.dll",
        "Steamless.Unpacker.Variant30.x64.dll",
        "Steamless.Unpacker.Variant30.x86.dll",
        "Steamless.Unpacker.Variant31.x64.dll",
        "Steamless.Unpacker.Variant31.x86.dll"
    )

    foreach ($f in $PluginFiles) {
        $outPath = Join-Path $PluginsDir $f
        Write-Host "Downloading plugin $f..."
        Invoke-WebRequest -Uri "$BaseRaw/Plugins/$f" -OutFile $outPath -UseBasicParsing
    }
}

# Final check
if (-not (Test-Path $SteamlessCLI)) {
    Write-Host "Steamless CLI missing after download."
    exit
}

Write-Host "Steamless CLI ready at $SteamlessCLI"



# =====================================================
# Step 6: SKIPPED
# Step 7: SKIPPED
# =====================================================


# =====================================================
# Step 8: Steamless EXE processing (Python logic mapped)
# =====================================================
Write-Host "Scanning for EXE files..."

$exeFiles = Get-ChildItem -Path $gamePath -Recurse -File -Filter *.exe |
    Where-Object { $_.Name -notmatch '\.bak$' }

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
            -WorkingDirectory $SteamlessDir `
            -WindowStyle Hidden `
            -NoNewWindow `
            -Wait `
            -ErrorAction Stop
    }
    catch {
        Write-Host "[SKIP] Not packed or Steamless failed"
        continue
    }

    $unpacked = "$($exe.FullName).unpacked.exe"

    if (Test-Path $unpacked) {
        try {
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
