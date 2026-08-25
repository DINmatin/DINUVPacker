[CmdletBinding()]
param(
    [string]$ProfileRoot
)

$ErrorActionPreference = 'Stop'
$packageRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'payload') -PathType Container) {
    $PSScriptRoot
} else {
    Split-Path -Parent $PSScriptRoot
}
$payloadRoot = Join-Path $packageRoot 'payload'
$maxRoot = Join-Path $env:LOCALAPPDATA 'Autodesk\3dsMax\2016 - 64bit'

function Select-MaxProfile {
    param([string]$Root)

    if ($ProfileRoot) {
        return [IO.Path]::GetFullPath($ProfileRoot)
    }

    $profiles = @()
    if (Test-Path -LiteralPath $Root -PathType Container) {
        $profiles = @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName 'usermacros') -PathType Container
        })

        if ($profiles.Count -eq 0) {
            $profiles = @(Get-ChildItem -LiteralPath $Root -Directory)
        }
    }

    if ($profiles.Count -eq 0) {
        return Join-Path $Root 'ENU'
    }
    if ($profiles.Count -eq 1) {
        return $profiles[0].FullName
    }

    Write-Host ''
    Write-Host 'Mehrere 3ds-Max-2016-Benutzerprofile wurden gefunden:'
    for ($index = 0; $index -lt $profiles.Count; $index++) {
        Write-Host ('  [{0}] {1}' -f ($index + 1), $profiles[$index].FullName)
    }
    do {
        $choice = Read-Host ('Profil waehlen (1-{0})' -f $profiles.Count)
        $parsed = 0
        $valid = [int]::TryParse($choice, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le $profiles.Count
    } until ($valid)
    return $profiles[$parsed - 1].FullName
}

function Copy-VerifiedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Timestamp,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Backups
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Paketdatei fehlt: $Source"
    }
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $backup = "$Destination.backup_$Timestamp"
        Copy-Item -LiteralPath $Destination -Destination $backup
        $Backups.Add($backup)
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "Bytepruefung fehlgeschlagen: $Destination"
    }
}

try {
    $profile = Select-MaxProfile -Root $maxRoot
    $userMacros = Join-Path $profile 'usermacros'
    $userIcons = Join-Path $profile 'usericons'
    New-Item -ItemType Directory -Path $userMacros -Force | Out-Null
    New-Item -ItemType Directory -Path $userIcons -Force | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backups = New-Object 'System.Collections.Generic.List[string]'

    # Max 2016 stores its effective #userIcons path in this UTF-16LE INI value.
    # Legacy installations may point it at Program Files, making per-user icon
    # groups invisible. Update only this key and preserve the complete old INI.
    $maxIni = Join-Path $profile '3dsmax.ini'
    if (Test-Path -LiteralPath $maxIni -PathType Leaf) {
        $iniText = Get-Content -Raw -LiteralPath $maxIni
        $desiredIniLine = "Additional Icons=$userIcons"
        if ($iniText -notmatch ('(?mi)^' + [regex]::Escape($desiredIniLine) + '$')) {
            $iniBackup = "$maxIni.backup_$timestamp"
            Copy-Item -LiteralPath $maxIni -Destination $iniBackup
            $backups.Add($iniBackup)
            if ($iniText -match '(?mi)^Additional Icons=.*$') {
                $iniText = [regex]::Replace($iniText, '(?mi)^Additional Icons=.*$', $desiredIniLine)
            } elseif ($iniText -match '(?mi)^\[Directories\]\s*$') {
                $iniText = [regex]::Replace($iniText, '(?mi)^\[Directories\]\s*$', "[Directories]`r`n$desiredIniLine", 1)
            } else {
                $iniText += "`r`n[Directories]`r`n$desiredIniLine`r`n"
            }
            $unicode = New-Object System.Text.UnicodeEncoding($false, $true)
            [IO.File]::WriteAllText($maxIni, $iniText, $unicode)
            $verifiedIni = Get-Content -Raw -LiteralPath $maxIni
            if ($verifiedIni -notmatch ('(?mi)^' + [regex]::Escape($desiredIniLine) + '$')) {
                throw "Der 3ds-Max-Benutzer-Iconpfad konnte nicht aktualisiert werden: $maxIni"
            }
        }
    }

    # 3ds Max creates this category-prefixed duplicate after certain manual
    # Evaluate/drag-and-drop workflows. Older copies redefine the same macro
    # after our file and silently replace its custom icon with the generic one.
    $generatedDuplicate = Join-Path $userMacros 'DIN Tools-DIN_UV_xatlasPack.mcr'
    if (Test-Path -LiteralPath $generatedDuplicate -PathType Leaf) {
        $duplicateBackup = "$generatedDuplicate.backup_$timestamp"
        Move-Item -LiteralPath $generatedDuplicate -Destination $duplicateBackup
        $backups.Add($duplicateBackup)
    }

    $files = @(
        @{ Source = Join-Path $payloadRoot 'DIN_UV_xatlasPack.mcr'; Destination = Join-Path $userMacros 'DIN_UV_xatlasPack.mcr' },
        @{ Source = Join-Path $payloadRoot 'DINUVPacker.exe'; Destination = Join-Path $userMacros 'DINUVPacker.exe' },
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_16i.bmp'; Destination = Join-Path $userIcons 'DINUVPacker_16i.bmp' },
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_16a.bmp'; Destination = Join-Path $userIcons 'DINUVPacker_16a.bmp' },
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_24i.bmp'; Destination = Join-Path $userIcons 'DINUVPacker_24i.bmp' },
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_24a.bmp'; Destination = Join-Path $userIcons 'DINUVPacker_24a.bmp' },
        # Max also searches the directory associated with the calling script.
        # Keep a second pair beside the MCR for installations whose #userIcons
        # system path was redirected to the protected application directory.
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_16i.bmp'; Destination = Join-Path $userMacros 'DINUVPacker_16i.bmp' },
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_16a.bmp'; Destination = Join-Path $userMacros 'DINUVPacker_16a.bmp' },
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_24i.bmp'; Destination = Join-Path $userMacros 'DINUVPacker_24i.bmp' },
        @{ Source = Join-Path $payloadRoot 'icons\DINUVPacker_24a.bmp'; Destination = Join-Path $userMacros 'DINUVPacker_24a.bmp' }
    )

    foreach ($file in $files) {
        Copy-VerifiedFile -Source $file.Source -Destination $file.Destination -Timestamp $timestamp -Backups $backups
    }

    Write-Host ''
    Write-Host 'DINUVPacker wurde erfolgreich installiert.' -ForegroundColor Green
    Write-Host "MacroScript: $userMacros\DIN_UV_xatlasPack.mcr"
    Write-Host "Programm:    $userMacros\DINUVPacker.exe"
    Write-Host "Icons:       $userIcons (plus fallback beside the MacroScript)"
    Write-Host 'Bytepruefung: erfolgreich (SHA-256)'
    if ($backups.Count -gt 0) {
        Write-Host 'Sicherungen:'
        $backups | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host 'Sicherungen: keine alten Dateien vorhanden'
    }
    Write-Host '3ds Max muss fuer Macro und Icon einmal neu gestartet werden.'
    exit 0
} catch {
    Write-Host ''
    Write-Host 'Installation fehlgeschlagen:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
