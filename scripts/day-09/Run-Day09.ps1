param(
    [ValidateSet("db", "context", "failure", "all")]
    [string]$Suite = "db",

    [int]$Repetitions = 5,

    [int]$TotalRequests = 10000,

    [int]$Concurrency = 100,

    [int]$WarmupRequests = 500,

    [int]$WarmupConcurrency = 20,

    [int]$ContextReads = 10000,

    [double]$FailureRps = 20,

    [int]$FailureDurationSeconds = 90,

    [int]$StartDelaySeconds = 2,

    [int]$CooldownSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Day09.Common.psm1") -Force

$Root = Get-Day09ProjectRoot
$DbPassword = Get-Day09DbPassword
$SessionId = Get-Date -Format "yyyyMMdd-HHmmss"

$ResultRoot = Join-Path $Root "results/day-09/runs/$SessionId"
$SummaryCsv = Join-Path $ResultRoot "summary.csv"
$AggregateCsv = Join-Path $ResultRoot "aggregate.csv"
$Exporter = Join-Path $PSScriptRoot "Export-Day09IntervalSummary.ps1"
$Aggregator = Join-Path $PSScriptRoot "New-Day09Aggregate.ps1"

New-Item -ItemType Directory -Force -Path $ResultRoot | Out-Null

if (($TotalRequests % $Concurrency) -ne 0) {
    throw "TotalRequests must be divisible by Concurrency."
}

if (($WarmupRequests % $WarmupConcurrency) -ne 0) {
    throw "WarmupRequests must be divisible by WarmupConcurrency."
}

if ($FailureDurationSeconds -lt 75) {
    throw "FailureDurationSeconds should be at least 75 seconds."
}

$gitCommit = (git -C $Root rev-parse HEAD).Trim()
$gitBranch = (git -C $Root rev-parse --abbrev-ref HEAD).Trim()

$sessionMetadata = [ordered]@{
    sessionId              = $SessionId
    createdAtUtc           = [DateTimeOffset]::UtcNow.ToString("o")
    gitCommit              = $gitCommit
    gitBranch              = $gitBranch
    repetitions            = $Repetitions
    totalRequests          = $TotalRequests
    concurrency            = $Concurrency
    warmupRequests         = $WarmupRequests
    warmupConcurrency      = $WarmupConcurrency
    contextReads           = $ContextReads
    failureRps             = $FailureRps
    failureDurationSeconds = $FailureDurationSeconds
    startDelaySeconds      = $StartDelaySeconds
    cooldownSeconds        = $CooldownSeconds
}

Save-Day09Json -Value $sessionMetadata -Path (Join-Path $ResultRoot "session-metadata.json")

Write-Host ""
Write-Host "========================================"
Write-Host " DAY 09"
Write-Host " Gatling reproducible experiments"
Write-Host "========================================"
Write-Host ""
Write-Host "Results:"
Write-Host $ResultRoot
Write-Host ""

Invoke-Day09ComposeUp

Wait-Day09Postgres -TimeoutSeconds 90
Wait-Day09Http -Uri "http://localhost:9090/-/ready" -TimeoutSeconds 60

function Invoke-Warmup {
    param(
        [Parameter(Mandatory)] [string]$Simulation,
        [Parameter(Mandatory)] [hashtable]$Properties,
        [Parameter(Mandatory)] [string]$LogDirectory,
        [Parameter(Mandatory)] [string]$Name
    )

    Write-Host ""
    Write-Host "Warm-up: $Name"

    Clear-Day09GatlingReports

    $handle = Start-Day09Gatling -SimulationClass $Simulation -Properties $Properties -LogDirectory $LogDirectory -RunName "$Name-warmup"
    Wait-Day09Process -Handle $handle
    Clear-Day09GatlingReports
}

function Invoke-FixedMeasurement {
    param(
        [Parameter(Mandatory)] [string]$Simulation,
        [Parameter(Mandatory)] [hashtable]$Properties,
        [Parameter(Mandatory)] [string]$Scenario,
        [Parameter(Mandatory)] [string]$Variant,
        [Parameter(Mandatory)] [int]$Run,
        [Parameter(Mandatory)] [string]$TargetPrometheusUrl,
        [Parameter(Mandatory)] [string]$TargetUri,
        [Parameter(Mandatory)] [string]$PrimaryService,
        [string]$HikariService,
        [bool]$OtelEnabled,
        [string]$ContextSamplesCsv = "",
        [Parameter(Mandatory)] [string]$RunDirectory
    )

    $rawDir = Join-Path $RunDirectory "raw"
    $logsDir = Join-Path $RunDirectory "logs"
    $gatlingDir = Join-Path $RunDirectory "gatling"

    New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
    New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

    $startMarker = Join-Path $rawDir "start.marker"
    $endMarker = Join-Path $rawDir "end.marker"
    $startSnapshot = Join-Path $rawDir "start.prom"
    $endSnapshot = Join-Path $rawDir "end.prom"
    $samples = Join-Path $rawDir "system-metrics.csv"
    $stopFile = Join-Path $rawDir "sampler.stop"

    Remove-Item $startMarker, $endMarker, $stopFile -Force -ErrorAction SilentlyContinue

    $gatlingProperties = @{}
    foreach ($key in $Properties.Keys) {
        $gatlingProperties[$key] = $Properties[$key]
    }

    $gatlingProperties["startMarker"] = $startMarker
    $gatlingProperties["endMarker"] = $endMarker
    $gatlingProperties["startDelaySeconds"] = $StartDelaySeconds

    if (-not [string]::IsNullOrWhiteSpace($ContextSamplesCsv)) {
        $gatlingProperties["contextSamplesPath"] = $ContextSamplesCsv
    }

    $samplerMode = if ($PrimaryService -eq "inventory-service") { "inventory" } else { "order" }

    $sampler = Start-Day09Sampler -Mode $samplerMode -StopFile $stopFile -OutputCsv $samples

    try {
    Clear-Day09GatlingReports

    # Capture the baseline synchronously BEFORE Gatling can
    # generate any measured traffic.
    Save-Day09Snapshot `
        -Uri $TargetPrometheusUrl `
        -Path $startSnapshot

    $handle = Start-Day09Gatling `
        -SimulationClass $Simulation `
        -Properties $gatlingProperties `
        -LogDirectory $logsDir `
        -RunName "$Scenario-$Variant-run$Run"

    $simulationStart =
        Wait-Day09Marker -Path $startMarker

    $loadStart =
        $simulationStart.AddSeconds(
            $StartDelaySeconds
        )

    $simulationEnd =
        Wait-Day09Marker `
            -Path $endMarker `
            -TimeoutSeconds 1800

    Save-Day09Snapshot `
        -Uri $TargetPrometheusUrl `
        -Path $endSnapshot
        Save-Day09Snapshot -Uri $TargetPrometheusUrl -Path $endSnapshot

        Stop-Day09Sampler -Process $sampler -StopFile $stopFile
        $sampler = $null

        Wait-Day09Process -Handle $handle
        Copy-Day09GatlingReport -Destination $gatlingDir

        & $Exporter `
            -Scenario $Scenario `
            -Variant $Variant `
            -Run $Run `
            -Phase "measured" `
            -StartSnapshot $startSnapshot `
            -EndSnapshot $endSnapshot `
            -SamplesCsv $samples `
            -StartUtc $loadStart.ToString("o") `
            -EndUtc $simulationEnd.ToString("o") `
            -PrimaryService $PrimaryService `
            -HikariService $HikariService `
            -TargetUri $TargetUri `
            -LoadModel "fixed-count" `
            -Concurrency $Concurrency `
            -ConfiguredRequests $TotalRequests `
            -OtelEnabled $OtelEnabled `
            -ContextSamplesCsv $ContextSamplesCsv `
            -OutputCsv $SummaryCsv

        Save-Day09Json -Value ([ordered]@{
            scenario           = $Scenario
            variant            = $Variant
            run                = $Run
            simulationStart    = $simulationStart.ToString("o")
            loadStart          = $loadStart.ToString("o")
            simulationEnd      = $simulationEnd.ToString("o")
            otelEnabled        = $OtelEnabled
            configuredRequests = $TotalRequests
            concurrency        = $Concurrency
        }) -Path (Join-Path $RunDirectory "metadata.json")

    } finally {
        if ($null -ne $sampler) {
            Stop-Day09Sampler -Process $sampler -StopFile $stopFile
        }
    }
}

function Invoke-DbVariant {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("baseline", "protected")]
        [string]$Variant,

        [Parameter(Mandatory)]
        [int]$Run
    )

    Write-Host ""
    Write-Host "========================================"
    Write-Host " DB experiment"
    Write-Host " Variant: $Variant"
    Write-Host " Run: $Run"
    Write-Host "========================================"

    $limit = if ($Variant -eq "baseline") { "-1" } else { "10" }
    $runDir = Join-Path $ResultRoot "db/$Variant/run-$Run"
    $logsDir = Join-Path $runDir "logs"
    $inventory = $null

    try {

        Assert-Day09PortFree -Port 8081

        $inventory = Start-Day09Service `
            -Name "inventory-service" `
            -ServiceDirectory (Join-Path $Root "inventory-service") `
            -Profiles "phase9,phase9-isolated,phase9-db" `
            -Environment @{
                DB_PASSWORD                  = $DbPassword
                EXPERIMENT_CONCURRENCY_LIMIT = $limit
            } `
            -LogDirectory $logsDir

        Wait-Day09Service `
            -Handle $inventory `
            -Uri "http://localhost:8081/actuator/health"

        $smoke = Invoke-RestMethod -Uri "http://localhost:8081/test/db-starvation"
        if (-not $smoke.virtual) {
            throw "DB experiment is not running on a virtual thread."
        }

        Invoke-Warmup -Simulation "ua.edu.magistry.loadtest.DbStarvationSimulation" -Properties @{
            baseUrl           = "http://localhost:8081"
            totalRequests     = $WarmupRequests
            concurrency       = $WarmupConcurrency
            startDelaySeconds = 0
        } -LogDirectory $logsDir -Name "db-$Variant-run$Run"

        Start-Sleep -Seconds $CooldownSeconds

        Invoke-FixedMeasurement -Simulation "ua.edu.magistry.loadtest.DbStarvationSimulation" -Properties @{
            baseUrl       = "http://localhost:8081"
            totalRequests = $TotalRequests
            concurrency   = $Concurrency
        } -Scenario "db-concurrency" -Variant $Variant -Run $Run `
          -TargetPrometheusUrl "http://localhost:8081/actuator/prometheus" `
          -TargetUri "/test/db-starvation" `
          -PrimaryService "inventory-service" `
          -HikariService "inventory-service" `
          -OtelEnabled $false `
          -RunDirectory $runDir

    } finally {
        Stop-Day09ProcessTree -Handle $inventory
    }
}

function Invoke-ContextVariant {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("threadlocal", "scoped-value")]
        [string]$Variant,

        [Parameter(Mandatory)]
        [int]$Run
    )

    Write-Host ""
    Write-Host "========================================"
    Write-Host " Context experiment"
    Write-Host " Variant: $Variant"
    Write-Host " Run: $Run"
    Write-Host "========================================"

    if ($Variant -eq "threadlocal") {
        $profile = "context-threadlocal"
        $expected = "ThreadLocalContextAccessor"
    } else {
        $profile = "context-scoped"
        $expected = "ScopedValueContextAccessor"
    }

    $runDir = Join-Path $ResultRoot "context/$Variant/run-$Run"
    $logsDir = Join-Path $runDir "logs"
    $contextSamples = Join-Path $runDir "raw/context-elapsed.csv"

    $inventory = $null
    $order = $null

    try {
        $inventory = Start-Day09Service `
            -Name "inventory-service" `
            -ServiceDirectory (Join-Path $Root "inventory-service") `
            -Profiles "phase9,phase9-isolated,$profile" `
            -Environment @{ DB_PASSWORD = $DbPassword } `
            -LogDirectory $logsDir

        Wait-Day09Http -Uri "http://localhost:8081/actuator/health"

        $order = Start-Day09Service `
            -Name "order-service" `
            -ServiceDirectory (Join-Path $Root "order-service") `
            -Profiles "phase9,phase9-isolated,$profile" `
            -LogDirectory $logsDir

        Wait-Day09Http -Uri "http://localhost:8080/actuator/health"

        $propagation = Invoke-RestMethod -Uri "http://localhost:8080/test/context-propagation"
        if (-not $propagation.propagated) {
            throw "Context propagation failed for $Variant."
        }

        if ((-not $propagation.orderVirtual) -or (-not $propagation.inventoryVirtual)) {
            throw "Context correctness check did not use virtual threads."
        }

        Invoke-Warmup -Simulation "ua.edu.magistry.loadtest.ContextBenchmarkSimulation" -Properties @{
            baseUrl                = "http://localhost:8080"
            totalRequests          = $WarmupRequests
            concurrency            = $WarmupConcurrency
            reads                  = $ContextReads
            expectedImplementation = $expected
            startDelaySeconds      = 0
        } -LogDirectory $logsDir -Name "context-$Variant-run$Run"

        Start-Sleep -Seconds $CooldownSeconds

        Invoke-FixedMeasurement -Simulation "ua.edu.magistry.loadtest.ContextBenchmarkSimulation" -Properties @{
            baseUrl                = "http://localhost:8080"
            totalRequests          = $TotalRequests
            concurrency            = $Concurrency
            reads                  = $ContextReads
            expectedImplementation = $expected
        } -Scenario "context-access" -Variant $Variant -Run $Run `
          -TargetPrometheusUrl "http://localhost:8080/actuator/prometheus" `
          -TargetUri "/test/context-benchmark" `
          -PrimaryService "order-service" `
          -HikariService "order-service" `
          -OtelEnabled $false `
          -ContextSamplesCsv $contextSamples `
          -RunDirectory $runDir

    } finally {
        Stop-Day09ProcessTree -Handle $order
        Stop-Day09ProcessTree -Handle $inventory
    }
}

function Invoke-FailureRun {
    param(
        [Parameter(Mandatory)]
        [int]$Run
    )

    Write-Host ""
    Write-Host "========================================"
    Write-Host " Failure experiment"
    Write-Host " Run: $Run"
    Write-Host "========================================"

    $runDir = Join-Path $ResultRoot "failure/run-$Run"
    $rawDir = Join-Path $runDir "raw"
    $logsDir = Join-Path $runDir "logs"
    $eventsDir = Join-Path $runDir "events"
    $gatlingDir = Join-Path $runDir "gatling"

    New-Item -ItemType Directory -Force -Path $rawDir | Out-Null

    $inventory = $null
    $order = $null
    $sampler = $null

    try {
        Initialize-Day09Toxiproxy
        Set-Day09ToxiproxyScenario -Scenario "normal"

        $inventory = Start-Day09Service `
            -Name "inventory-service" `
            -ServiceDirectory (Join-Path $Root "inventory-service") `
            -Profiles "phase9" `
            -Environment @{ DB_PASSWORD = $DbPassword } `
            -LogDirectory $logsDir

        Wait-Day09Http -Uri "http://localhost:8081/actuator/health"

        $order = Start-Day09Service `
            -Name "order-service" `
            -ServiceDirectory (Join-Path $Root "order-service") `
            -Profiles "phase9,phase6" `
            -Environment @{ INVENTORY_BASE_URL = "http://localhost:8666" } `
            -LogDirectory $logsDir

        Wait-Day09Http -Uri "http://localhost:8080/actuator/health"

        Invoke-Warmup -Simulation "ua.edu.magistry.loadtest.OrderWarmupSimulation" -Properties @{
            baseUrl           = "http://localhost:8080"
            totalRequests     = $WarmupRequests
            concurrency       = $WarmupConcurrency
        } -LogDirectory $logsDir -Name "failure-run$Run"

        Start-Sleep -Seconds $CooldownSeconds

        Set-Day09ToxiproxyScenario -Scenario "normal"
        Clear-Day09GatlingReports

        $startMarker = Join-Path $rawDir "start.marker"
        $endMarker = Join-Path $rawDir "end.marker"
        $samples = Join-Path $rawDir "system-metrics.csv"
        $stopFile = Join-Path $rawDir "sampler.stop"

        Remove-Item $startMarker, $endMarker, $stopFile -Force -ErrorAction SilentlyContinue

        $sampler = Start-Day09Sampler -Mode "both" -StopFile $stopFile -OutputCsv $samples

        $handle = Start-Day09Gatling -SimulationClass "ua.edu.magistry.loadtest.OrderFailureSimulation" -Properties @{
            baseUrl           = "http://localhost:8080"
            usersPerSecond    = $FailureRps
            durationSeconds   = $FailureDurationSeconds
            startDelaySeconds = $StartDelaySeconds
            startMarker       = $startMarker
            endMarker         = $endMarker
        } -LogDirectory $logsDir -RunName "failure-run$Run"

        $simulationStart = Wait-Day09Marker -Path $startMarker
        $t0 = $simulationStart.AddSeconds($StartDelaySeconds)

        Wait-Day09Until -Utc ($t0.AddMilliseconds(-250))
        $snapshotT0 = Join-Path $rawDir "t0-normal-start.prom"
        Save-Day09Snapshot -Uri "http://localhost:8080/actuator/prometheus" -Path $snapshotT0

        $t15 = $t0.AddSeconds(15)
        Wait-Day09Until -Utc $t15
        $snapshotT15 = Join-Path $rawDir "t15-normal-end.prom"
        Save-Day09Snapshot -Uri "http://localhost:8080/actuator/prometheus" -Path $snapshotT15

        Set-Day09ToxiproxyScenario -Scenario "delay-1000"
        $delayAppliedAt = [DateTimeOffset]::UtcNow

        $t30 = $t0.AddSeconds(30)
        Wait-Day09Until -Utc $t30
        $snapshotT30 = Join-Path $rawDir "t30-delay-end.prom"
        Save-Day09Snapshot -Uri "http://localhost:8080/actuator/prometheus" -Path $snapshotT30

        Set-Day09ToxiproxyScenario -Scenario "connection-reset"
        $resetAppliedAt = [DateTimeOffset]::UtcNow

        $t45 = $t0.AddSeconds(45)
        Wait-Day09Until -Utc $t45
        $snapshotT45 = Join-Path $rawDir "t45-failure-end.prom"
        Save-Day09Snapshot -Uri "http://localhost:8080/actuator/prometheus" -Path $snapshotT45

        Set-Day09ToxiproxyScenario -Scenario "normal"
        $restoredAt = [DateTimeOffset]::UtcNow

        $simulationEnd = Wait-Day09Marker -Path $endMarker -TimeoutSeconds 1800
        $snapshotEnd = Join-Path $rawDir "recovery-end.prom"
        Save-Day09Snapshot -Uri "http://localhost:8080/actuator/prometheus" -Path $snapshotEnd

        Stop-Day09Sampler -Process $sampler -StopFile $stopFile
        $sampler = $null

        Wait-Day09Process -Handle $handle
        Copy-Day09GatlingReport -Destination $gatlingDir

        $phaseRequests = [int][Math]::Round($FailureRps * 15)
        $recoveryRequests = [int][Math]::Round($FailureRps * ($FailureDurationSeconds - 45))

        & $Exporter -Scenario "failure-recovery" -Variant "fault-injection" -Run $Run -Phase "normal" `
            -StartSnapshot $snapshotT0 -EndSnapshot $snapshotT15 -SamplesCsv $samples `
            -StartUtc $t0.ToString("o") -EndUtc $t15.ToString("o") `
            -PrimaryService "order-service" -HikariService "inventory-service" `
            -TargetUri "/orders" -LoadModel "open-constant-rps" `
            -ConfiguredRps $FailureRps -ConfiguredRequests $phaseRequests `
            -OtelEnabled $true -OutputCsv $SummaryCsv

        & $Exporter -Scenario "failure-recovery" -Variant "fault-injection" -Run $Run -Phase "delay-1000" `
            -StartSnapshot $snapshotT15 -EndSnapshot $snapshotT30 -SamplesCsv $samples `
            -StartUtc $t15.ToString("o") -EndUtc $t30.ToString("o") `
            -PrimaryService "order-service" -HikariService "inventory-service" `
            -TargetUri "/orders" -LoadModel "open-constant-rps" `
            -ConfiguredRps $FailureRps -ConfiguredRequests $phaseRequests `
            -OtelEnabled $true -OutputCsv $SummaryCsv

        & $Exporter -Scenario "failure-recovery" -Variant "fault-injection" -Run $Run -Phase "connection-reset" `
            -StartSnapshot $snapshotT30 -EndSnapshot $snapshotT45 -SamplesCsv $samples `
            -StartUtc $t30.ToString("o") -EndUtc $t45.ToString("o") `
            -PrimaryService "order-service" -HikariService "inventory-service" `
            -TargetUri "/orders" -LoadModel "open-constant-rps" `
            -ConfiguredRps $FailureRps -ConfiguredRequests $phaseRequests `
            -OtelEnabled $true -OutputCsv $SummaryCsv

        & $Exporter -Scenario "failure-recovery" -Variant "fault-injection" -Run $Run -Phase "recovery" `
            -StartSnapshot $snapshotT45 -EndSnapshot $snapshotEnd -SamplesCsv $samples `
            -StartUtc $t45.ToString("o") -EndUtc $simulationEnd.ToString("o") `
            -PrimaryService "order-service" -HikariService "inventory-service" `
            -TargetUri "/orders" -LoadModel "open-constant-rps" `
            -ConfiguredRps $FailureRps -ConfiguredRequests $recoveryRequests `
            -OtelEnabled $true -OutputCsv $SummaryCsv

        Save-Day09Url -Uri "http://localhost:8080/actuator/circuitbreakers" -Path (Join-Path $eventsDir "circuitbreakers.json")
        Save-Day09Url -Uri "http://localhost:8080/actuator/circuitbreakerevents" -Path (Join-Path $eventsDir "circuitbreaker-events.json")
        Save-Day09Url -Uri "http://localhost:8080/actuator/retryevents" -Path (Join-Path $eventsDir "retry-events.json")

        Save-Day09Json -Value ([ordered]@{
            run                        = $Run
            otelEnabled                = $true
            simulationStart            = $simulationStart.ToString("o")
            loadStart                  = $t0.ToString("o")
            delayRequestedAt           = $t15.ToString("o")
            delayAppliedAt             = $delayAppliedAt.ToString("o")
            connectionResetRequestedAt = $t30.ToString("o")
            connectionResetAppliedAt   = $resetAppliedAt.ToString("o")
            restoreRequestedAt         = $t45.ToString("o")
            restoredAt                 = $restoredAt.ToString("o")
            simulationEnd              = $simulationEnd.ToString("o")
            rps                        = $FailureRps
            durationSeconds            = $FailureDurationSeconds
        }) -Path (Join-Path $runDir "metadata.json")

    } finally {
        if ($null -ne $sampler) {
            Stop-Day09Sampler -Process $sampler -StopFile (Join-Path $rawDir "sampler.stop")
        }

        try { Set-Day09ToxiproxyScenario -Scenario "normal" } catch {}

        Stop-Day09ProcessTree -Handle $order
        Stop-Day09ProcessTree -Handle $inventory
    }
}

if ($Suite -eq "db" -or $Suite -eq "all") {
    for ($run = 1; $run -le $Repetitions; $run++) {
        $variants = if ($run % 2 -eq 1) { @("baseline", "protected") } else { @("protected", "baseline") }
        foreach ($variant in $variants) {
            Invoke-DbVariant -Variant $variant -Run $run
        }
    }
}

if ($Suite -eq "context" -or $Suite -eq "all") {
    for ($run = 1; $run -le $Repetitions; $run++) {
        $variants = if ($run % 2 -eq 1) { @("threadlocal", "scoped-value") } else { @("scoped-value", "threadlocal") }
        foreach ($variant in $variants) {
            Invoke-ContextVariant -Variant $variant -Run $run
        }
    }
}

if ($Suite -eq "failure" -or $Suite -eq "all") {
    for ($run = 1; $run -le $Repetitions; $run++) {
        Invoke-FailureRun -Run $run
    }
}

if (Test-Path $SummaryCsv) {
    & $Aggregator -InputCsv $SummaryCsv -OutputCsv $AggregateCsv
}

Write-Host ""
Write-Host "========================================"
Write-Host " DAY 09 COMPLETED"
Write-Host "========================================"
Write-Host ""
Write-Host "Summary:"
Write-Host $SummaryCsv
Write-Host ""
Write-Host "Aggregate:"
Write-Host $AggregateCsv