Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module `
    (
        Join-Path `
            $PSScriptRoot `
            "Day09.Common.psm1"
    ) `
    -Force

Write-Host ""
Write-Host "========================================"
Write-Host " Day 09 - Infrastructure startup"
Write-Host "========================================"
Write-Host ""

Invoke-Day09ComposeUp

Write-Host "Waiting for PostgreSQL on localhost:5432..."

Wait-Day09Postgres `
    -TimeoutSeconds 90

Write-Host "PostgreSQL is ready."

Write-Host "Waiting for Prometheus..."

Wait-Day09Http `
    -Uri "http://localhost:9090/-/ready" `
    -TimeoutSeconds 60

Write-Host "Prometheus is ready."
Write-Host ""
Write-Host "Infrastructure is ready for Day 09."
Write-Host ""
Write-Host "Next manual DB smoke-test step:"
Write-Host '  cd F:\magistry-project\inventory-service'
Write-Host '  .\mvnw.cmd spring-boot:run "-Dspring-boot.run.profiles=phase9,phase9-isolated,phase9-db"'
