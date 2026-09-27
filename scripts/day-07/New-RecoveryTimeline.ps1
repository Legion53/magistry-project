[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RequestsCsv,

    [Parameter(Mandatory)]
    [string] $TimelineCsv,

    [Parameter(Mandatory)]
    [string] $OutputSvg,

    [Parameter(Mandatory)]
    [double] $LatencyThresholdMs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RequestsCsv -PathType Leaf)) {
    throw "Request dataset was not found: $RequestsCsv"
}
if (-not (Test-Path -LiteralPath $TimelineCsv -PathType Leaf)) {
    throw "Timeline dataset was not found: $TimelineCsv"
}

$requests = @(Import-Csv -LiteralPath $RequestsCsv)
$markers = @(Import-Csv -LiteralPath $TimelineCsv)
if ($requests.Count -eq 0) {
    throw 'The request dataset has no rows; timeline cannot be rendered.'
}

$chartWidth = 1400.0
$chartHeight = 620.0
$left = 95.0
$right = 35.0
$top = 45.0
$bottom = 95.0
$plotWidth = $chartWidth - $left - $right
$plotHeight = $chartHeight - $top - $bottom

$parsedRequests = foreach ($request in $requests) {
    [PSCustomObject]@{
        timestamp = [DateTimeOffset]::Parse($request.timestamp_utc)
        latency = [double]$request.latency_ms
        phase = $request.phase
        isError = [System.Convert]::ToBoolean($request.is_error)
    }
}
$parsedMarkers = foreach ($marker in $markers) {
    [PSCustomObject]@{
        timestamp = [DateTimeOffset]::Parse($marker.timestamp_utc)
        event = $marker.event
        scenario = $marker.scenario
    }
}

$start = ($parsedRequests.timestamp | Measure-Object -Minimum).Minimum
$endCandidates = @($parsedRequests.timestamp) + @($parsedMarkers.timestamp)
$end = ($endCandidates | Measure-Object -Maximum).Maximum
$durationSeconds = [Math]::Max(1.0, ($end - $start).TotalSeconds)
$maximumLatency = [Math]::Max(
    $LatencyThresholdMs * 1.15,
    (($parsedRequests.latency | Measure-Object -Maximum).Maximum * 1.10)
)

function ConvertTo-ChartX([DateTimeOffset] $Timestamp) {
    $left + ((($Timestamp - $start).TotalSeconds / $durationSeconds) * $plotWidth)
}

function ConvertTo-ChartY([double] $Latency) {
    $top + $plotHeight - (($Latency / $maximumLatency) * $plotHeight)
}

function ConvertTo-SvgText([string] $Text) {
    [System.Security.SecurityElement]::Escape($Text)
}

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$svg = [System.Text.StringBuilder]::new()
[void]$svg.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"1400`" height=`"620`" viewBox=`"0 0 1400 620`" role=`"img`" aria-label=`"Day 7 recovery timeline`">")
[void]$svg.AppendLine('<rect width="100%" height="100%" fill="#ffffff"/>')
[void]$svg.AppendLine('<style>text{font-family:Segoe UI,Arial,sans-serif;fill:#1f2937}.axis{stroke:#475569;stroke-width:1}.grid{stroke:#cbd5e1;stroke-width:1;stroke-dasharray:4 4}.marker{stroke-width:2;stroke-dasharray:6 4}.title{font-size:20px;font-weight:600}.label{font-size:12px}.small{font-size:10px}</style>')
[void]$svg.AppendLine('<text x="95" y="26" class="title">Day 7: controlled fault injection and recovery timeline</text>')

for ($index = 0; $index -le 5; $index++) {
    $latency = $maximumLatency * $index / 5.0
    $y = ConvertTo-ChartY $latency
    [void]$svg.AppendLine(("<line class=`"grid`" x1=`"{0:F2}`" y1=`"{1:F2}`" x2=`"{2:F2}`" y2=`"{1:F2}`"/>" -f $left, $y, ($left + $plotWidth)))
    [void]$svg.AppendLine(("<text x=`"{0:F2}`" y=`"{1:F2}`" class=`"label`" text-anchor=`"end`">{2:F0}</text>" -f ($left - 10), ($y + 4), $latency))
}

[void]$svg.AppendLine(("<line class=`"axis`" x1=`"{0:F2}`" y1=`"{1:F2}`" x2=`"{2:F2}`" y2=`"{1:F2}`"/>" -f $left, ($top + $plotHeight), ($left + $plotWidth)))
[void]$svg.AppendLine(("<line class=`"axis`" x1=`"{0:F2}`" y1=`"{1:F2}`" x2=`"{0:F2}`" y2=`"{2:F2}`"/>" -f $left, ($top + $plotHeight), $top))
[void]$svg.AppendLine(("<text x=`"20`" y=`"{0:F2}`" class=`"label`">latency, ms</text>" -f ($top + 10)))

$thresholdY = ConvertTo-ChartY $LatencyThresholdMs
[void]$svg.AppendLine(("<line x1=`"{0:F2}`" y1=`"{1:F2}`" x2=`"{2:F2}`" y2=`"{1:F2}`" stroke=`"#7c3aed`" stroke-width=`"2`" stroke-dasharray=`"8 4`"/>" -f $left, $thresholdY, ($left + $plotWidth)))
[void]$svg.AppendLine(("<text x=`"{0:F2}`" y=`"{1:F2}`" class=`"small`" fill=`"#7c3aed`">stable-latency threshold: {2:F0} ms</text>" -f ($left + 8), ($thresholdY - 6), $LatencyThresholdMs))

foreach ($request in $parsedRequests) {
    $x = ConvertTo-ChartX $request.timestamp
    $y = ConvertTo-ChartY $request.latency
    $colour = if ($request.isError) { '#dc2626' } elseif ($request.phase -like 'delay-*') { '#2563eb' } else { '#16a34a' }
    [void]$svg.AppendLine(("<circle cx=`"{0:F2}`" cy=`"{1:F2}`" r=`"4`" fill=`"{2}`"><title>{3}: {4:F0} ms</title></circle>" -f $x, $y, $colour, (ConvertTo-SvgText $request.phase), $request.latency))
}

$markerColours = @{
    'fault-injected' = '#dc2626'
    'network-restored' = '#2563eb'
    'half-open-probe' = '#d97706'
    'circuit-closed-observed' = '#16a34a'
    'stable-after-recovery' = '#7c3aed'
}
$markerNumber = 0
foreach ($marker in $parsedMarkers) {
    if (-not $markerColours.ContainsKey($marker.event)) {
        continue
    }
    $markerNumber++
    $x = ConvertTo-ChartX $marker.timestamp
    $colour = $markerColours[$marker.event]
    $labelY = $top + 16 + (($markerNumber % 3) * 13)
    $label = ConvertTo-SvgText ("$($marker.event): $($marker.scenario)")
    [void]$svg.AppendLine(("<line class=`"marker`" x1=`"{0:F2}`" y1=`"{1:F2}`" x2=`"{0:F2}`" y2=`"{2:F2}`" stroke=`"{3}`"/>" -f $x, $top, ($top + $plotHeight), $colour))
    [void]$svg.AppendLine(("<text x=`"{0:F2}`" y=`"{1:F2}`" class=`"small`" transform=`"rotate(-60 {0:F2} {1:F2})`">{2}</text>" -f ($x + 4), $labelY, $label))
}

for ($index = 0; $index -le 8; $index++) {
    $seconds = $durationSeconds * $index / 8.0
    $x = $left + ($seconds / $durationSeconds * $plotWidth)
    [void]$svg.AppendLine(("<line class=`"axis`" x1=`"{0:F2}`" y1=`"{1:F2}`" x2=`"{0:F2}`" y2=`"{2:F2}`"/>" -f $x, ($top + $plotHeight), ($top + $plotHeight + 5)))
    [void]$svg.AppendLine(("<text x=`"{0:F2}`" y=`"{1:F2}`" class=`"label`" text-anchor=`"middle`">{2:F0}s</text>" -f $x, ($top + $plotHeight + 23), $seconds))
}

[void]$svg.AppendLine(("<text x=`"{0:F2}`" y=`"{1:F2}`" class=`"label`">time since first baseline request</text>" -f ($left + $plotWidth / 2), ($chartHeight - 25)))
[void]$svg.AppendLine('<circle cx="100" cy="590" r="5" fill="#16a34a"/><text x="110" y="594" class="label">accepted</text><circle cx="230" cy="590" r="5" fill="#2563eb"/><text x="240" y="594" class="label">delay scenario</text><circle cx="395" cy="590" r="5" fill="#dc2626"/><text x="405" y="594" class="label">error / unavailable</text>')
[void]$svg.AppendLine('</svg>')

$outputDirectory = Split-Path -Parent $OutputSvg
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Set-Content -LiteralPath $OutputSvg -Value $svg.ToString() -Encoding utf8

[PSCustomObject]@{
    output = (Resolve-Path -LiteralPath $OutputSvg).Path
    request_points = $parsedRequests.Count
    marker_count = $parsedMarkers.Count
    latency_threshold_ms = $LatencyThresholdMs
} | ConvertTo-Json
