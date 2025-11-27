Write-Host "Your remote script is running!"
Write-Host "This is coming from GitHub RAW."

# test.ps1 — download all files from GitHub branch matching AppID

param(
[string]$AppID = $env:PATCHID  # fallback if using environment variable
)

if (-not $AppID) {
Write-Host "Please provide AppID as parameter or set $env:PATCHID"
exit
}

# --- Step 1: Detect Steam Path ---

$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) {
$steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {
Write-Host "Steam installation not found!"
exit
}

# --- Step 2: Find appmanifest for the AppID ---

$appManifest = Get-ChildItem "$steamPath\steamapps" -Filter "appmanifest_$AppID.acf" -Recurse | Select-Object -First 1
if (-not $appManifest) {
Write-Host "AppID $AppID not found in Steam library!"
exit
}

# --- Step 3: Parse installdir from appmanifest ---

$acfContent = Get-Content $appManifest.FullName
$installDirLine = $acfContent | Where-Object { $_ -match '"installdir"' }
$installDir = ($installDirLine -split '"')[3]

# --- Step 4: Build full path to game ---

$gamePath = Join-Path (Join-Path $steamPath "steamapps\common") $installDir
Write-Host "Detected game folder: $gamePath"

# --- Step 5: Get file list from GitHub branch using API ---

$repoOwner = "CrabBerjoget"
$repoName = "intestingpowershell"
$branch = $AppID

$apiUrl = "[https://api.github.com/repos/$repoOwner/$repoName/contents/?ref=$branch](https://api.github.com/repos/$repoOwner/$repoName/contents/?ref=$branch)"
try {
$filesList = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
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
