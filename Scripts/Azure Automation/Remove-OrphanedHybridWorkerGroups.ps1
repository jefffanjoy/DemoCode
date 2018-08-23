Param (
    [Parameter(Mandatory=$true)]
    [String] $SubscriptionId,
    [Parameter(Mandatory=$true)]
    [String] $ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [String] $AutomationAccountName,
    [Parameter(Mandatory=$false)]
    [ValidateSet('AzureCloud','AzureUSGovernment')]
    [Alias('EnvironmentName')]
    [string] $Environment = 'AzureCloud',
    [Parameter(Mandatory=$false)]
    [int] $DaysSinceLastSeen = 30,
    [Parameter(Mandatory=$false)]
    [switch] $WhatIf
)

    Function GetAzureAccessToken {
        Param ()

        $context = Get-AzureRmContext
        $token = ($context.TokenCache.ReadItems() | Sort-Object ExpiresOn | Where-Object { (($_.TenantId -eq $context.Tenant.Id) -and ($_.DisplayableId -eq $context.Account.Id)) })[-1]
        if (($token.ExpiresOn.UtcDateTime.AddMinutes(-5)) -le ((Get-Date).ToUniversalTime())) {
            Write-Host ("Executing benign PowerShell statement in an attempt to refresh access token.")
            $null = Get-AzureRmSubscription
            $token = ($context.TokenCache.ReadItems() | Sort-Object ExpiresOn | Where-Object { (($_.TenantId -eq $context.Tenant.Id) -and ($_.DisplayableId -eq $context.Account.Id)) })[-1]
        }
        $token.AccessToken
    }

    Function GetAuthorizationHeader {
        Param ()

        $AccessToken = GetAzureAccessToken
        ("Bearer {0}" -f $AccessToken)
    }

    Function BuildHeaders {
        Param ()

        @{
            Authorization = GetAuthorizationHeader
        }
    }

    Function GetOrphanedHybridWorkerGroups {
        $currentTime = Get-Date
        $currentTimeUTC = $currentTime.ToUniversalTime()
        Write-Host ("Current Time: {0} ({1} UTC)" -f $currentTime, $currentTimeUTC)
        Write-Host ("Retrieving list of hybrid worker groups registered in Automation account '{0}'." -f $AutomationAccountName)
        $Uri = ("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Automation/automationAccounts/{3}/hybridRunbookWorkerGroups?api-version=2015-10-31" -f $AzureManagementBaseUri, $SubscriptionId, $ResourceGroupName, $AutomationAccountName)
        $HWGList = @()
        do {
            try {
                Write-Host ("Retrieving Hybrid Worker data from '{0}'." -f $Uri)
                $results = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
                Write-Host ("Data successfully retrieved from {0}" -f $Uri)
                Write-Host ("Next link: {0}" -f $results.nextLink)
                $HWGList += $results.value
                $Uri = $results.nextlink
            } catch {
                if ($_.Exception.Message -like '*ResourceCollectionRequestsThrottled*') {
                    Write-Host ("Encountered resource throttling.  Sleeping for 60 seconds.")
                    Start-Sleep -Second 60
                } else {
                    Write-Error -Exception $_
                }
            }
        } until (!$Uri)
        $OrphanedHWG = @()
        foreach ($HWG in $HWGList) {
            # If there are no workers in the group, then consider the group orphaned
            if (($HWG.hybridRunbookWorkers | Measure-Object).Count -eq 0) { 
                Write-Host ("Adding hybrid worker group named '{0}' as orphaned." -f $HWG.name)
                $OrphanedHWG += $HWG
            } else {
                # Retrieve the most recently seen hybrid worker
                $MostRecentSeenWorker = $HWG.hybridRunbookWorkers | Sort-Object -Property lastSeenDateTime -Descending | Select-Object -First 1
                $MostRecentSeenTime = Get-Date($MostRecentSeenWorker.lastSeenDateTime)
                $MostRecentSeenTimeUTC = $MostRecentSeenTime.ToUniversalTime()
                if ($MostRecentSeenTimeUTC -lt $CurrentTimeUTC.AddDays(-$DaysSinceLastSeen)) {
                    Write-Host ("Adding hybrid worker group named '{0}' as orphaned." -f $HWG.name)
                    $OrphanedHWG += $HWG
                }
            }
        }
        $OrphanedHWG
    }

    Function RemoveOrphanedHybridWorkerGroup {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $HybridWorkerGroupName,
            [Parameter(Mandatory=$false)]
            [switch] $WhatIf
        )

        if ($WhatIf) {
            Write-Host ("what if: Deleting hybrid worker group named '{0}'." -f $HybridWorkerGroupName)
        } else {
            Write-Host ("Deleting hybrid worker group named '{0}'." -f $HybridWorkerGroupName)
            $Uri = ("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Automation/automationAccounts/{3}/hybridRunbookWorkerGroups/{4}?api-version=2015-10-31" -f $AzureManagementBaseUri, $SubscriptionId, $ResourceGroupName, $AutomationAccountName, $HybridWorkerGroupName)
            Write-Host ("Deleting hybrid worker group from '{0}'." -f $Uri)
            Invoke-RestMethod -Method DELETE -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
        }
    }

# Clearing any Azure cached contexts for the current user
Write-Host ("Clearing Azure cached contexts for the current process.")
$null = Clear-AzureRmContext -Scope Process -Force

# Enable the ability for auto save of context to process
Write-Host ("Enabling context auto save for process scope.")
$null = Enable-AzureRmContextAutosave -Scope Process

# Login to Azure.
Write-Host ("Prompting user to login to Azure environment '{0}'." -f $Environment)
$account = Add-AzureRmAccount -Environment $Environment
if (!($account)) {
    throw ("Unable to successfully authenticate to Azure for environment '{0}'." -f $Environment)
}

# Selecting the subscription
Write-Host ("Setting subscription to '{0}'." -f $SubscriptionId)
$AzureContext = Set-AzureRmContext -SubscriptionId $SubscriptionId -Scope Process

# Setting Azure Resource Manager endpoint
$AzureManagementBaseUri = $AzureContext.Environment.ResourceManagerUrl
Write-Host ("Setting resource manager endpoint to {0}." -f $AzureManagementBaseUri)

# Get the list or hybrid worker groups that are considered orphaned
$OrphanedHWGs = GetOrphanedHybridWorkerGroups
Write-Host ("{0} orphaned hybrid worker group(s) identified." -f ($OrphanedHWGS | Measure-Object).Count)

# Remove each of the hybrid worker groups
foreach ($HWG in $OrphanedHWGs) {
    RemoveOrphanedHybridWorkerGroup -HybridWorkerGroupName $HWG.name -WhatIf:$WhatIf
}
