param (
    [Parameter(Mandatory=$true)]
    [string]$subscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$vmName,

    [Parameter(Mandatory=$true)]
    [string]$targetZone,

    [Parameter(Mandatory=$false)]
    [string]$newNetworkResourceId,

    [Parameter(Mandatory=$false)]
    [string]$authMode
)

$ErrorActionPreference = "Stop"
function UpdateZone {
    param (
        [Parameter(Mandatory=$true)]
        [string]$subscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$vmName,

        [Parameter(Mandatory=$true)]
        [string]$targetZone,

        [Parameter(Mandatory=$true)]
        [string]$token,

        [string]$newNetworkProfile
    )

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName`?api-version=2024-07-01"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    $body = [PSCustomObject]@{
        "zones" = @($targetZone)
    }

    if ($null -ne $newNetworkProfile -and -not [string]::IsNullOrEmpty($newNetworkProfile)) {
        $networkProfileObject = $newNetworkProfile | ConvertFrom-Json
        $properties = [PSCustomObject]@{
            "networkProfile" = $networkProfileObject
        }
        $body | Add-Member -MemberType NoteProperty -Name "properties" -Value $properties
    }

    $body = $body | ConvertTo-Json -Depth 10
    Write-Output "request payload: $body"

    InvokeAzureApiAndPollForCompletion -uri $uri -method "PATCH" -headers $headers -payload $body 
}

function ForceDeallocate {
    param (
        [Parameter(Mandatory=$true)]
        [string]$subscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$vmName,

        [Parameter(Mandatory=$true)]
        [string]$token
    )
    
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/deallocate`?api-version=2024-07-01&forceDeallocate=true"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    InvokeAzureApiAndPollForCompletion -uri $uri -method "POST" -headers $headers
}

function StartVM {
    param (
        [Parameter(Mandatory=$true)]
        [string]$subscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$vmName,

        [Parameter(Mandatory=$true)]
        [string]$token
    )

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/start`?api-version=2024-07-01"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    InvokeAzureApiAndPollForCompletion -uri $uri -method "POST" -headers $headers
}

function PollForCompletion {
    param (
        [Parameter(Mandatory=$true)]
        [string]$asyncOperationUrl,

        [Parameter(Mandatory=$true)]
        [string]$token
    )

    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    $counter = 0
    $upperCircuit = 400
    while ($counter -lt $upperCircuit) {
        $response = Invoke-WebRequest -Uri $asyncOperationUrl -Headers $headers
        $statusCode = $response.StatusCode
        if ($statusCode -eq 200) {
            $responsePayload = $response.Content | ConvertFrom-Json
            $operationStatus = $responsePayload.status
            Write-Output "Operation status $operationStatus"
            if ($operationStatus -eq "Succeeded") {
                break
            }
            Write-Output "Waiting 20 seconds"
            Start-Sleep -Seconds 20
        }
        else {
            throw "GET operation failed with $statusCode"
        }
        $counter++
    }

    if ($counter -eq $upperCircuit) {
        throw "Operation timed out"
    }
}

function InvokeAzureApiAndPollForCompletion {
    param (
        [Parameter(Mandatory=$true)]
        [string]$uri,

        [Parameter(Mandatory=$true)]
        [string]$method,

        [Parameter(Mandatory=$true)]
        [object]$headers,

        [object]$payload
    )

    Write-Output "Invoking $method : $uri"
    $response = Invoke-WebRequest -Uri $uri -Method $method -Headers $headers -Body $body
    $statusCode = $response.StatusCode
    if ($statusCode -eq 200 -or $statusCode -eq 202) {
        $asyncHeader = $response.Headers["azure-asyncOperation"]
        Write-Output "Status Code: $statusCode"
        if ($null -ne $asyncHeader) {
            $asyncOperationUrl = "$asyncHeader"
            Write-Output "Polling for operation completion. Async header: $asyncHeader."
            PollForCompletion -asyncOperationUrl $asyncOperationUrl -token $token
        }
    } else {
        throw "azure api $method : $uri failed with $statusCode"
    }
}

#TODO 1: Only continue execution if zone or network profile actually needs to be changed

if ($newNetworkResourceId) {
    $networkProfile = @{
        "networkInterfaces" = @(
            @{
                "id" = $newNetworkResourceId
                "properties" = @{
                    "deleteOption" = "Detach"
                }
            }
        )
    }
    $networkProfile = $networkProfile | ConvertTo-Json -Depth 5
} else {$networkProfile = $null}


# --- Make script non-interactive & fail-fast ---
$ErrorActionPreference = 'Stop'                    # treat errors as fatal
$ConfirmPreference     = 'None'                    # suppress Confirm prompts globally
$ProgressPreference    = 'SilentlyContinue'        # hide progress bars
$InformationPreference = 'SilentlyContinue'        # suppress informational messages
$WarningPreference     = 'Continue'                # show warnings but don't block

# --- Default parameter values for all cmdlets ---
$PSDefaultParameterValues = @{
    '*:Confirm'          = $false                  # equivalent to -Confirm:$false
    '*:Verbose'          = $false
    '*:ErrorAction'      = 'Stop'                  # consistent error semantics
    'Start-Process:Wait' = $true                   # avoid race conditions
}

if ($authMode -eq "DeviceAuthentication") {
    Connect-AzAccount -SubscriptionId $subscriptionId -UseDeviceAuthentication
}
else {
    Connect-AzAccount -SubscriptionId $subscriptionId
}


# --------------------------
# Get access token
# --------------------------
try {
    # Note: ResourceUrl must have trailing slash for Cloud Shell compatibility
    $token = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
    # Handle both string and SecureString token types
    if ($token.Token -is [System.Security.SecureString]) {
        $accessToken = [System.Net.NetworkCredential]::new('', $token.Token).Password
    }
    else {
        $accessToken = $token.Token
    }
}
catch {
    Write-Error "Failed to get access token: $_"
    exit 1
}

Write-Output "Stopping the VM."
ForceDeallocate -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -vmName $vmName -token $accessToken
Write-Output "Updating zone"
UpdateZone -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -vmName $vmName -targetZone $targetZone -token $accessToken -newNetworkProfile $networkProfile
Write-Output "Starting the VM"
StartVM -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -vmName $vmName -token $accessToken
