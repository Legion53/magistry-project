[CmdletBinding()]
param(
    [string] $ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string] $OrderBaseUrl = 'http://localhost:8080',
    [string] $InventoryBaseUrl = 'http://localhost:8081',
    [string] $ToxiproxyBaseUrl = 'http://localhost:8474',
    [string] $RunId = ('run-' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')),
    [ValidateRange(5, 100)]
    [int] $BaselineSamples = 10,
    [ValidateRange(1, 60)]
    [int] $SamplesPerDelay = 5,
    [ValidateRange(3, 20)]
    [int] $FailureRequests = 3,
    [ValidateRange(3, 20)]
    [int] $StableIntervals = 5,
    [ValidateRange(0, 60)]
    [int] $SampleIntervalSeconds = 1,
    [ValidateRange(30, 120)]
    [int] $OpenStateWaitSeconds = 32,
    [ValidateRange(1, 10000)]
    [double] $MinimumStableLatencyMs = 250,
    [ValidateRange(1, 10)]
    [double] $BaselineP95Multiplier = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Day07.Toxiproxy.psm1') -Force

function Invoke-Day07OrderRequest {
    param(
        [Parameter(Mandatory)] [System.Net.Http.HttpClient] $Client,
        [Parameter(Mandatory)] [string] $OrderUri,
        [Parameter(Mandatory)] [string] $Phase,
        [Parameter(Mandatory)] [string] $Scenario,
        [Parameter(Mandatory)] [int] $Sequence
    )

    $timestamp = [DateTimeOffset]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $httpStatus = 0
    $orderStatus = 'TRANSPORT_ERROR'
    $errorText = $null
    $response = $null
    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Post,
        "$OrderUri/orders"
    )
    $request.Content = [System.Net.Http.StringContent]::new(
        '{"productId":1,"quantity":2}',
        [System.Text.Encoding]::UTF8,
        'application/json'
    )

    try {
        $response = $Client.SendAsync($request).GetAwaiter().GetResult()
        $httpStatus = [int]$response.StatusCode
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            $payload = $content | ConvertFrom-Json
            if ($null -ne $payload.status) {
                $orderStatus = [string]$payload.status
            }
        }
    }
    catch {
        $errorText = $_.Exception.Message
    }
    finally {
        $stopwatch.Stop()
        if ($null -ne $response) {
            $response.Dispose()
        }
        $request.Dispose()
    }

    [PSCustomObject]@{
        timestamp_utc = $timestamp.ToString('o')
        sequence = $Sequence
        phase = $Phase
        scenario = $Scenario
        http_status = $httpStatus
        order_status = $orderStatus
        latency_ms = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
        is_error = [bool](($httpStatus -ne 200) -or ($orderStatus -ne 'ACCEPTED'))
        error = $errorText
    }
}

function Get-Day07Percentile {
    param(
        [Parameter(Mandatory)] [double[]] $Values,
        [Parameter(Mandatory)] [double] $Percentile
    )

    if ($Values.Count -eq 0) {
        throw 'Cannot calculate a percentile from an empty sample.'
    }
    $ordered = @($Values | Sort-Object)
    $index = [Math]::Min($ordered.Count - 1, [Math]::Ceiling($Percentile * $ordered.Count) - 1)
    return [double]$ordered[$index]
}

function Get-Day07CircuitBreakerState {
    param([Parameter(Mandatory)] [string] $OrderUri)

    $response = Invoke-RestMethod -Uri "$OrderUri/actuator/circuitbreakers" -Method GET -ErrorAction Stop
    $breaker = $response.circuitBreakers.inventoryService
    if ($null -eq $breaker -or [string]::IsNullOrWhiteSpace([string]$breaker.state)) {
        throw 'The Actuator response does not contain circuitBreakers.inventoryService.state. Start order-service with the phase6 profile.'
    }
    return ([string]$breaker.state).ToUpperInvariant()
}

function Assert-Day07Health {
    param(
        [Parameter(Mandatory)] [string] $BaseUrl,
        [Parameter(Mandatory)] [string] $ServiceName
    )

    $health = Invoke-RestMethod -Uri "$BaseUrl/actuator/health" -Method GET -ErrorAction Stop
    if ($health.status -ne 'UP') {
        throw "$ServiceName is not UP. Observed status: $($health.status)"
    }
}

function Add-Day07Marker {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[object]] $Markers,
        [Parameter(Mandatory)] [string] $Event,
        [Parameter(Mandatory)] [string] $Scenario,
        [string] $Details = ''
    )

    $Markers.Add([PSCustomObject]@{
        timestamp_utc = [DateTimeOffset]::UtcNow.ToString('o')
        event = $Event
        scenario = $Scenario
        details = $Details
    })
}

function Save-Day07Snapshot {
    param(
        [Parameter(Mandatory)] [string] $EventsDirectory,
        [Parameter(Mandatory)] [int] $Ordinal,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $OrderUri,
        [Parameter(Mandatory)] [string] $ToxiproxyUri
    )

    $snapshot = [PSCustomObject]@{
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        circuit_breakers = Invoke-RestMethod -Uri "$OrderUri/actuator/circuitbreakers" -Method GET -ErrorAction Stop
        circuit_breaker_events = Invoke-RestMethod -Uri "$OrderUri/actuator/circuitbreakerevents" -Method GET -ErrorAction Stop
        retry_events = Invoke-RestMethod -Uri "$OrderUri/actuator/retryevents" -Method GET -ErrorAction Stop
        toxiproxy_proxy = Get-Day07InventoryProxy -ToxiproxyBaseUrl $ToxiproxyUri
    }
    $path = Join-Path $EventsDirectory ('{0:D2}-{1}.json' -f $Ordinal, $Name)
    Set-Content -LiteralPath $path -Value ($snapshot | ConvertTo-Json -Depth 20) -Encoding utf8
    return $path
}

$resultsRoot = Join-Path $ProjectRoot 'results/day-07'
$paths = @{
    raw = Join-Path $resultsRoot (Join-Path 'raw' $RunId)
    metrics = Join-Path $resultsRoot (Join-Path 'metrics' $RunId)
    events = Join-Path $resultsRoot (Join-Path 'events' $RunId)
    charts = Join-Path $resultsRoot (Join-Path 'charts' $RunId)
}
foreach ($path in $paths.Values) {
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to overwrite existing experiment data: $path. Choose a different RunId."
    }
}
foreach ($path in $paths.Values) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

$requests = [System.Collections.Generic.List[object]]::new()
$markers = [System.Collections.Generic.List[object]]::new()
$recoveryCycles = [System.Collections.Generic.List[object]]::new()
$sequence = 0
$snapshotOrdinal = 0
$baselineP95 = $null
$stableLatencyThresholdMs = $null
$experimentError = $null
$httpClient = [System.Net.Http.HttpClient]::new()
$httpClient.Timeout = [TimeSpan]::FromSeconds(15)

try {
    Assert-Day07Health -BaseUrl $InventoryBaseUrl -ServiceName 'inventory-service (direct)'
    Assert-Day07Health -BaseUrl $OrderBaseUrl -ServiceName 'order-service'
    Wait-Day07Toxiproxy -ToxiproxyBaseUrl $ToxiproxyBaseUrl | Out-Null

    if ((Get-Day07CircuitBreakerState -OrderUri $OrderBaseUrl) -ne 'CLOSED') {
        throw 'Circuit Breaker is not CLOSED before the run. Restart order-service with the phase6 profile, then rerun this experiment.'
    }

    Set-Day07ToxiproxyFault -Scenario 'normal' -ToxiproxyBaseUrl $ToxiproxyBaseUrl | Out-Null
    Add-Day07Marker -Markers $markers -Event 'baseline-started' -Scenario 'normal'
    for ($sample = 1; $sample -le $BaselineSamples; $sample++) {
        $sequence++
        $requests.Add((Invoke-Day07OrderRequest -Client $httpClient -OrderUri $OrderBaseUrl -Phase 'baseline' -Scenario 'normal' -Sequence $sequence))
        if ($sample -lt $BaselineSamples) { Start-Sleep -Seconds $SampleIntervalSeconds }
    }
    $baseline = @($requests | Where-Object { $_.phase -eq 'baseline' })
    if (@($baseline | Where-Object { $_.is_error }).Count -ne 0) {
        throw 'Baseline contains unsuccessful requests; do not use an unhealthy baseline for MTTR calculation.'
    }
    $baselineP95 = Get-Day07Percentile -Values ([double[]]$baseline.latency_ms) -Percentile 0.95
    $stableLatencyThresholdMs = [Math]::Max($MinimumStableLatencyMs, [Math]::Ceiling($baselineP95 * $BaselineP95Multiplier))
    Add-Day07Marker -Markers $markers -Event 'baseline-complete' -Scenario 'normal' -Details "p95_ms=$baselineP95; stable_threshold_ms=$stableLatencyThresholdMs"

    foreach ($delayScenario in @('delay-100', 'delay-500', 'delay-1000')) {
        Set-Day07ToxiproxyFault -Scenario $delayScenario -ToxiproxyBaseUrl $ToxiproxyBaseUrl | Out-Null
        Add-Day07Marker -Markers $markers -Event 'fault-injected' -Scenario $delayScenario
        for ($sample = 1; $sample -le $SamplesPerDelay; $sample++) {
            $sequence++
            $requests.Add((Invoke-Day07OrderRequest -Client $httpClient -OrderUri $OrderBaseUrl -Phase $delayScenario -Scenario $delayScenario -Sequence $sequence))
            if ($sample -lt $SamplesPerDelay) { Start-Sleep -Seconds $SampleIntervalSeconds }
        }
        Set-Day07ToxiproxyFault -Scenario 'normal' -ToxiproxyBaseUrl $ToxiproxyBaseUrl | Out-Null
        Add-Day07Marker -Markers $markers -Event 'network-restored' -Scenario $delayScenario
    }

    foreach ($faultScenario in @('reset-peer', 'downstream-unavailable')) {
        Set-Day07ToxiproxyFault -Scenario $faultScenario -ToxiproxyBaseUrl $ToxiproxyBaseUrl | Out-Null
        $failureInjectedAt = [DateTimeOffset]::UtcNow
        Add-Day07Marker -Markers $markers -Event 'fault-injected' -Scenario $faultScenario -Details 'T_failure_injection: Toxiproxy API mutation acknowledged.'
        $snapshotOrdinal++
        Save-Day07Snapshot -EventsDirectory $paths.events -Ordinal $snapshotOrdinal -Name "$faultScenario-injected" -OrderUri $OrderBaseUrl -ToxiproxyUri $ToxiproxyBaseUrl | Out-Null

        for ($sample = 1; $sample -le $FailureRequests; $sample++) {
            $sequence++
            $requests.Add((Invoke-Day07OrderRequest -Client $httpClient -OrderUri $OrderBaseUrl -Phase 'failure' -Scenario $faultScenario -Sequence $sequence))
        }

        $stateAfterFailure = Get-Day07CircuitBreakerState -OrderUri $OrderBaseUrl
        if ($stateAfterFailure -ne 'OPEN') {
            throw "Circuit Breaker did not open after $FailureRequests $faultScenario requests; observed state: $stateAfterFailure."
        }
        Add-Day07Marker -Markers $markers -Event 'circuit-open-observed' -Scenario $faultScenario
        $snapshotOrdinal++
        Save-Day07Snapshot -EventsDirectory $paths.events -Ordinal $snapshotOrdinal -Name "$faultScenario-open" -OrderUri $OrderBaseUrl -ToxiproxyUri $ToxiproxyBaseUrl | Out-Null

        Set-Day07ToxiproxyFault -Scenario 'normal' -ToxiproxyBaseUrl $ToxiproxyBaseUrl | Out-Null
        Add-Day07Marker -Markers $markers -Event 'network-restored' -Scenario $faultScenario
        $restoreAt = [DateTimeOffset]::UtcNow

        $probeNotBefore = $failureInjectedAt.AddSeconds($OpenStateWaitSeconds)
        $remaining = $probeNotBefore - [DateTimeOffset]::UtcNow
        if ($remaining.TotalMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([int][Math]::Ceiling($remaining.TotalMilliseconds))
        }

        $sequence++
        $requests.Add((Invoke-Day07OrderRequest -Client $httpClient -OrderUri $OrderBaseUrl -Phase 'half-open-probe' -Scenario $faultScenario -Sequence $sequence))
        Add-Day07Marker -Markers $markers -Event 'half-open-probe' -Scenario $faultScenario

        $sequence++
        $requests.Add((Invoke-Day07OrderRequest -Client $httpClient -OrderUri $OrderBaseUrl -Phase 'closing-probe' -Scenario $faultScenario -Sequence $sequence))
        if ((Get-Day07CircuitBreakerState -OrderUri $OrderBaseUrl) -ne 'CLOSED') {
            throw "Circuit Breaker did not close after the two recovery probes for $faultScenario."
        }
        Add-Day07Marker -Markers $markers -Event 'circuit-closed-observed' -Scenario $faultScenario

        $stableSamples = @()
        for ($sample = 1; $sample -le $StableIntervals; $sample++) {
            $sequence++
            $record = Invoke-Day07OrderRequest -Client $httpClient -OrderUri $OrderBaseUrl -Phase 'stable-sample' -Scenario $faultScenario -Sequence $sequence
            $record | Add-Member -NotePropertyName circuit_state -NotePropertyValue (Get-Day07CircuitBreakerState -OrderUri $OrderBaseUrl)
            $requests.Add($record)
            $stableSamples += $record
            if ($sample -lt $StableIntervals) { Start-Sleep -Seconds $SampleIntervalSeconds }
        }

        $isStable = @($stableSamples | Where-Object {
            $_.is_error -or $_.latency_ms -gt $stableLatencyThresholdMs -or $_.circuit_state -ne 'CLOSED'
        }).Count -eq 0
        if (-not $isStable) {
            throw "Stable recovery criterion was not met for $faultScenario. Review the raw sample data; it has been retained."
        }

        $stableAt = [DateTimeOffset]::UtcNow
        $mttrMs = [Math]::Round(($stableAt - $failureInjectedAt).TotalMilliseconds, 3)
        Add-Day07Marker -Markers $markers -Event 'stable-after-recovery' -Scenario $faultScenario -Details "T_stable_after_recovery; MTTR_ms=$mttrMs"
        $recoveryCycles.Add([PSCustomObject]@{
            scenario = $faultScenario
            failure_injection_utc = $failureInjectedAt.ToString('o')
            network_restored_utc = $restoreAt.ToString('o')
            stable_after_recovery_utc = $stableAt.ToString('o')
            mttr_ms = $mttrMs
            stable_latency_threshold_ms = $stableLatencyThresholdMs
            stable_intervals = $StableIntervals
        })
        $snapshotOrdinal++
        Save-Day07Snapshot -EventsDirectory $paths.events -Ordinal $snapshotOrdinal -Name "$faultScenario-recovered" -OrderUri $OrderBaseUrl -ToxiproxyUri $ToxiproxyBaseUrl | Out-Null
    }
}
catch {
    # Persist every completed request and snapshot before reporting the failed
    # acceptance condition. A failed experiment is still valid evidence.
    $experimentError = $_
}
finally {
    try {
        Set-Day07ToxiproxyFault -Scenario 'normal' -ToxiproxyBaseUrl $ToxiproxyBaseUrl | Out-Null
    }
    catch {
        Write-Warning "Could not restore the Day 7 proxy to normal: $($_.Exception.Message)"
    }
    $httpClient.Dispose()
}

$requestsPath = Join-Path $paths.raw 'requests.csv'
$markersPath = Join-Path $paths.events 'timeline.csv'
$summaryPath = Join-Path $paths.metrics 'phase-summary.csv'
$recoveryPath = Join-Path $paths.metrics 'recovery-summary.json'
$chartPath = Join-Path $paths.charts 'recovery-timeline.svg'

$requests | Export-Csv -LiteralPath $requestsPath -NoTypeInformation -Encoding utf8
$markers | Export-Csv -LiteralPath $markersPath -NoTypeInformation -Encoding utf8

$phaseSummary = foreach ($group in ($requests | Group-Object phase, scenario)) {
    $values = [double[]]@($group.Group | ForEach-Object { [double]$_.latency_ms })
    $errors = @($group.Group | Where-Object { $_.is_error }).Count
    [PSCustomObject]@{
        phase = $group.Group[0].phase
        scenario = $group.Group[0].scenario
        samples = $group.Count
        errors = $errors
        error_rate_pct = [Math]::Round((100.0 * $errors / $group.Count), 3)
        latency_p50_ms = [Math]::Round((Get-Day07Percentile -Values $values -Percentile 0.50), 3)
        latency_p95_ms = [Math]::Round((Get-Day07Percentile -Values $values -Percentile 0.95), 3)
        latency_max_ms = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 3)
    }
}
$phaseSummary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding utf8

[PSCustomObject]@{
    run_id = $RunId
    generated_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    baseline_p95_ms = $baselineP95
    stable_latency_threshold_ms = $stableLatencyThresholdMs
    stable_intervals = $StableIntervals
    mttr_definition = 'T(stable_after_recovery) - T(failure_injection)'
    recovery_cycles = @($recoveryCycles)
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $recoveryPath -Encoding utf8

if ($requests.Count -gt 0 -and $markers.Count -gt 0 -and $null -ne $stableLatencyThresholdMs) {
    & (Join-Path $PSScriptRoot 'New-RecoveryTimeline.ps1') `
        -RequestsCsv $requestsPath `
        -TimelineCsv $markersPath `
        -OutputSvg $chartPath `
        -LatencyThresholdMs $stableLatencyThresholdMs | Out-Null
}

if ($null -ne $experimentError) {
    throw $experimentError
}

[PSCustomObject]@{
    run_id = $RunId
    raw_requests = $requestsPath
    phase_metrics = $summaryPath
    recovery_metrics = $recoveryPath
    events = $paths.events
    chart = $chartPath
    mttr_ms = @($recoveryCycles | ForEach-Object { $_.mttr_ms })
} | ConvertTo-Json -Depth 10
