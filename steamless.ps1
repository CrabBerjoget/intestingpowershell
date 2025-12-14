# =========================
# Steamless bootstrap
# =========================

$RootDir = Join-Path $env:TEMP "Steamless"
$SteamlessDir = Join-Path $RootDir "Steamless_CLI"
$PluginsDir = Join-Path $SteamlessDir "Plugins"
$SteamlessCLI = Join-Path $SteamlessDir "Steamless.CLI.exe"

$BaseRaw = "https://raw.githubusercontent.com/CrabBerjoget/intestingpowershell/Steamless/Steamless_CLI"

if (-not (Test-Path $SteamlessCLI)) {
    Write-Host "[INFO] Downloading Steamless_CLI..."

    New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null

    # Core files
    $CoreFiles = @(
        "Steamless.CLI.exe",
        "Steamless.CLI.exe.config",
        "infos.txt"
    )

    foreach ($File in $CoreFiles) {
        Invoke-WebRequest `
            -Uri "$BaseRaw/$File" `
            -OutFile (Join-Path $SteamlessDir $File) `
            -UseBasicParsing
    }

    # Plugin files
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

    foreach ($File in $PluginFiles) {
        Invoke-WebRequest `
            -Uri "$BaseRaw/Plugins/$File" `
            -OutFile (Join-Path $PluginsDir $File) `
            -UseBasicParsing
    }
}

# Final safety check
if (-not (Test-Path $SteamlessCLI)) {
    Write-Host "[ERROR] Steamless bootstrap failed."
    exit 1
}
