param(
    [Parameter(Mandatory)]
    [ValidateSet(
        "normal",
        "delay-100",
        "delay-500",
        "delay-1000",
        "connection-reset",
        "downstream-unavailable"
    )]
    [string]$Scenario
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module `
    (Join-Path $PSScriptRoot "Day07.Toxiproxy.psm1") `
    -Force


Write-Host "========================================"
Write-Host " Day 07 - Fault injection"
Write-Host " Scenario: $Scenario"
Write-Host "========================================"
Write-Host ""


if (-not (Test-Toxiproxy)) {
    throw "Toxiproxy API is not available."
}


switch ($Scenario) {

    "normal" {
        Restore-Day07Network
    }

    "delay-100" {
        Set-Day07Latency -Milliseconds 100
    }

    "delay-500" {
        Set-Day07Latency -Milliseconds 500
    }

    "delay-1000" {
        Set-Day07Latency -Milliseconds 1000
    }

    "connection-reset" {
        Set-Day07ConnectionReset
    }

    "downstream-unavailable" {
        Set-Day07DownstreamUnavailable
    }
}


Write-Host ""
Write-Host "Current state:"
Get-Day07State | Format-List