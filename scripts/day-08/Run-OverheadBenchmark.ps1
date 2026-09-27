param(
    [string]$Variant = "otel-off",
    [int]$TotalRequests = 1000,
    [int]$Concurrency = 20,
    [string]$Url = "http://localhost:8080/orders",
    [string]$MetricsUrl = "http://localhost:8080/actuator/prometheus"
)

$OutputDir = ".\results\day-08\overhead"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Running Overhead Benchmark: $Variant" -ForegroundColor Cyan
Write-Host " Total Requests: $TotalRequests, Concurrency:$Concurrency" -ForegroundColor Cyan
Write-Host " Target URL: $Url" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

[System.Net.ServicePointManager]::DefaultConnectionLimit = [Math]::Max($Concurrency * 2, 50)
[System.Net.ServicePointManager]::Expect100Continue =$false

$RunspacePool = [runspacefactory]::CreateRunspacePool(1,$Concurrency)
$RunspacePool.Open()

$ScriptBlock = {
    param($Url,$Payload)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = "POST"
        $req.ContentType = "application/json"
        $req.Timeout = 10000
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
        $req.ContentLength =$bytes.Length
        $stream =$req.GetRequestStream()
        $stream.Write($bytes, 0,$bytes.Length)
        $stream.Close()
        $res =$req.GetResponse()
        $sw.Stop()
        $res.Close()
        return @{ Success = $true; Latency =$sw.Elapsed.TotalMilliseconds }
    } catch {
        $sw.Stop()
        return @{ Success = $false; Latency =$sw.Elapsed.TotalMilliseconds }
    }
}

$payload = '{"productId":1,"quantity":2}'
$tasks = [System.Collections.Generic.List[psobject]]::new()

$benchmarkStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

1..$TotalRequests | ForEach-Object {
    $ps = [powershell]::Create()
    $ps.RunspacePool =$RunspacePool
    [void]$ps.AddScript($ScriptBlock)
    [void]$ps.AddArgument($Url)
    [void]$ps.AddArgument($payload)
    $tasks.Add([PSCustomObject]@{ Pipe = $ps; AsyncResult =$ps.BeginInvoke() })
}

$latencies = [System.Collections.Generic.List[double]]::new()
$successCount = 0
$failCount = 0

foreach ($task in $tasks) {
    $result = $task.Pipe.EndInvoke($task.AsyncResult)
    $task.Pipe.Dispose()
    if ($result.Success) {
        $successCount++
        $latencies.Add([double]$result.Latency)
    } else {
        $failCount++
    }
}

$benchmarkStopwatch.Stop()
$RunspacePool.Close()
$RunspacePool.Dispose()

$totalElapsedSec =$benchmarkStopwatch.Elapsed.TotalSeconds
$throughput = [Math]::Round(($successCount / [Math]::Max($totalElapsedSec, 0.001)), 2)

$sortedLatencies =$latencies | Sort-Object

function Get-Percentile($list,$p) {
    if ($null -eq $list -or$list.Count -eq 0) { return 0 }
    $index = [Math]::Floor(($list.Count - 1) * ($p / 100))
    return [Math]::Round($list[$index], 2)
}

$p50 = Get-Percentile $sortedLatencies 50
$p95 = Get-Percentile $sortedLatencies 95
$p99 = Get-Percentile $sortedLatencies 99

$cpuUsage = "N/A"
$heapUsedMb = "N/A"
try {
    $promMetrics = (Invoke-WebRequest -Uri$MetricsUrl -UseBasicParsing -TimeoutSec 5).Content
    if ($promMetrics -match 'jvm_memory_used_bytes\{area="heap",id="G1 Old Gen"\}\s+([0-9\.E\+\-]+)') {
        $oldGen = [double]$Matches[1]
        if ($promMetrics -match 'jvm_memory_used_bytes\{area="heap",id="G1 Eden Space"\}\s+([0-9\.E\+\-]+)') {
            $eden = [double]$Matches[1]
            $heapUsedMb = [Math]::Round(($oldGen + $eden) / (1024 * 1024), 2)
        }
    }
    if ($promMetrics -match 'process_cpu_time_ns_total\s+([0-9\.E\+\-]+)') {
        $cpuTimeSec = [Math]::Round(([double]$Matches[1]) / 1e9, 2)
        $cpuUsage = "$cpuTimeSec s"
    }
} catch {
    Write-Warning "Could not scrape Prometheus metrics directly."
}

Write-Host "`n--- Execution Summary ---" -ForegroundColor Green
Write-Host "Success: $successCount, Failed: $failCount"
Write-Host "Duration: $([Math]::Round($totalElapsedSec, 2)) s"
Write-Host "Throughput: $throughput req/s"
Write-Host "Latency p50: $p50 ms"
Write-Host "Latency p95: $p95 ms"
Write-Host "Latency p99: $p99 ms"
Write-Host "Heap Used: $heapUsedMb MB"
Write-Host "CPU Process Time: $cpuUsage"

$csvFile = Join-Path $OutputDir "$Variant.csv"
[PSCustomObject]@{
    Variant        = $Variant
    TotalRequests  = $TotalRequests
    Concurrency    = $Concurrency
    ThroughputRps  = $throughput
    P50_ms         = $p50
    P95_ms         = $p95
    P99_ms         = $p99
    HeapUsed_MB    = $heapUsedMb
    CpuTime        = $cpuUsage
} | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

Write-Host "`nSaved results to $csvFile" -ForegroundColor Yellow
