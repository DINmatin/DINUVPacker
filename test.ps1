$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$executable = Join-Path $projectRoot 'bin\DINUVPacker.exe'
if (-not (Test-Path -LiteralPath $executable)) {
    & (Join-Path $projectRoot 'build.ps1')
}

$input = Join-Path $projectRoot 'tests\two_islands.dinuv'
$output = Join-Path $projectRoot 'tests\two_islands.result'
& $executable $input $output
if ($LASTEXITCODE -ne 0) {
    throw "DINUVPacker test execution failed with exit code $LASTEXITCODE."
}

python (Join-Path $projectRoot 'tests\validate_result.py') $output
if ($LASTEXITCODE -ne 0) {
    throw "DINUVPacker result validation failed with exit code $LASTEXITCODE."
}

$stackedInput = Join-Path $projectRoot 'tests\stacked_islands.dinuv'
$stackedOutput = Join-Path $projectRoot 'tests\stacked_islands.result'
& $executable $stackedInput $stackedOutput
if ($LASTEXITCODE -ne 0) {
    throw "DINUVPacker stacked-island test execution failed with exit code $LASTEXITCODE."
}
python (Join-Path $projectRoot 'tests\validate_stacked_result.py') $stackedOutput
if ($LASTEXITCODE -ne 0) {
    throw "DINUVPacker stacked-island validation failed with exit code $LASTEXITCODE."
}

$autoInput = Join-Path $projectRoot 'tests\auto_cube.dinuv'
$autoOutput = Join-Path $projectRoot 'tests\auto_cube.result'
& $executable $autoInput $autoOutput
if ($LASTEXITCODE -ne 0) {
    throw "DINUVPacker auto-unwrap test execution failed with exit code $LASTEXITCODE."
}
python (Join-Path $projectRoot 'tests\validate_auto_result.py') $autoOutput
if ($LASTEXITCODE -ne 0) {
    throw "DINUVPacker auto-unwrap validation failed with exit code $LASTEXITCODE."
}

Write-Output 'DINUVPacker tests passed.'
