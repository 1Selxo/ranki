# Script to install customized anki.koplugin to Kindle KOReader
$pluginSrc = "C:\Users\basel\.gemini\antigravity\scratch\anki.koplugin"

# Find Kindle Drive
$kindleDrive = $null
foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
    $root = $drive.Root
    if ((Test-Path "$root\koreader") -or (Test-Path "$root\anki_data")) {
        $kindleDrive = $root
        break
    }
}

if (-not $kindleDrive) {
    Write-Host "Kindle not detected. Please plug in your Kindle via USB." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found Kindle at: $kindleDrive" -ForegroundColor Green
$targetDir = "$kindleDrive\koreader\plugins\anki.koplugin"

if (-not (Test-Path $targetDir)) {
    Write-Host "Creating $targetDir..."
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Copying plugin files to $targetDir..."
Copy-Item -Path "$pluginSrc\*" -Destination $targetDir -Recurse -Force -Exclude ".git",".github","temp_*","test_*"

Write-Host "Verification:"
$copiedFiles = Get-ChildItem -Path $targetDir -Recurse
Write-Host "Total files deployed: $($copiedFiles.Count)" -ForegroundColor Green

if (Test-Path "$targetDir\ranki_local.lua") {
    Write-Host "ranki_local.lua successfully installed!" -ForegroundColor Green
} else {
    Write-Host "Warning: ranki_local.lua missing in target!" -ForegroundColor Red
}

if (Test-Path "$targetDir\profiles\default.lua") {
    Write-Host "Default Mining profile installed!" -ForegroundColor Green
}
