param(
    [Parameter(Mandatory)]
    [string]$Scenario,

    [Parameter(Mandatory)]
    [string]$Variant,

    [Parameter(Mandatory)]
    [int]$Run,

    [Parameter(Mandatory)]
    [string]$Phase,

    [Parameter(Mandatory)]
    [string]$StartSnapshot,

    [Parameter(Mandatory)]
    [string]$EndSnapshot,

    [Parameter(Mandatory)]
    [string]$SamplesCsv,

    [Parameter(Mandatory)]
    [string]$StartUtc,

    [Parameter(Mandatory)]
    [string]$EndUtc,

    [Parameter(Mandatory)]
    [string]$PrimaryService,

    [string]$HikariService,

    [Parameter(Mandatory)]
    [string]$TargetUri,

    [Parameter(Mandatory)]
    [string]$LoadModel,

    [int]$Concurrency = 0,

    [double]$ConfiguredRps = 0,

    [int]$ConfiguredRequests = 0,

    [bool]$OtelEnabled = $false,

    [string]$ContextSamplesCsv = "",

    [Parameter(Mandatory)]
    [string]$OutputCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$culture =
    [System.Globalization.CultureInfo]::InvariantCulture

function Convert-Number {
    param(
        [string]$Value
    )

    if (
        $null -eq $Value `
        -or
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

function Format-Number {
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

function ConvertFrom-PrometheusText {
    param(
        [string]$Text
    )

    $result =
        [System.Collections.Generic.List[object]]::new()

    foreach (
        $line in (
            $Text -split "`r?`n"
        )
    ) {

        if (
            [string]::IsNullOrWhiteSpace(
                $line
            ) `
            -or
            $line.StartsWith("#")
        ) {
            continue
        }

        $match =
            [regex]::Match(
                $line,
                '^(?<name>[a-zA-Z_:][a-zA-Z0-9_:]*)' +
                '(?:\{(?<labels>.*)\})?' +
                '\s+(?<value>[-+0-9.Ee]+)$'
            )

        if (-not $match.Success) {
            continue
        }

        $labels =
            @{}

        $labelsText =
            $match.Groups["labels"].Value

        if ( `
            -not [string]::IsNullOrWhiteSpace(
                $labelsText
            )
        ) {

            $labelMatches =
                [regex]::Matches(
                    $labelsText,
                    '(?<key>[a-zA-Z_][a-zA-Z0-9_]*)=' +
                    '"(?<value>(?:\\.|[^"])*)"'
                )

            foreach (
                $labelMatch in $labelMatches
            ) {

                $value =
                    $labelMatch.Groups["value"].Value

                $value =
                    $value.Replace(
                        '\"',
                        '"'
                    )

                $value =
                    $value.Replace(
                        '\\',
                        '\'
                    )

                $labels[
                    $labelMatch.Groups["key"].Value
                ] =
                    $value
            }
        }

        $result.Add(
            [PSCustomObject]@{
                Name =
                    $match.Groups["name"].Value

                Labels =
                    $labels

                Value =
                    Convert-Number (
                        $match.Groups["value"].Value
                    )
            }
        )
    }

    return $result.ToArray()
}

function Get-MetricSum {
    param(
        $Samples,
        [string]$Name
    )

    $sum =
        0.0

    $found =
        $false

    foreach (
        $sample in $Samples
    ) {

        if ($sample.Name -eq $Name) {

            $sum +=
                [double]$sample.Value

            $found =
                $true
        }
    }

    if (-not $found) {
        return $null
    }

    return $sum
}

function Get-RequestCount {
    param(
        $Samples,
        [string]$Uri,
        [bool]$SuccessOnly
    )

    $sum =
        0.0

    foreach (
        $sample in $Samples
    ) {

        if (
            $sample.Name `
            -ne
            "http_server_requests_seconds_count"
        ) {
            continue
        }

        if ( `
            -not $sample.Labels.ContainsKey("uri")
        ) {
            continue
        }

        if (
            $sample.Labels["uri"] `
            -ne
            $Uri
        ) {
            continue
        }

        if ($SuccessOnly) {

            if ( `
                -not $sample.Labels.ContainsKey("status")
            ) {
                continue
            }

            if (
                $sample.Labels["status"] `
                -notmatch '^2'
            ) {
                continue
            }
        }

        $sum +=
            [double]$sample.Value
    }

    return $sum
}

function Get-BucketMap {
    param(
        $Samples,
        [string]$Uri
    )

    $map =
        @{}

    foreach (
        $sample in $Samples
    ) {

        if (
            $sample.Name `
            -ne
            "http_server_requests_seconds_bucket"
        ) {
            continue
        }

        if ( `
            -not $sample.Labels.ContainsKey("uri") `
            -or `
            -not $sample.Labels.ContainsKey("le")
        ) {
            continue
        }

        if (
            $sample.Labels["uri"] `
            -ne
            $Uri
        ) {
            continue
        }

        $le =
            [string]$sample.Labels["le"]

        if ( `
            -not $map.ContainsKey(
                $le
            )
        ) {

            $map[$le] =
                0.0
        }

        $map[$le] +=
            [double]$sample.Value
    }

    return $map
}

function Get-HistogramQuantile {
    param(
        $StartSamples,
        $EndSamples,
        [string]$Uri,
        [double]$Quantile
    )

    $startMap =
        Get-BucketMap `
            -Samples $StartSamples `
            -Uri $Uri

    $endMap =
        Get-BucketMap `
            -Samples $EndSamples `
            -Uri $Uri

    $keys =
        @(
            $startMap.Keys
            $endMap.Keys
        ) |
        Sort-Object -Unique

    $buckets =
        @()

    foreach ($key in $keys) {

        $startValue =
            if (
                $startMap.ContainsKey(
                    $key
                )
            ) {
                [double]$startMap[$key]
            }
            else {
                0.0
            }

        $endValue =
            if (
                $endMap.ContainsKey(
                    $key
                )
            ) {
                [double]$endMap[$key]
            }
            else {
                0.0
            }

        $delta =
            [Math]::Max(
                0.0,
                $endValue - $startValue
            )

        $bound =
            if ($key -eq "+Inf") {

                [double]::PositiveInfinity

            }
            else {

                Convert-Number $key
            }

        $buckets +=
            [PSCustomObject]@{
                Bound = $bound
                Count = $delta
            }
    }

    $buckets =
        $buckets |
        Sort-Object Bound

    if ($buckets.Count -eq 0) {
        return $null
    }

    $total =
        [double]$buckets[
            $buckets.Count - 1
        ].Count

    if ($total -le 0) {
        return $null
    }

    $target =
        $Quantile * $total

    $previousBound =
        0.0

    $previousCount =
        0.0

    foreach ($bucket in $buckets) {

        if (
            $bucket.Count `
            -ge
            $target
        ) {

            if (
                [double]::IsPositiveInfinity(
                    $bucket.Bound
                )
            ) {
                return $previousBound
            }

            $bucketCount =
                $bucket.Count -
                $previousCount

            if ($bucketCount -le 0) {
                return $bucket.Bound
            }

            $position =
                (
                    $target -
                    $previousCount
                ) /
                $bucketCount

            return (
                $previousBound `
                +
                (
                    $bucket.Bound -
                    $previousBound
                ) *
                $position
            )
        }

        $previousBound =
            $bucket.Bound

        $previousCount =
            $bucket.Count
    }

    return $previousBound
}

function Get-SeriesStats {
    param(
        $Rows,
        [string]$Column
    )

    $values =
        @()

    foreach ($row in $Rows) {

        $raw =
            [string]$row.$Column

        if ( `
            -not [string]::IsNullOrWhiteSpace(
                $raw
            )
        ) {

            $values +=
                Convert-Number $raw
        }
    }

    if ($values.Count -eq 0) {

        return [PSCustomObject]@{
            Average = $null
            Maximum = $null
        }
    }

    return [PSCustomObject]@{
        Average =
            (
                $values |
                Measure-Object `
                    -Average
            ).Average

        Maximum =
            (
                $values |
                Measure-Object `
                    -Maximum
            ).Maximum
    }
}

function Get-ExactQuantile {
    param(
        [double[]]$Values,
        [double]$Q
    )

    if ($Values.Count -eq 0) {
        return $null
    }

    $sorted =
        @(
            $Values |
            Sort-Object
        )

    if ($sorted.Count -eq 1) {
        return $sorted[0]
    }

    $position =
        $Q *
        (
            $sorted.Count - 1
        )

    $lower =
        [Math]::Floor(
            $position
        )

    $upper =
        [Math]::Ceiling(
            $position
        )

    if ($lower -eq $upper) {
        return $sorted[$lower]
    }

    $fraction =
        $position -
        $lower

    return (
        $sorted[$lower] `
        +
        (
            $sorted[$upper] `
            -
            $sorted[$lower]
        ) *
        $fraction
    )
}

$start =
    [DateTimeOffset]::Parse(
        $StartUtc,
        $culture
    )

$end =
    [DateTimeOffset]::Parse(
        $EndUtc,
        $culture
    )

$durationSeconds =
    (
        $end - $start
    ).TotalSeconds

if ($durationSeconds -le 0) {
    throw "Invalid measurement interval."
}

$startText =
    Get-Content `
        -Path $StartSnapshot `
        -Raw

$endText =
    Get-Content `
        -Path $EndSnapshot `
        -Raw

$startMetrics =
    ConvertFrom-PrometheusText `
        -Text $startText

$endMetrics =
    ConvertFrom-PrometheusText `
        -Text $endText

$startRequests =
    Get-RequestCount `
        -Samples $startMetrics `
        -Uri $TargetUri `
        -SuccessOnly $false

$endRequests =
    Get-RequestCount `
        -Samples $endMetrics `
        -Uri $TargetUri `
        -SuccessOnly $false

$startSuccess =
    Get-RequestCount `
        -Samples $startMetrics `
        -Uri $TargetUri `
        -SuccessOnly $true

$endSuccess =
    Get-RequestCount `
        -Samples $endMetrics `
        -Uri $TargetUri `
        -SuccessOnly $true

$requests =
    [Math]::Max(
        0,
        $endRequests -
        $startRequests
    )

$success =
    [Math]::Max(
        0,
        $endSuccess -
        $startSuccess
    )

$errors =
    [Math]::Max(
        0,
        $requests -
        $success
    )

$errorRate =
    if ($requests -eq 0) {
        0.0
    }
    else {
        (
            $errors /
            $requests
        ) * 100.0
    }

$p50 =
    Get-HistogramQuantile `
        -StartSamples $startMetrics `
        -EndSamples $endMetrics `
        -Uri $TargetUri `
        -Quantile 0.50

$p95 =
    Get-HistogramQuantile `
        -StartSamples $startMetrics `
        -EndSamples $endMetrics `
        -Uri $TargetUri `
        -Quantile 0.95

$p99 =
    Get-HistogramQuantile `
        -StartSamples $startMetrics `
        -EndSamples $endMetrics `
        -Uri $TargetUri `
        -Quantile 0.99

$startCpu =
    Get-MetricSum `
        -Samples $startMetrics `
        -Name "process_cpu_time_ns_total"

$endCpu =
    Get-MetricSum `
        -Samples $endMetrics `
        -Name "process_cpu_time_ns_total"

$cpuCount =
    Get-MetricSum `
        -Samples $endMetrics `
        -Name "system_cpu_count"

$cpuPct =
    $null

if (
    $null -ne $startCpu `
    -and
    $null -ne $endCpu `
    -and
    $null -ne $cpuCount `
    -and
    $cpuCount -gt 0
) {

    $cpuPct =
        (
            (
                $endCpu -
                $startCpu
            ) `
            /
            (
                $durationSeconds *
                1000000000.0 *
                $cpuCount
            )
        ) *
        100.0
}

$allSamples =
    Import-Csv `
        -Path $SamplesCsv

$primaryRows =
    @(
        $allSamples |
        Where-Object {

            $_.service -eq $PrimaryService `
            -and `
            [DateTimeOffset]::Parse(
                $_.timestamp_utc,
                $culture
            ) -ge $start `
            -and `
            [DateTimeOffset]::Parse(
                $_.timestamp_utc,
                $culture
            ) -le $end
        }
    )

if (
    [string]::IsNullOrWhiteSpace(
        $HikariService
    )
) {

    $HikariService =
        $PrimaryService
}

$hikariRows =
    @(
        $allSamples |
        Where-Object {

            $_.service -eq $HikariService `
            -and `
            [DateTimeOffset]::Parse(
                $_.timestamp_utc,
                $culture
            ) -ge $start `
            -and `
            [DateTimeOffset]::Parse(
                $_.timestamp_utc,
                $culture
            ) -le $end
        }
    )

$heap =
    Get-SeriesStats `
        -Rows $primaryRows `
        -Column "heap_used_mb"

$gc =
    Get-SeriesStats `
        -Rows $primaryRows `
        -Column "gc_overhead_pct"

$hikariActive =
    Get-SeriesStats `
        -Rows $hikariRows `
        -Column "hikari_active"

$hikariPending =
    Get-SeriesStats `
        -Rows $hikariRows `
        -Column "hikari_pending"

$contextP50 =
    $null

$contextP95 =
    $null

$contextP99 =
    $null

if ( `
    -not [string]::IsNullOrWhiteSpace(
        $ContextSamplesCsv
    ) `
    -and
    (Test-Path $ContextSamplesCsv)
) {

    $contextValues =
        @(
            Import-Csv `
                -Path $ContextSamplesCsv |
            ForEach-Object {
                Convert-Number `
                    $_.elapsed_micros
            }
        )

    $contextP50 =
        Get-ExactQuantile `
            -Values $contextValues `
            -Q 0.50

    $contextP95 =
        Get-ExactQuantile `
            -Values $contextValues `
            -Q 0.95

    $contextP99 =
        Get-ExactQuantile `
            -Values $contextValues `
            -Q 0.99
}

$throughput =
    $requests /
    $durationSeconds

$row =
    [PSCustomObject][ordered]@{

        timestamp_utc =
            [DateTimeOffset]::UtcNow.ToString("o")

        scenario =
            $Scenario

        variant =
            $Variant

        run =
            $Run

        phase =
            $Phase

        otel_enabled =
            $OtelEnabled

        load_model =
            $LoadModel

        concurrency =
            if ($Concurrency -eq 0) {
                ""
            }
            else {
                $Concurrency
            }

        configured_rps =
            if ($ConfiguredRps -eq 0) {
                ""
            }
            else {
                Format-Number $ConfiguredRps
            }

        configured_requests =
            if ($ConfiguredRequests -eq 0) {
                ""
            }
            else {
                $ConfiguredRequests
            }

        observed_requests =
            [Math]::Round(
                $requests
            )

        success =
            [Math]::Round(
                $success
            )

        errors =
            [Math]::Round(
                $errors
            )

        error_rate_pct =
            Format-Number $errorRate

        p50_ms =
            if ($null -eq $p50) {
                ""
            }
            else {
                Format-Number (
                    $p50 * 1000.0
                )
            }

        p95_ms =
            if ($null -eq $p95) {
                ""
            }
            else {
                Format-Number (
                    $p95 * 1000.0
                )
            }

        p99_ms =
            if ($null -eq $p99) {
                ""
            }
            else {
                Format-Number (
                    $p99 * 1000.0
                )
            }

        throughput_rps =
            Format-Number $throughput

        cpu_avg_pct =
            Format-Number $cpuPct

        heap_avg_mb =
            Format-Number $heap.Average

        heap_peak_mb =
            Format-Number $heap.Maximum

        gc_overhead_avg_pct =
            Format-Number $gc.Average

        hikari_active_avg =
            Format-Number $hikariActive.Average

        hikari_active_max =
            Format-Number $hikariActive.Maximum

        hikari_pending_avg =
            Format-Number $hikariPending.Average

        hikari_pending_max =
            Format-Number $hikariPending.Maximum

        context_inner_p50_us =
            Format-Number $contextP50

        context_inner_p95_us =
            Format-Number $contextP95

        context_inner_p99_us =
            Format-Number $contextP99

        duration_s =
            Format-Number $durationSeconds

        start_utc =
            $start.ToString("o")

        end_utc =
            $end.ToString("o")
    }

$directory =
    Split-Path `
        -Parent `
        $OutputCsv

New-Item `
    -ItemType Directory `
    -Force `
    -Path $directory |
    Out-Null

if (Test-Path $OutputCsv) {

    $row |
        Export-Csv `
            -Path $OutputCsv `
            -NoTypeInformation `
            -Append `
            -Encoding UTF8

}
else {

    $row |
        Export-Csv `
            -Path $OutputCsv `
            -NoTypeInformation `
            -Encoding UTF8
}