$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portableCompilerRoot = Join-Path $projectRoot '.tools\mingw'
$compilerPath = if (Test-Path -LiteralPath $portableCompilerRoot) {
    (Get-ChildItem -LiteralPath $portableCompilerRoot -Filter 'g++.exe' -Recurse | Select-Object -First 1).FullName
} else {
    (Get-Command 'g++.exe' -ErrorAction SilentlyContinue).Source
}
if (-not $compilerPath) {
    throw 'MinGW-w64 g++.exe was not found on PATH or under .tools\mingw.'
}

$outputDirectory = Join-Path $projectRoot 'bin'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$output = Join-Path $outputDirectory 'DINUVPacker.exe'
$xatlasDirectory = Join-Path $projectRoot 'third_party\xatlas\source\xatlas'

& $compilerPath `
    '-std=c++11' '-O2' '-DNDEBUG' '-Wall' '-Wextra' '-pedantic' `
    '-static' '-static-libgcc' '-static-libstdc++' `
    ('-I' + $xatlasDirectory) `
    (Join-Path $projectRoot 'src\main.cpp') `
    (Join-Path $xatlasDirectory 'xatlas.cpp') `
    '-o' $output

if ($LASTEXITCODE -ne 0) {
    throw "C++ build failed with exit code $LASTEXITCODE."
}

Get-Item -LiteralPath $output | Select-Object FullName, Length, LastWriteTime
Get-FileHash -Algorithm SHA256 -LiteralPath $output
