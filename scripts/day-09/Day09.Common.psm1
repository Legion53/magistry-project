Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

function Get-Day09ProjectRoot {
    return $script:ProjectRoot
}

function Get-Day09DbPassword {
    if (($null -ne $env:DB_PASSWORD) -and (-not [string]::IsNullOrWhiteSpace($env:DB_PASSWORD))) {
        return $env:DB_PASSWORD
    }

    $envFile = Join-Path $script:ProjectRoot "infrastructure/.env"

    if (-not (Test-Path $envFile)) {
        throw "DB_PASSWORD is not set and infrastructure/.env was not found."
    }

    $line = Get-Content $envFile |
        Where-Object { $_ -match '^POSTGRES_PASSWORD=' } |
        Select-Object -First 1

    if ($null -eq $line) {
        throw "POSTGRES_PASSWORD was not found in infrastructure/.env."
    }

    $value = (($line -split '=', 2)[1]).Trim()

    if (($value.Length -ge 2) -and $value.StartsWith('"') -and $value.EndsWith('"')) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "POSTGRES_PASSWORD in infrastructure/.env is empty."
    }

    return $value
}

function Wait-Day09Http {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [int]$TimeoutSeconds = 90
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 3

            if (($response.StatusCode -ge 200) -and ($response.StatusCode -lt 500)) {
                return
            }
        }
        catch {
            # Keep polling until timeout.
        }

        Start-Sleep -Milliseconds 500
    }

    throw "Timeout waiting for $Uri"
}

function Wait-Day09Postgres {
    param(
        [int]$TimeoutSeconds = 90
    )

    Write-Host "Waiting for PostgreSQL..."

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        & docker exec thesis-postgres pg_isready -U thesis -d thesis_inventory *> $null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "PostgreSQL is ready."
            return
        }

        Start-Sleep -Seconds 1
    }

    throw "PostgreSQL did not become ready within $TimeoutSeconds seconds."
}

function Start-Day09Service {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$ServiceDirectory,
        [Parameter(Mandatory)] [string]$Profiles,
        [hashtable]$Environment = @{},
        [Parameter(Mandatory)] [string]$LogDirectory
    )

    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

    $mvnw = Join-Path $ServiceDirectory "mvnw.cmd"
    if (-not (Test-Path $mvnw)) {
        throw "Maven wrapper not found: $mvnw"
    }

    $oldValues = @{}
    foreach ($key in $Environment.Keys) {$oldValues[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
    }

    try {
        $stdout = Join-Path $LogDirectory "$Name.stdout.log"
        $stderr = Join-Path $LogDirectory "$Name.stderr.log"

        $cmdArgs = @(
            "/d", "/c",
            "`"$mvnw`" spring-boot:run -Dspring-boot.run.profiles=$Profiles"
        )

        $process = Start-Process `
            -FilePath "cmd.exe" `
            -ArgumentList $cmdArgs `
            -WorkingDirectory $ServiceDirectory `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru

        return [PSCustomObject]@{
            Name    = $Name
            Process = $process
            Stdout  = $stdout
            Stderr  = $stderr
        }
    } finally {
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $oldValues[$key], "Process")
        }
    }
}

function Stop-Day09ProcessTree {
    param(
        $Handle
    )

    if ($null -eq $Handle) {
        return
    }

    if ($null -eq $Handle.Process) {
        return
    }

    $process = Get-Process -Id $Handle.Process.Id -ErrorAction SilentlyContinue

    if ($null -eq $process) {
        return
    }

    & taskkill.exe /PID $process.Id /T /F | Out-Null
    Start-Sleep -Seconds 2
}

function Clear-Day09GatlingReports {
    $directory = Join-Path $script:ProjectRoot "load-tests/target/gatling"

    if (Test-Path $directory) {
        Remove-Item -Path $directory -Recurse -Force
    }
}

function Start-Day09Gatling {
    param(
        [Parameter(Mandatory)] [string]$SimulationClass,
        [hashtable]$Properties = @{},
        [Parameter(Mandatory)] [string]$LogDirectory,
        [Parameter(Mandatory)] [string]$RunName
    )

    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

    $mvnw = Join-Path $script:ProjectRoot "order-service\mvnw.cmd"
    $pom = Join-Path $script:ProjectRoot "load-tests\pom.xml"

    $argsList = [System.Collections.Generic.List[string]]::new()
    $argsList.Add("-B")
    $argsList.Add("-ntp")
    $argsList.Add("-f")
    $argsList.Add($pom)
    $argsList.Add("-Dgatling.simulationClass=$SimulationClass")

    $sortedKeys = $Properties.Keys | Sort-Object
    foreach ($key in $sortedKeys) {
        $val = $Properties[$key]
        $argsList.Add("-D$key=$val")
    }

    $argsList.Add("gatling:test")

    $stdout = Join-Path $LogDirectory "$RunName.gatling.stdout.log"
    $stderr = Join-Path $LogDirectory "$RunName.gatling.stderr.log"

    $process = Start-Process `
        -FilePath $mvnw `
        -ArgumentList $argsList `
        -WorkingDirectory $script:ProjectRoot `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    return [PSCustomObject]@{
        Process = $process
        Stdout  = $stdout
        Stderr  = $stderr
    }
}

function Wait-Day09Process {
    param([Parameter(Mandatory)] $Handle)

    $Handle.Process.WaitForExit()
    $Handle.Process.Refresh()

    $code = $Handle.Process.ExitCode
    if ($null -ne $code -and $code -ne 0) {
        throw "Process failed with exit code $code. See $($Handle.Stderr)"
    }
}

function Wait-Day09Marker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [int]$TimeoutSeconds = 600
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if (Test-Path $Path) {
            $raw = (Get-Content -Path $Path -Raw).Trim()

            return [DateTimeOffset]::Parse(
                $raw,
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }

        Start-Sleep -Milliseconds 100
    }

    throw "Marker was not created: $Path"
}

function Wait-Day09Until {
    param(
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$Utc
    )

    while ($true) {
        $remaining = $Utc - [DateTimeOffset]::UtcNow

        if ($remaining.TotalMilliseconds -le 0) {
            return
        }

        $sleep = [Math]::Min(
            250,
            [Math]::Max(20, $remaining.TotalMilliseconds)
        )

        Start-Sleep -Milliseconds ([int]$sleep)
    }
}

function Save-Day09Snapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $content = (Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 10).Content

    [System.IO.File]::WriteAllText(
        $Path,
        $content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Start-Day09Sampler {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("order", "inventory", "both")]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$StopFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputCsv
    )

    if (Test-Path $StopFile) {
        Remove-Item -Force $StopFile
    }

    if (Test-Path $OutputCsv) {
        Remove-Item -Force $OutputCsv
    }

    $scriptPath =
        Join-Path $PSScriptRoot "Sample-Metrics.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Metrics sampler script not found: $scriptPath"
    }

    $outputDirectory =
        Split-Path -Parent $OutputCsv

    if (-not (Test-Path $outputDirectory)) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path $outputDirectory |
            Out-Null
    }

    $stdout =
        Join-Path $outputDirectory "sampler.stdout.log"

    $stderr =
        Join-Path $outputDirectory "sampler.stderr.log"

    Remove-Item `
        $stdout, `
        $stderr `
        -Force `
        -ErrorAction SilentlyContinue

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$scriptPath`"",
        "-Mode",
        $Mode,
        "-StopFile",
        "`"$StopFile`"",
        "-OutputCsv",
        "`"$OutputCsv`"",
        "-IntervalSeconds",
        "1"
    )

    $process =
        Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $arguments `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru

    $startupDeadline =
    [DateTimeOffset]::UtcNow.AddSeconds(10)

while ([DateTimeOffset]::UtcNow -lt $startupDeadline) {

    $process.Refresh()

    if ($process.HasExited) {

        $errorText = ""

        if (Test-Path $stderr) {
            $errorText =
                Get-Content `
                    -Path $stderr `
                    -Raw
        }

        throw (
            "Metrics sampler terminated during startup. " +
            "ExitCode=$($process.ExitCode)." +
            [Environment]::NewLine +
            "stderr: $stderr" +
            [Environment]::NewLine +
            $errorText
        )
    }

    if (Test-Path $OutputCsv) {
        return $process
    }

    Start-Sleep -Milliseconds 100
}

# Sampler is still alive, but did not create its output file
New-Item `
    -ItemType File `
    -Force `
    -Path $StopFile |
    Out-Null

if (-not $process.WaitForExit(5000)) {
    & taskkill.exe `
        /PID $process.Id `
        /T `
        /F |
        Out-Null
}

$errorText = ""

if (Test-Path $stderr) {
    $errorText =
        Get-Content `
            -Path $stderr `
            -Raw
}

throw (
    "Metrics sampler remained alive but did not create output CSV within 10 seconds: " +
    $OutputCsv +
    [Environment]::NewLine +
    "stderr: $stderr" +
    [Environment]::NewLine +
    $errorText
)
}

function Stop-Day09Sampler {
    param(
        $Process,

        [Parameter(Mandatory = $true)]
        [string]$StopFile
    )

    New-Item -ItemType File -Force -Path $StopFile | Out-Null

    if ($null -eq $Process) {
        return
    }

    if (-not $Process.WaitForExit(10000)) {
        & taskkill.exe /PID $Process.Id /T /F | Out-Null
    }
}

function Invoke-Day09ComposeUp {
    $compose = Join-Path $script:ProjectRoot "infrastructure/compose.yaml"

    & docker compose -f $compose up -d

    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed."
    }
}

function Initialize-Day09Toxiproxy {
    $scriptPath = Join-Path $script:ProjectRoot "scripts/day-07/Initialize-Toxiproxy.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Toxiproxy initialization script not found: $scriptPath"
    }

    & $scriptPath -StartContainer
}

function Set-Day09ToxiproxyScenario {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "normal",
            "delay-100",
            "delay-500",
            "delay-1000",
            "connection-reset",
            "downstream-unavailable"
        )]
        [string]$Scenario
    )

    $scriptPath = Join-Path $script:ProjectRoot "scripts/day-07/Set-ToxiproxyFault.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Toxiproxy scenario script not found: $scriptPath"
    }

    & $scriptPath -Scenario $Scenario
}

function Copy-Day09GatlingReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $sourceRoot = Join-Path $script:ProjectRoot "load-tests/target/gatling"

    if (-not (Test-Path $sourceRoot)) {
        throw "Gatling report directory was not found: $sourceRoot"
    }

    $latest = Get-ChildItem -Path $sourceRoot -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "Gatling report was not found."
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Copy-Item `
        -Path (Join-Path $latest.FullName "*") `
        -Destination $Destination `
        -Recurse `
        -Force
}

function Save-Day09Url {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $content = (Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 10).Content
        $directory = Split-Path -Parent $Path

        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            New-Item -ItemType Directory -Force -Path $directory | Out-Null
        }

        Set-Content -Path $Path -Value $content -Encoding UTF8
    }
    catch {
        Write-Warning "Could not save $Uri : $($_.Exception.Message)"
    }
}

function Save-Day09Json {
    param(
        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $Value |
        ConvertTo-Json -Depth 10 |
        Set-Content -Path $Path -Encoding UTF8
}

function Assert-Day09PortFree {
    param(
        [Parameter(Mandatory)]
        [int]$Port
    )

    $connection =
        Get-NetTCPConnection `
            -LocalPort $Port `
            -State Listen `
            -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -ne $connection) {

        $processInfo =
            Get-Process `
                -Id $connection.OwningProcess `
                -ErrorAction SilentlyContinue

        $processName =
            if ($null -ne $processInfo) {
                $processInfo.ProcessName
            }
            else {
                "unknown"
            }

        throw (
            "Port $Port is already in use. " +
            "PID=$($connection.OwningProcess), " +
            "Process=$processName. " +
            "Stop the existing service before running Day 09."
        )
    }
}

function Wait-Day09Service {
    param(
        [Parameter(Mandatory)]
        $Handle,

        [Parameter(Mandatory)]
        [string]$Uri,

        [int]$TimeoutSeconds = 90
    )

    $deadline =
        [DateTimeOffset]::UtcNow.AddSeconds(
            $TimeoutSeconds
        )

    while ([DateTimeOffset]::UtcNow -lt $deadline) {

        $Handle.Process.Refresh()

        if ($Handle.Process.HasExited) {

            $errorText = ""

            if (Test-Path $Handle.Stderr) {
                $errorText =
                    Get-Content `
                        -Path $Handle.Stderr `
                        -Raw
            }

            throw (
                "$($Handle.Name) terminated during startup. " +
                "ExitCode=$($Handle.Process.ExitCode)." +
                [Environment]::NewLine +
                "stderr: $($Handle.Stderr)" +
                [Environment]::NewLine +
                $errorText
            )
        }

        try {
            $response =
                Invoke-WebRequest `
                    -UseBasicParsing `
                    -Uri $Uri `
                    -TimeoutSec 3

            if (
                $response.StatusCode -ge 200 -and
                $response.StatusCode -lt 500
            ) {
                return
            }
        }
        catch {
            # Continue polling.
        }

        Start-Sleep -Milliseconds 500
    }

    throw "Timeout waiting for $Uri"
}

Export-ModuleMember -Function @(
    "Get-Day09ProjectRoot",
    "Get-Day09DbPassword",
    "Wait-Day09Http",
    "Wait-Day09Postgres",
    "Start-Day09Service",
    "Stop-Day09ProcessTree",
    "Clear-Day09GatlingReports",
    "Start-Day09Gatling",
    "Wait-Day09Process",
    "Wait-Day09Marker",
    "Wait-Day09Until",
    "Save-Day09Snapshot",
    "Start-Day09Sampler",
    "Stop-Day09Sampler",
    "Invoke-Day09ComposeUp",
    "Initialize-Day09Toxiproxy",
    "Set-Day09ToxiproxyScenario",
    "Copy-Day09GatlingReport",
    "Save-Day09Url",
    "Save-Day09Json",
    "Assert-Day09PortFree",
    "Wait-Day09Service"
)
