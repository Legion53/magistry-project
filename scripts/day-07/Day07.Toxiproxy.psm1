Set-StrictMode -Version Latest

$script:ToxiproxyApiUrl = "http://localhost:8474"
$script:Day07ProxyName = "inventory-service"
$script:Day07ProxyListen = "0.0.0.0:8666"
$script:Day07ProxyUpstream = "host.docker.internal:8081"
$script:Day07ToxicPrefix = "day7-"


function Get-ToxiproxyApiUrl {
    return $script:ToxiproxyApiUrl
}


function Get-Day07ProxyName {
    return $script:Day07ProxyName
}


function Invoke-ToxiproxyApi {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GET", "POST", "DELETE")]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [object]$Body
    )

    $uri = "$($script:ToxiproxyApiUrl)$Path"

    $params = @{
        Method      = $Method
        Uri         = $uri
        ErrorAction = "Stop"
        Headers     = @{
            "User-Agent" = "Day07-Toxiproxy-Initializer"
        }
    }

    if ($null -ne $Body) {
        $params["ContentType"] = "application/json"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
    }

    return Invoke-RestMethod @params
}


function Test-Toxiproxy {

    try {
        $response = Invoke-RestMethod `
            -Uri "$($script:ToxiproxyApiUrl)/version" `
            -Method Get `
            -TimeoutSec 5 `
            -Headers @{
                "User-Agent" = "Day07-Toxiproxy-Initializer"
            } `
            -ErrorAction Stop

        return $null -ne $response.version
    }
    catch {
        return $false
    }
}


function Get-Day07Proxy {
    return Invoke-ToxiproxyApi `
        -Method GET `
        -Path "/proxies/$($script:Day07ProxyName)"
}


function New-Day07Proxy {
    $existing = $null

    try {
        $existing = Get-Day07Proxy
    }
    catch {
        # Proxy does not exist.
    }

    if ($null -ne $existing) {
        Write-Host "Proxy '$($script:Day07ProxyName)' already exists."

        return $existing
    }

    $body = @{
        name     = $script:Day07ProxyName
        listen   = $script:Day07ProxyListen
        upstream = $script:Day07ProxyUpstream
        enabled  = $true
    }

    $proxy = Invoke-ToxiproxyApi `
        -Method POST `
        -Path "/proxies" `
        -Body $body

    Write-Host "Created proxy '$($script:Day07ProxyName)'."

    return $proxy
}


function Enable-Day07InventoryProxy {
    param(
        [bool]$Enabled
    )

    $body = @{
        name     = $script:Day07ProxyName
        listen   = $script:Day07ProxyListen
        upstream = $script:Day07ProxyUpstream
        enabled  = $Enabled
    }

    $proxy = Invoke-ToxiproxyApi `
        -Method POST `
        -Path "/proxies/$($script:Day07ProxyName)" `
        -Body $body

    if ($Enabled) {
        Write-Host "Proxy '$($script:Day07ProxyName)' ENABLED."
    }
    else {
        Write-Host "Proxy '$($script:Day07ProxyName)' DISABLED."
    }

    return $proxy
}


function Get-Day07Toxics {
    return Invoke-ToxiproxyApi `
        -Method GET `
        -Path "/proxies/$($script:Day07ProxyName)/toxics"
}


function Clear-Day07Toxics {

    $toxics = Get-Day07Toxics

    foreach ($toxic in $toxics) {

        if ($toxic.name.StartsWith($script:Day07ToxicPrefix)) {

            Write-Host "Removing toxic '$($toxic.name)'..."

            Invoke-ToxiproxyApi `
                -Method DELETE `
                -Path "/proxies/$($script:Day07ProxyName)/toxics/$($toxic.name)" |
                Out-Null
        }
    }
}


function Add-Day07Toxic {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Type,

        [string]$Stream = "downstream",

        [hashtable]$Attributes = @{}
    )

    $body = @{
        name       = "$($script:Day07ToxicPrefix)$Name"
        type       = $Type
        stream     = $Stream
        toxicity   = 1.0
        attributes = $Attributes
    }

    $result = Invoke-ToxiproxyApi `
        -Method POST `
        -Path "/proxies/$($script:Day07ProxyName)/toxics" `
        -Body $body

    Write-Host "Added toxic '$($body.name)' ($Type, toxicity=1.0)."

    return $result
}


function Set-Day07Latency {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(100, 500, 1000)]
        [int]$Milliseconds
    )

    Clear-Day07Toxics

    Add-Day07Toxic `
        -Name "latency-$Milliseconds" `
        -Type "latency" `
        -Stream "downstream" `
        -Attributes @{
            latency = $Milliseconds
            jitter  = 0
        }

    Enable-Day07InventoryProxy -Enabled $true | Out-Null

    Write-Host ""
    Write-Host "DAY 7 FAULT: latency +$Milliseconds ms"
}


function Set-Day07ConnectionReset {

    Clear-Day07Toxics

    Add-Day07Toxic `
        -Name "reset-peer" `
        -Type "reset_peer" `
        -Stream "downstream" `
        -Attributes @{
            timeout = 0
        }

    Enable-Day07InventoryProxy -Enabled $true | Out-Null

    Write-Host ""
    Write-Host "DAY 7 FAULT: connection reset"
}


function Set-Day07DownstreamUnavailable {

    Clear-Day07Toxics

    Enable-Day07InventoryProxy -Enabled $false | Out-Null

    Write-Host ""
    Write-Host "DAY 7 FAULT: downstream unavailable"
}


function Restore-Day07Network {

    Clear-Day07Toxics

    Enable-Day07InventoryProxy -Enabled $true | Out-Null

    Write-Host ""
    Write-Host "DAY 7 NETWORK: RESTORED"
}


function Get-Day07State {

    $proxy = Get-Day07Proxy

    [PSCustomObject]@{
        Name     = $proxy.name
        Listen   = $proxy.listen
        Upstream = $proxy.upstream
        Enabled  = $proxy.enabled
        Toxics   = @(
            $proxy.toxics | ForEach-Object {
                "$($_.name):$($_.type):toxicity=$($_.toxicity)"
            }
        ) -join "; "
    }
}


Export-ModuleMember -Function @(
    "Get-ToxiproxyApiUrl",
    "Get-Day07ProxyName",
    "Test-Toxiproxy",
    "Get-Day07Proxy",
    "New-Day07Proxy",
    "Enable-Day07InventoryProxy",
    "Get-Day07Toxics",
    "Clear-Day07Toxics",
    "Set-Day07Latency",
    "Set-Day07ConnectionReset",
    "Set-Day07DownstreamUnavailable",
    "Restore-Day07Network",
    "Get-Day07State"
)