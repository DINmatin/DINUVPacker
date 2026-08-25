param(
    [string]$Version = '0.4.2'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$releaseName = "DINUVPacker-$Version-Max2016-win64"
$distRoot = Join-Path $projectRoot 'dist'
$stageRoot = Join-Path $distRoot $releaseName
$payloadRoot = Join-Path $stageRoot 'payload'
$iconPayloadRoot = Join-Path $payloadRoot 'icons'
$zipPath = Join-Path $distRoot "$releaseName.zip"

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $iconPayloadRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'installer\Install.cmd') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'installer\Install-DINUVPacker.ps1') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'installer\README.txt') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\icons\DINUVPacker.ico') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'maxscript\DIN_UV_xatlasPack.mcr') -Destination $payloadRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'bin\DINUVPacker.exe') -Destination $payloadRoot

@('DINUVPacker_16i.bmp', 'DINUVPacker_16a.bmp', 'DINUVPacker_24i.bmp', 'DINUVPacker_24a.bmp') | ForEach-Object {
    Copy-Item -LiteralPath (Join-Path $projectRoot "assets\icons\$_") -Destination $iconPayloadRoot
}

Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal
Get-Item -LiteralPath $zipPath | Select-Object FullName, Length, LastWriteTime
