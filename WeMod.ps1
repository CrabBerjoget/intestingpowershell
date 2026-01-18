if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    Start-Process powershell `
        -ArgumentList "-STA -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

cls
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# ================== Helper Functions ==================
function Show-Header($title) {
    $line = "═" * ($title.Length + 4)
    Write-Host "╔$line╗" -ForegroundColor Cyan
    Write-Host "║  $title  ║" -ForegroundColor Cyan
    Write-Host "╚$line╝" -ForegroundColor Cyan
}
function Show-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Yellow }
function Show-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Show-Error($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ================== TEMP DOWNLOAD FOLDER ==================
$downloadPath = Join-Path $env:TEMP "WeModPro"
if (-not (Test-Path $downloadPath)) {
    New-Item -ItemType Directory -Path $downloadPath | Out-Null
}
Show-Header "WeMod Downloader"
Show-Info "Temp folder: $downloadPath"

# ================== GITHUB SOURCE ==================
$repoOwner = "CrabBerjoget"
$repoName  = "intestingpowershell"
$branch    = "WeModPro"

function Get-GitHubFiles {
    param($owner, $repo, $branch)
    $url = "https://api.github.com/repos/$owner/$repo/contents/?ref=$branch"
    try {
        Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "PowerShell" }
    } catch {
        return $null
    }
}

Show-Header "Fetching Source"
$filesList = Get-GitHubFiles $repoOwner $repoName $branch
if (-not $filesList) {
    Show-Error "Failed to fetch WeMod files."
    exit
}
Show-Success "Source found."

# ================== DOWNLOAD FILES ==================
Show-Header "Downloading Files"
foreach ($file in $filesList) {
    if ($file.type -ne "file") { continue }

    $dest = Join-Path $downloadPath $file.name
    Show-Info "Downloading $($file.name)"
    Invoke-WebRequest -Uri $file.download_url -OutFile $dest -UseBasicParsing *> $null
}
Show-Success "All files downloaded."

# ================== ENSURE UNRAR ==================
$unrarPath = Join-Path $downloadPath "UnRAR.exe"
if (-not (Test-Path $unrarPath)) {
    Show-Info "Downloading UnRAR.exe"
    Invoke-WebRequest `
        -Uri "https://github.com/CrabBerjoget/intestingpowershell/raw/main/UnRAR.exe" `
        -OutFile $unrarPath *> $null
}

# ================== ASK EXTRACTION LOCATION ==================
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "Select where to extract WeMod"
$dialog.ShowNewFolderButton = $true

if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Show-Error "No extraction folder selected."
    exit
}
$extractPath = $dialog.SelectedPath
Show-Success "Extracting to: $extractPath"

# ================== EXTRACT WeMod ==================
Show-Header "Extracting WeMod"

$firstRar = Join-Path $downloadPath "WeMod.part1.rar"
if (-not (Test-Path $firstRar)) {
    Show-Error "WeMod.part1.rar not found!"
    exit
}

Start-Process -FilePath $unrarPath `
    -ArgumentList "x `"$firstRar`" `"$extractPath`" -y -inul" `
    -WindowStyle Hidden -Wait *> $null

Remove-Item "$downloadPath\WeMod.part*.rar" -Force
Show-Success "Extraction complete."

# ================== OPEN FOLDER ==================
Start-Process $extractPath

# ================== FINISH ==================
Show-Success "Happy Gaming!"
