param(
    [Parameter(Mandatory)]
    [string]$InputCsv,

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
        [string]::IsNullOrWhiteSpace(
            $Value
        )
    ) {
        return $null
    }

    return [double]::Parse(
        $Value,
        [System.Globalization.NumberStyles]::Float,
        $culture
    )
}

function Get-Quantile {
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
        $position - $lower

    return (
        $sorted[$lower] +
        (
            $sorted[$upper] -
            $sorted[$lower]
        ) *
        $fraction
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

$rows =
    Import-Csv `
        -Path $InputCsv

$metrics = @(
    "throughput_rps",
    "error_rate_pct",
    "p50_ms",
    "p95_ms",
    "p99_ms",
    "cpu_avg_pct",
    "heap_avg_mb",
    "heap_peak_mb",
    "gc_overhead_avg_pct",
    "hikari_active_avg",
    "hikari_active_max",
    "hikari_pending_avg",
    "hikari_pending_max",
    "context_inner_p50_us",
    "context_inner_p95_us",
    "context_inner_p99_us"
)

$groups =
    $rows |
    Group-Object {
        "$($_.scenario)|" +
        "$($_.variant)|" +
        "$($_.phase)"
    }

$output =
    @()

foreach ($group in $groups) {

    $first =
        $group.Group |
        Select-Object -First 1

    $record =
        [ordered]@{
            scenario =
                $first.scenario

            variant =
                $first.variant

            phase =
                $first.phase

            n =
                $group.Count
        }

    foreach ($metric in $metrics) {

        $values =
            @(
                $group.Group |
                ForEach-Object {

                    $value =
                        Convert-Number `
                            $_.$metric

                    if ($null -ne $value) {
                        $value
                    }
                }
            )

        if ($values.Count -eq 0) {

            $record[
                "${metric}_median"
            ] = ""

            $record[
                "${metric}_q1"
            ] = ""

            $record[
                "${metric}_q3"
            ] = ""

            continue
        }

        $record[
            "${metric}_median"
        ] =
            Format-Number (
                Get-Quantile `
                    -Values $values `
                    -Q 0.50
            )

        $record[
            "${metric}_q1"
        ] =
            Format-Number (
                Get-Quantile `
                    -Values $values `
                    -Q 0.25
            )

        $record[
            "${metric}_q3"
        ] =
            Format-Number (
                Get-Quantile `
                    -Values $values `
                    -Q 0.75
            )
    }

    $output +=
        [PSCustomObject]$record
}

$output |
    Export-Csv `
        -Path $OutputCsv `
        -NoTypeInformation `
        -Encoding UTF8