param(
    [switch]$StartContainer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$ComposeFile = Join-Path $ProjectRoot "infrastructure/compose.yaml"

Import-Module `
    (Join-Path $PSScriptRoot "Day07.Toxiproxy.psm1") `
    -Force


Write-Host "========================================"
Write-Host " Day 07 - Toxiproxy initialization"
Write-Host "========================================"
Write-Host ""


if (-not (Test-Path $ComposeFile)) {
    throw "Docker Compose file not found: $ComposeFile"
}


if ($StartContainer) {

    Write-Host "Starting Toxiproxy container..."
    Write-Host "Compose file: $ComposeFile"
    Write-Host ""

    docker compose `
        -f $ComposeFile `
        up -d toxiproxy

    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose failed to start Toxiproxy."
    }

    Write-Host ""
    Write-Host "Waiting for Toxiproxy API..."

    $ready = $false

    for ($i = 0; $i -lt 30; $i++) {

        try {
            if (Test-Toxiproxy) {
                $ready = $true
                break
            }
        }
        catch {
            # Toxiproxy is still starting.
        }

        Start-Sleep -Seconds 1
    }

    if (-not $ready) {

        Write-Host ""
        Write-Host "Toxiproxy container did not become ready."

        Write-Host "Container status:"

        docker compose `
            -f $ComposeFile `
            ps toxiproxy

        Write-Host ""
        Write-Host "Container logs:"

        docker compose `
            -f $ComposeFile `
            logs --tail=50 toxiproxy

        throw "Toxiproxy did not become ready within 30 seconds."
    }
}


if (-not (Test-Toxiproxy)) {
    throw "Toxiproxy is not available."
}


Write-Host ""
Write-Host "Creating Day 07 proxy..."

New-Day07Proxy | Out-Null


Write-Host ""
Write-Host "Resetting previous Day 07 faults..."

Clear-Day07Toxics

Enable-Day07InventoryProxy `
    -Enabled $true |
    Out-Null


Write-Host ""
Write-Host "========================================"
Write-Host " Toxiproxy state"
Write-Host "========================================"

Get-Day07State | Format-List


Write-Host ""
Write-Host "Day 07 Toxiproxy initialization completed."