param (
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$vmName
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Set-AzContext -SubscriptionId $subscriptionId | Out-Null

# Get token
$token = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
$accessToken = if ($token.Token -is [securestring]) {
    [System.Net.NetworkCredential]::new("", $token.Token).Password
} else {
    $token.Token
}

# Get VM location
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction Stop
$location = $vm.Location

# Build URI SAFELY
$uriBuilder = [System.UriBuilder]::new(
    "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName"
)
$query = [System.Web.HttpUtility]::ParseQueryString("")
$query["api-version"] = "2025-04-01"
$uriBuilder.Query = $query.ToString()
$uri = $uriBuilder.Uri.AbsoluteUri

$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

$payload = @{
    location   = $location
    properties = @{
        resiliencyProfile = @{
            zoneMovement = @{
                isEnabled = $true
            }
        }
    }
} | ConvertTo-Json -Depth 10

Write-Output "Enabling resiliencyProfile.zoneMovement.isEnabled = true"
Invoke-WebRequest -Uri $uri -Method PATCH -Headers $headers -Body $payload | Out-Null

Start-Sleep -Seconds 5
Write-Output "Enablement request sent successfully."