param(
    [Parameter(Mandatory)]
    [ValidateSet(
        "order",
        "inventory",
        "both"
    )]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$StopFile,

    [Parameter(Mandatory)]
    [string]$OutputCsv,

    [int]$IntervalSeconds = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$culture =
    [System.Globalization.CultureInfo]::InvariantCulture

$targets = @()

if (
    $Mode -eq "order" -or
    $Mode -eq "both"
) {

    $targets +=
        [PSCustomObject]@{
            Service =
                "order-service"

            Url =
                "http://localhost:8080/actuator/prometheus"
        }
}

if (
    $Mode -eq "inventory" -or
    $Mode -eq "both"
) {

    $targets +=
        [PSCustomObject]@{
            Service =
                "inventory-service"

            Url =
                "http://localhost:8081/actuator/prometheus"
        }
}

function Convert-Day09Double {
    param(
        [string]$Value
    )

    if (
        $null -eq $Value -or
        $Value -eq ""
    ) {
        return $null
    }

    return [double]::Parse(
        $Value,
        [System.Globalization.NumberStyles]::Float,
        $culture
    )
}

function Format-Day09Double {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return (
        [double]$Value
    ).ToString(
        "G17",
        $culture
    )
}

function Get-SingleMetric {
    param(
        [string]$Text,
        [string]$Metric
    )

    $escaped =
        [regex]::Escape(
            $Metric
        )

    $pattern =
        "(?m)^$escaped" +
        "(?:\{[^\r\n]*\})?" +
        "\s+" +
        "(?<value>[-+0-9.Ee]+)$"

    $match =
        [regex]::Match(
            $Text,
            $pattern
        )

    if (-not $match.Success) {
        return $null
    }

    return Convert-Day09Double `
        $match.Groups["value"].Value
}

function Get-HeapUsedMb {
    param(
        [string]$Text
    )

    $pattern =
        '(?m)^jvm_memory_used_bytes' +
        '\{[^\r\n}]*area="heap"' +
        '[^\r\n}]*\}\s+' +
        '(?<value>[-+0-9.Ee]+)$'

    $matches =
        [regex]::Matches(
            $Text,
            $pattern
        )

    $sum =
        0.0

    foreach ($match in $matches) {

        $sum +=
            Convert-Day09Double `
                $match.Groups["value"].Value
    }

    return $sum / 1MB
}

$directory =
    Split-Path `
        -Parent `
        $OutputCsv

if (-not (Test-Path $directory)) {

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $directory |
        Out-Null
}

$encoding =
    [System.Text.UTF8Encoding]::new(
        $false
    )

$writer =
    [System.IO.StreamWriter]::new(
        $OutputCsv,
        $false,
        $encoding
    )

try {

    $writer.WriteLine(
        "timestamp_utc," +
        "service," +
        "heap_used_mb," +
        "gc_overhead_pct," +
        "jvm_threads_live," +
        "hikari_active," +
        "hikari_pending," +
        "process_cpu_time_ns," +
        "cpu_count"
    )

    $writer.Flush()

    while (
        -not (
            Test-Path $StopFile
        )
    ) {

        foreach ($target in $targets) {

            try {

                $text =
                    (
                        Invoke-WebRequest `
                            -UseBasicParsing `
                            -Uri $target.Url `
                            -TimeoutSec 5
                    ).Content

                $heapMb =
                    Get-HeapUsedMb `
                        -Text $text

                $gcOverhead =
                    Get-SingleMetric `
                        -Text $text `
                        -Metric "jvm_gc_overhead"

                $threads =
                    Get-SingleMetric `
                        -Text $text `
                        -Metric "jvm_threads_live_threads"

                $hikariActive =
                    Get-SingleMetric `
                        -Text $text `
                        -Metric "hikaricp_connections_active"

                $hikariPending =
                    Get-SingleMetric `
                        -Text $text `
                        -Metric "hikaricp_connections_pending"

                $cpuTime =
                    Get-SingleMetric `
                        -Text $text `
                        -Metric "process_cpu_time_ns_total"

                $cpuCount =
                    Get-SingleMetric `
                        -Text $text `
                        -Metric "system_cpu_count"

                $timestamp =
                    [DateTimeOffset]::UtcNow.ToString("o")

                $gcPct =
                    if ($null -eq $gcOverhead) {
                        $null
                    }
                    else {
                        $gcOverhead * 100.0
                    }

                $fields = @(
                    $timestamp,
                    $target.Service,
                    (Format-Day09Double $heapMb),
                    (Format-Day09Double $gcPct),
                    (Format-Day09Double $threads),
                    (Format-Day09Double $hikariActive),
                    (Format-Day09Double $hikariPending),
                    (Format-Day09Double $cpuTime),
                    (Format-Day09Double $cpuCount)
                )

                $writer.WriteLine(
                    $fields -join ","
                )

                $writer.Flush()

            }
            catch {

                Write-Warning (
                    "Metrics scrape failed for " +
                    $target.Service +
                    ": " +
                    $_.Exception.Message
                )
            }
        }

        Start-Sleep `
            -Seconds $IntervalSeconds
    }

}
finally {

    $writer.Dispose()
}