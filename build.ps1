<#
.SYNOPSIS
    Compiles wincom.ps1 to wincom.exe with PS2EXE and stamps the version into it.
.EXAMPLE
    .\build.ps1 -Version 0.0.2
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'

$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+(\.\d+){0,3}$') {
    throw "Invalid version '$Version', expected e.g. 1.2.3"
}

$pattern = "(?m)^\`$WincomVersion = '[^']*'"
$source = Get-Content (Join-Path $PSScriptRoot 'wincom.ps1') -Raw
if ($source -notmatch $pattern) {
    throw "Version line not found in wincom.ps1"
}

$temp = Join-Path ([IO.Path]::GetTempPath()) "wincom-$Version.ps1"
$source -replace $pattern, "`$WincomVersion = '$Version'" | Set-Content $temp -Encoding UTF8

try {
    Import-Module ps2exe
    Invoke-ps2exe -inputFile $temp -outputFile (Join-Path $PSScriptRoot 'wincom.exe') `
        -version $Version -title 'wincom' -product 'wincom' `
        -description 'Lightweight serial terminal' -copyright 'Copyright (c) 2025 Moggla'
}
finally {
    Remove-Item $temp -ErrorAction SilentlyContinue
}
