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

# --- Make script non-interactive & fail-fast ---
$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$WarningPreference = 'Continue'
$PSDefaultParameterValues = @{
    '*:Confirm' = $false
    '*:Verbose' = $false
    '*:ErrorAction' = 'Stop'
}

function PollForCompletion {
    param (
        [Parameter(Mandatory=$true)]
        [string]$asyncOperationUrl,

        [Parameter(Mandatory=$true)]
        [string]$accessToken
    )

    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    $counter = 0
    $upperCircuit = 400 # ~400 * 20s = ~2h 13m upper bound
    while ($counter -lt $upperCircuit) {
        $response = Invoke-WebRequest -Uri $asyncOperationUrl -Headers $headers
        if ($response.StatusCode -eq 200) {
            $responsePayload = $response.Content | ConvertFrom-Json
            $operationStatus = $responsePayload.status
            Write-Output "Operation status: $operationStatus"
            if ($operationStatus -eq "Succeeded") { return }
            if ($operationStatus -eq "Failed") { throw "Async operation failed: $($response.Content)" }
            Write-Output "Waiting 20 seconds..."
            Start-Sleep -Seconds 20
        }
        else {
            throw "GET async operation failed with status code $($response.StatusCode). Payload: $($response.Content)"
        }
        $counter++
    }
    throw "Operation timed out after polling. Last response: $($response.Content)"
}

function InvokeAzureApiAndPollForCompletion {
    param (
        [Parameter(Mandatory=$true)]
        [string]$uri,

        [Parameter(Mandatory=$true)]
        [string]$method,

        [Parameter(Mandatory=$true)]
        [hashtable]$headers,

        [Parameter(Mandatory=$false)]
        [string]$payload,

        [Parameter(Mandatory=$true)]
        [string]$accessToken
    )

    Write-Output "Invoking $method : $uri"
    if ($null -ne $payload -and -not [string]::IsNullOrEmpty($payload)) {
        $response = Invoke-WebRequest -Uri $uri -Method $method -Headers $headers -Body $payload
    } else {
        $response = Invoke-WebRequest -Uri $uri -Method $method -Headers $headers
    }

    $statusCode = $response.StatusCode
    Write-Output "Status Code: $statusCode"

    if ($statusCode -eq 200 -or $statusCode -eq 202) {
        $asyncHeader = $response.Headers["azure-asyncOperation"]
        if ($null -ne $asyncHeader -and -not [string]::IsNullOrEmpty($asyncHeader)) {
            Write-Output "Polling for operation completion. Async header: $asyncHeader"
            PollForCompletion -asyncOperationUrl "$asyncHeader" -accessToken $accessToken
        }
        return
    }

    throw "Azure API $method : $uri failed with status code $statusCode. Payload: $($response.Content)"
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
        [string]$accessToken
    )

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/deallocate`?api-version=2024-07-01&forceDeallocate=true"
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    InvokeAzureApiAndPollForCompletion -uri $uri -method "POST" -headers $headers -payload $null -accessToken $accessToken
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
        [string]$accessToken
    )

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/start`?api-version=2024-07-01"
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    InvokeAzureApiAndPollForCompletion -uri $uri -method "POST" -headers $headers -payload $null -accessToken $accessToken
}

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
        [string]$accessToken,

        [Parameter(Mandatory=$false)]
        [string]$newNetworkProfile
    )

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName`?api-version=2024-07-01"
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    # (Optional but safer) include location in request.
    # If Get-AzVM fails for any reason, fall back to not sending location.
    $location = $null
    try {
        $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction Stop
        $location = $vm.Location
    } catch { }

    $bodyObj = [ordered]@{
        zones = @("$targetZone")
    }

    if ($location) {
        $bodyObj["location"] = $location
        $bodyObj["name"] = $vmName
    }

    if ($null -ne $newNetworkProfile -and -not [string]::IsNullOrEmpty($newNetworkProfile)) {
        $networkProfileObject = $newNetworkProfile | ConvertFrom-Json
        $bodyObj["properties"] = @{
            networkProfile = $networkProfileObject
        }
    }

    $payload = $bodyObj | ConvertTo-Json -Depth 20
    Write-Output "request payload: $payload"
    InvokeAzureApiAndPollForCompletion -uri $uri -method "PATCH" -headers $headers -payload $payload -accessToken $accessToken
}

# --------------------------
# NEW: Enable resiliencyProfile.zoneMovement.isEnabled = true (added above fast path)
# --------------------------
function EnableZoneMovement {
    param (
        [Parameter(Mandatory=$true)]
        [string]$subscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$vmName,

        [Parameter(Mandatory=$true)]
        [string]$accessToken
    )

    # Enablement payload must be:
    # { "location": "<region>", "properties": { "resiliencyProfile": { "zoneMovement": { "isEnabled": true }}}}
    # as described in internal docs/specs. [1](https://microsoft.sharepoint.com/teams/AzureIDC/AzureIDC_CRP/_layouts/15/Doc.aspx?sourcedoc=%7B2FA35BE4-0ADB-40D3-828A-9962D278E8B0%7D&file=Resilient%20VM.docx&action=default&mobileredirect=true&DefaultItemOpen=1)[2](https://microsoftapc.sharepoint.com/teams/AzureCoreIDC/_layouts/15/Doc.aspx?sourcedoc=%7BA4D9052D-F4F2-4FCE-B7EC-4B40E69E0E76%7D&file=Zone-Resilient-VMs-ZR-components-PM-Spec.docx&action=default&mobileredirect=true&DefaultItemOpen=1)[3](https://microsoftapc.sharepoint.com/teams/AzureCoreIDC/_layouts/15/Doc.aspx?sourcedoc=%7B91763990-DD92-414A-AFCA-9AC029895801%7D&file=Private-preview-Enable-Zone-Movement-of-VMs.docx&action=default&mobileredirect=true&DefaultItemOpen=1)
    $location = (Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction Stop).Location

    # IMPORTANT: Keep your existing fast-path API versions unchanged (2024-07-01) for deallocate/update/start.
    # For enablement, we use the API version that supports resiliencyProfile payload.
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName`?api-version=2025-04-01"
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type"  = "application/json"
    }

    $bodyObj = [ordered]@{
        location   = $location
        properties = @{
            resiliencyProfile = @{
                zoneMovement = @{
                    isEnabled = $true
                }
            }
        }
    }

    $payload = $bodyObj | ConvertTo-Json -Depth 20
    Write-Output "Enabling zoneMovement (resiliencyProfile) payload: $payload"

    # NOTE: We do NOT alter your fast path logic below.
    # We keep enablement lightweight: fire request and proceed.
    # If ARM returns async header, we do a short bounded poll (max ~2 mins) and continue regardless.
    Write-Output "Invoking PATCH : $uri"
    $response = Invoke-WebRequest -Uri $uri -Method PATCH -Headers $headers -Body $payload
    Write-Output "Status Code: $($response.StatusCode)"

    $asyncHeader = $response.Headers["azure-asyncOperation"]
    if ($null -ne $asyncHeader -and -not [string]::IsNullOrEmpty($asyncHeader)) {
        Write-Output "Enablement returned async header. Soft waiting briefly before continuing..."
        # Soft wait: 6 polls * 20s = ~2 mins max, then continue (to preserve fast-path behavior)
        $softCounter = 0
        while ($softCounter -lt 6) {
            $pollResp = Invoke-WebRequest -Uri "$asyncHeader" -Headers @{ "Authorization" = "Bearer $accessToken"; "Content-Type" = "application/json" }
            if ($pollResp.StatusCode -eq 200) {
                $pollPayload = $pollResp.Content | ConvertFrom-Json
                Write-Output "Enablement status: $($pollPayload.status)"
                if ($pollPayload.status -eq "Succeeded") { break }
                if ($pollPayload.status -eq "Failed") { throw "Enablement failed: $($pollResp.Content)" }
            }
            Start-Sleep -Seconds 20
            $softCounter++
        }
        Write-Output "Continuing to fast-path operations..."
    } else {
        # tiny pause to let CRP persist goal state
        Start-Sleep -Seconds 5
    }
}

# Build network profile if newNetworkResourceId is supplied
$networkProfile = $null
if ($newNetworkResourceId) {
    $networkProfileObj = @{
        "networkInterfaces" = @(
            @{
                "id" = $newNetworkResourceId
                "properties" = @{
                    "deleteOption" = "Detach"
                }
            }
        )
    }
    $networkProfile = $networkProfileObj | ConvertTo-Json -Depth 10
}

# --------------------------
# Auth / Context (unchanged from your baseline)
# --------------------------
$inCloudShell = ($env:ACC_CLOUD -eq "AzureCloudShell") -or ($env:AZUREPS_HOST_ENVIRONMENT -like "*CloudShell*")
if (-not $inCloudShell) {
    if ($authMode -eq "DeviceAuthentication") {
        Connect-AzAccount -UseDeviceAuthentication
    } else {
        Connect-AzAccount
    }
}
Set-AzContext -SubscriptionId $subscriptionId | Out-Null

# --------------------------
# Get access token (same as baseline)
# --------------------------
try {
    # Note: ResourceUrl must have trailing slash for Cloud Shell compatibility
    $token = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
    # Handle both string and SecureString token types
    if ($token.Token -is [System.Security.SecureString]) {
        $accessToken = [System.Net.NetworkCredential]::new('', $token.Token).Password
    } else {
        $accessToken = $token.Token
    }
}
catch {
    Write-Error "Failed to get access token: $_"
    exit 1
}

# --------------------------
# NEW STEP (above fast path): enable resiliencyProfile.zoneMovement
# --------------------------
Write-Output "Enabling VM resiliencyProfile.zoneMovement.isEnabled = true"
EnableZoneMovement -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -vmName $vmName -accessToken $accessToken

# --------------------------
# Execute fast path (UNCHANGED): deallocate -> patch zone -> start
# --------------------------
Write-Output "Stopping the VM."
ForceDeallocate -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -vmName $vmName -accessToken $accessToken

Write-Output "Updating zone"
UpdateZone -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -vmName $vmName -targetZone $targetZone -accessToken $accessToken -newNetworkProfile $networkProfile

Write-Output "Starting the VM"
StartVM -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -vmName $vmName -accessToken $accessToken
