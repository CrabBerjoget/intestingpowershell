# URL to mapping JSON
$mapUrl = "https://CrabBerjoget.github.io/ps-patches/index.json"
$map = irm $mapUrl

# Get the patch ID from argument
if ($args.Count -eq 0) {
    Write-Host "Usage: loader.ps1 <patchID>"
    exit
}

$patchID = $args[0]

if (-not $map.$patchID) {
    Write-Host "Patch ID '$patchID' not found."
    exit
}

# Download and run the patch
irm $map.$patchID | iex
