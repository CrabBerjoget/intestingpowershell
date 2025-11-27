# loader.ps1 — fully automatic, uses env PATCHID, downloads branch and auto-unrars RAR files

# --- Step 0: Get PatchID ---

if (-not $env:PATCHID) {
Write-Host "Please set environment variable PATCHID"
exit
}
$AppID = $env:PATCHID
Write-Host "Running patch $AppID"

# --- Step 1: Detect Steam Path ---

$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) { $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath }
if (-not $steamPath) { Write-Host "Steam not found"; exit }

# --- Step 2: Find appmanifest ---

$appManifest = Get-ChildItem "$steamPath\steamapps" -Filter "appmanifest_$AppID.acf" -Recurse | Select-Object -First 1
if (-not $appManifest) { Write-Host "AppID not found"; exit }

# --- Step 3: Get game folder ---

$acfContent = Get-Content $appManifest.FullName
$installDirLine = $acfContent | Where-Object { $_ -match '"installdir"' }
$installDir = ($installDirLine -split '"')[3]
$gamePath = Join-Path "$steamPath\steamapps\common" $installDir
Write-Host "Detected game folder: $gamePath"

# --- Step 4: Download branch as ZIP ---

$zipUrl = "[https://github.com/CrabBerjoget/intestingpowershell/archive/refs/heads/$AppID.zip](https://github.com/CrabBerjoget/intestingpowershell/archive/refs/heads/$AppID.zip)"
$tempZip = Join-Path $env:TEMP "$AppID.zip"

Write-Host "Downloading branch ZIP..."
try {
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip
} catch {
Write-Host "Failed to download ZIP for branch $AppID"
exit
}

# --- Step 5: Extract ZIP to temp folder and move contents ---

$tempExtract = Join-Path $env:TEMP "$AppID-extract"
try {
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)
Remove-Item $tempZip -Force

```
# Move contents from inner folder to game folder
$innerFolder = Join-Path $tempExtract "intestingpowershell-$AppID"
Get-ChildItem $innerFolder -Recurse | ForEach-Object {
    $targetPath = $_.FullName.Replace($innerFolder, $gamePath)
    if ($_.PSIsContainer) {
        if (-not (Test-Path $targetPath)) { New-Item -ItemType Directory -Path $targetPath | Out-Null }
    } else {
        Copy-Item $_.FullName -Destination $targetPath -Force
    }
}
Remove-Item $tempExtract -Recurse -Force
```

} catch {
Write-Host "Failed to extract ZIP"
exit
}

# --- Step 6: Extract any RAR files inside ---

# Ensure UnRAR.exe is downloaded to the game folder

$unrarPath = Join-Path $gamePath "UnRAR.exe"
if (-not (Test-Path $unrarPath)) {
Write-Host "Downloading UnRAR.exe..."
try {
Invoke-WebRequest -Uri "[https://www.rarlab.com/rar/unrarw32.exe](https://www.rarlab.com/rar/unrarw32.exe)" -OutFile $unrarPath
} catch {
Write-Host "Failed to download UnRAR.exe. RAR extraction will be skipped."
$unrarPath = $null
}
}

$rarFiles = Get-ChildItem -Path $gamePath -Recurse -Filter *.rar
foreach ($rar in $rarFiles) {
if ($unrarPath -and (Test-Path $unrarPath)) {
Write-Host "Extracting $($rar.FullName)"
Start-Process $unrarPath -ArgumentList "x `"$($rar.FullName)`" `"$gamePath`" -y" -Wait
Remove-Item $rar.FullName -Force
} else {
Write-Host "UnRAR.exe not found. Skipping $($rar.Name)"
}
}

Write-Host "Patch complete!"
