

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

# --- Step 2: Find appmanifest by scanning drives instead of parsing VDF ---

Write-Host "Scanning drives A-Z for Steam libraries..."

$libraryFolders = @()

# Add main Steam path from registry
$libraryFolders += $steamPath

# Scan all drives for SteamLibrary folders
foreach ($letter in 'A'..'Z') {
    $drive = "$letter:\"
    if (Test-Path $drive) {

        # Typical Steam library folder
        $lib1 = Join-Path $drive "SteamLibrary"
        $lib2 = Join-Path $drive "steamLibrary"
        $lib3 = Join-Path $drive "STEAMLIBRARY"

        foreach ($lib in @($lib1, $lib2, $lib3)) {
            if (Test-Path $lib) {
                $libraryFolders += $lib
            }
        }

        # Some users install Steam directly on a different drive (D:\Steam)
        $steamLike = Join-Path $drive "Steam"
        if (Test-Path $steamLike) {
            $libraryFolders += $steamLike
        }
    }
}

# Remove duplicates
$libraryFolders = $libraryFolders | Select-Object -Unique

Write-Host "Detected Steam Libraries:"
$libraryFolders | ForEach-Object { Write-Host " - $_" }

# Search for appmanifest in detected library folders
$appManifest = $null
foreach ($folder in $libraryFolders) {
    $steamApps = Join-Path $folder "steamapps"
    if (Test-Path $steamApps) {
        $acf = Get-ChildItem -Path $steamApps -Filter "appmanifest_$AppID.acf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($acf) {
            $appManifest = $acf
            break
        }
    }
}

if (-not $appManifest) {
    Write-Host "AppID $AppID not found in any Steam library folder!"
    exit
}


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
$repoOwner = "CrabBerjoget"
$repoName = "intestingpowershell"
$branch = $AppID
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/contents/?ref=$branch"

try {
    $filesList = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -Headers @{ "User-Agent" = "PowerShell" }
} catch {
    Write-Host "Failed to fetch file list from GitHub branch $branch"
    exit
}

# --- Step 6: Download all files ---
foreach ($file in $filesList) {
    if ($file.type -eq "file") {
        $fileUrl = $file.download_url
        $fileName = $file.name
        $destination = Join-Path $gamePath $fileName
        Write-Host "Downloading $fileName → $destination"
        try {
            Invoke-WebRequest $fileUrl -OutFile $destination
        } catch {
            Write-Host "Failed to download $fileName"
        }
    }
}

Write-Host "Patch complete!"

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



