# loader.ps1 — download branch files and auto-unrar

# --- Step 0: Get PatchID ---

if (-not $env:PATCHID) {
Write-Host "Please set environment variable PATCHID"
exit
}
$AppID = $env:PATCHID
Write-Host "Running patch $AppID"

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

$appManifest = Get-ChildItem "$steamPath\steamapps" -Filter "appmanifest_$AppID.acf" -Recurse | Select-Object -First 1
if (-not $appManifest) {
Write-Host "AppID $AppID not found in Steam library!"
exit
}

# --- Step 3: Parse installdir ---

$acfContent = Get-Content $appManifest.FullName
$installDirLine = $acfContent | Where-Object { $_ -match '"installdir"' }
$installDir = ($installDirLine -split '"')[3]

# --- Step 4: Build full path ---

$gamePath = Join-Path (Join-Path $steamPath "steamapps\common") $installDir
Write-Host "Detected game folder: $gamePath"

# --- Step 5: Get file list from GitHub branch ---

$repoOwner = "CrabBerjoget"
$repoName = "intestingpowershell"
$branch = $AppID
$apiUrl = "[https://api.github.com/repos/$repoOwner/$repoName/contents/?ref=$branch](https://api.github.com/repos/$repoOwner/$repoName/contents/?ref=$branch)"

try {
$filesList = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -Headers @{ "User-Agent" = "PowerShell" }
} catch {
Write-Host "Failed to fetch file list from GitHub branch $branch"
exit
}

# --- Step 6: Download all files ---

$rarDetected = $false
foreach ($file in $filesList) {
if ($file.type -eq "file") {
$fileUrl = $file.download_url
$fileName = $file.name
$destination = Join-Path $gamePath $fileName
Write-Host "Downloading $fileName → $destination"
try {
Invoke-WebRequest $fileUrl -OutFile $destination
if ($fileName -like "*.rar") { $rarDetected = $true }
} catch {
Write-Host "Failed to download $fileName"
}
}
}

# --- Step 7: Extract RAR files if any ---

if ($rarDetected) {
if (Get-Command "UnRAR.exe" -ErrorAction SilentlyContinue) {
Write-Host "RAR files detected. Proceeding with UnRAR..."
$rarFiles = Get-ChildItem -Path $gamePath -Recurse -Filter *.rar
foreach ($rar in $rarFiles) {
Write-Host "Extracting $($rar.FullName)"
Start-Process "UnRAR.exe" -ArgumentList "x `"$($rar.FullName)`" `"$gamePath`" -y" -Wait
Remove-Item $rar.FullName -Force
}
} else {
Write-Host "UnRAR.exe not found. Skipping RAR extraction."
}
}

Write-Host "Patch complete!"
