param(
    [Parameter(Mandatory)]
    [ValidateSet(
        "baseline",
        "delay-100",
        "delay-500",
        "delay-1000",
        "connection-reset",
        "downstream-unavailable"
    )]
    [string]$Scenario,

    [int]$Concurrency = 20,

    [int]$DurationSeconds = 30,

    [int]$WarmupSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")

$ResultsRoot = Join-Path `
    $ProjectRoot `
    "results/day-07"

$RawRoot = Join-Path `
    $ResultsRoot `
    "raw"

$MetricsRoot = Join-Path `
    $ResultsRoot `
    "metrics"


New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null
New-Item -ItemType Directory -Force -Path $MetricsRoot | Out-Null


$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$scenarioDir = Join-Path `
    $RawRoot `
    "$Scenario-$timestamp"

New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null


Write-Host "========================================"
Write-Host " DAY 07 EXPERIMENT"
Write-Host "========================================"
Write-Host "Scenario    : $Scenario"
Write-Host "Concurrency : $Concurrency"
Write-Host "Warmup      : $WarmupSeconds sec"
Write-Host "Measurement  : $DurationSeconds sec"
Write-Host "Output      : $scenarioDir"
Write-Host ""


# ---------------------------------------------------------
# 1. Restore clean state
# ---------------------------------------------------------

& (Join-Path $PSScriptRoot "Reset-Toxiproxy.ps1")


# ---------------------------------------------------------
# 2. Configure fault
# ---------------------------------------------------------

if ($Scenario -ne "baseline") {

    & (Join-Path $PSScriptRoot "Set-ToxiproxyFault.ps1") `
        -Scenario $Scenario
}


# ---------------------------------------------------------
# 3. Record start time
# ---------------------------------------------------------

$startTime = Get-Date

@"
scenario=$Scenario
start=$($startTime.ToString("o"))
concurrency=$Concurrency
warmupSeconds=$WarmupSeconds
durationSeconds=$DurationSeconds
"@ | Set-Content `
    (Join-Path $scenarioDir "experiment.properties")


# ---------------------------------------------------------
# 4. Warmup
# ---------------------------------------------------------

Write-Host ""
Write-Host "Warmup: $WarmupSeconds seconds..."

.\oha.exe `
    -c $Concurrency `
    -z "${WarmupSeconds}s" `
    http://localhost:8080/orders `
    > (Join-Path $scenarioDir "warmup.txt")


# ---------------------------------------------------------
# 5. Measurement
# ---------------------------------------------------------

Write-Host ""
Write-Host "Measurement: $DurationSeconds seconds..."

$ohaOutput = Join-Path `
    $scenarioDir `
    "oha.txt"

.\oha.exe `
    -c $Concurrency `
    -z "${DurationSeconds}s" `
    http://localhost:8080/orders `
    > $ohaOutput


# ---------------------------------------------------------
# 6. Record end
# ---------------------------------------------------------

$endTime = Get-Date

@"
end=$($endTime.ToString("o"))
"@ | Add-Content `
    (Join-Path $scenarioDir "experiment.properties")


# ---------------------------------------------------------
# 7. Save Toxiproxy state
# ---------------------------------------------------------

$toxiproxyState = Join-Path `
    $scenarioDir `
    "toxiproxy-state.json"

Invoke-RestMethod `
    "http://localhost:8474/proxies/inventory-service" |
    ConvertTo-Json -Depth 10 |
    Set-Content $toxiproxyState


# ---------------------------------------------------------
# 8. Restore clean network
# ---------------------------------------------------------

& (Join-Path $PSScriptRoot "Reset-Toxiproxy.ps1")


Write-Host ""
Write-Host "========================================"
Write-Host " Scenario completed"
Write-Host "========================================"
Write-Host "Results: $scenarioDir"