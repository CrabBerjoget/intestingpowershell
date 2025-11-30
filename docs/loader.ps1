

# --- Step 0: Use AppID from caller ---
if (-not $AppID) {
    Write-Host "Error: AppID not provided."
    exit
}

Write-Host "Using AppID: $AppID"


# --- Step 1: Detect Steam Path ---
$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {
    Write-Host "Steam installation not found!"
    exit
}

# --- Step 2: Find appmanifest ---

Write-Host "Checking main Steam steamapps folder first..."

$appManifest = $null
$libraryFolders = @()

# 1. Main Steam folder
$mainSteamApps = Join-Path $steamPath "steamapps"
if (Test-Path $mainSteamApps) {
    $acf = Get-ChildItem -Path $mainSteamApps -Filter "appmanifest_$AppID.acf" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($acf) {
        $appManifest = $acf
    }
}

# 2. If not found → scan drives
if (-not $appManifest) {

    Write-Host "Not in main Steam folder. Scanning mounted drives..."

    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root

    foreach ($drive in $drives) {
        if (-not (Test-Path $drive)) { continue }

        # possible library roots
        $libs = @(
            (Join-Path $drive "SteamLibrary"),
            (Join-Path $drive "Steam")
        )

        foreach ($lib in $libs) {

            if (-not (Test-Path $lib)) { continue }

            $steamApps = Join-Path $lib "steamapps"

            # THIS is the real fix: ensure the steamapps folder EXISTS
            if (-not (Test-Path $steamApps)) { continue }

            $acf = Get-ChildItem -Path $steamApps -Filter "appmanifest_$AppID.acf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($acf) {
                $appManifest = $acf
                break
            }
        }

        if ($appManifest) { break }
    }
}

# final fail check
if (-not $appManifest) {
    Write-Host "AppID $AppID not found in any Steam library folder!"
    exit
}

Write-Host "Found manifest: $($appManifest.FullName)"


# --- Step 3: Parse installdir from appmanifest ---
$acfContent = Get-Content $appManifest.FullName
$installDirLine = $acfContent | Where-Object { $_ -match '"installdir"' }
$installDir = ($installDirLine -split '"')[3]

# --- Step 4: Build REAL game path from the library the manifest was found in ---
# appManifest is like: <LibraryRoot>\steamapps\appmanifest_123456.acf
$libraryRoot = Split-Path (Split-Path $appManifest.FullName -Parent) -Parent
$gamePath = Join-Path (Join-Path $libraryRoot "steamapps\common") $installDir

Write-Host "Detected game folder: $gamePath"

# --- Step 5: Get file list from GitHub branch ---

$branch     = $AppID
$repo1Owner = "3circledesign"
$repo1Name  = "intestingpowershell"

$repo2Owner = "CrabBerjoget"
$repo2Name  = "intestingpowershell"

function Get-GitHubFiles($owner, $name, $branch) {
    $url = "https://api.github.com/repos/$owner/$name/contents/?ref=$branch"
    try {
        return Invoke-RestMethod -Uri $url -UseBasicParsing -Headers @{ "User-Agent" = "PowerShell" }
    } catch {
        return $null
    }
}

Write-Host "Fetching source..."

$filesList = Get-GitHubFiles $repo1Owner $repo1Name $branch

if (-not $filesList) {
    Write-Host "Refetching source..."

    $filesList = Get-GitHubFiles $repo2Owner $repo2Name $branch

    if (-not $filesList) {
        Write-Host "ERROR: No Patch for $branch yet!"
        exit
    }
}

Write-Host "Patch Found."


# --- Step 6: Download all files (MULTI-THREADED) ---

$jobs = @()

foreach ($file in $filesList) {
    if ($file.type -eq "file") {

        $fileUrl  = $file.download_url
        $fileName = $file.name
        $dest     = Join-Path $gamePath $fileName

        Write-Host "Queued: $fileName"

        # Start a background job for each file
        $jobs += Start-Job -ScriptBlock {
            param($url, $out)

            try {
                Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
            } catch {
                Write-Host "Failed to download $($out)"
            }

        } -ArgumentList $fileUrl, $dest
    }
}

Write-Host "Downloading all files in parallel..."

# Wait for all jobs to finish
Wait-Job -Job $jobs | Out-Null

# Retrieve results (also clears finished jobs)
Receive-Job -Job $jobs | Out-Null
Remove-Job -Job $jobs | Out-Null

Write-Host "All downloads complete!"


# --- Step 7: Ensure UnRAR.exe is downloaded ---
$unrarPath = Join-Path $gamePath "UnRAR.exe"
if (-not (Test-Path $unrarPath)) {
    Write-Host "Downloading UnRAR.exe..."
    try {
        Invoke-WebRequest -Uri "https://github.com/CrabBerjoget/intestingpowershell/raw/main/UnRAR.exe" -OutFile $unrarPath
    } catch {
        Write-Host "Failed to download UnRAR.exe. RAR extraction will be skipped."
        $unrarPath = $null
    }
}

# --- Step 8: Extract RAR files silently to the same folder ---

$rarFiles = Get-ChildItem -Path $gamePath -Recurse -Filter *.rar
foreach ($rar in $rarFiles) {
if ($unrarPath -and (Test-Path $unrarPath)) {
$destination = $rar.DirectoryName  # Extract to same folder as RAR
Write-Host "Extracting $($rar.FullName) → $destination"
Start-Process -FilePath $unrarPath -ArgumentList "x `"$($rar.FullName)`" `"$destination`" -y -inul" -WindowStyle Hidden -Wait
Remove-Item $rar.FullName -Force
} else {
Write-Host "UnRAR.exe not found. Skipping $($rar.Name)"
}
}
Write-Host "RAR extraction complete!"



