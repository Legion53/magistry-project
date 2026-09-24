Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module `
    (Join-Path $PSScriptRoot "Day07.Toxiproxy.psm1") `
    -Force


Write-Host "Resetting Day 07 Toxiproxy..."

Restore-Day07Network

Write-Host ""
Get-Day07State | Format-List

Write-Host ""
Write-Host "Day 07 network restored."