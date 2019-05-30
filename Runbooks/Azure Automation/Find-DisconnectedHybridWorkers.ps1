<#
.SYNOPSIS
    Find hybrid runbook workers that have not communicated within a defined period.

.DESCRIPTION
    This runbook will authenticate to Azure using the defined Azure Run As Account, get all the
    registered hybrid runbook workers for the defined automation account and then write an output
    stream for each hybrid runbook worker that has not communicated with Azure within the defined
    number of minutes using a readily identifiable prefix string.

    By forwarding job stream data to Azure Log Analytics, alerting can be created to identify any
    hybrid workers that are flagged as disconnected using the readily identifiable prefix string.

    Prefix strings:

    For the scenario where a hybrid worker group has no hybrid workers in it (this really should
    never happen), the prefix string is: ~[Empty Hybrid Worker Group]

    For the scenario where a hybrid worker has not communicated with Azure in the last "n" minutes, 
    the prefix string is: ~[Disconnected Hybrid Worker]

.PARAMETER SubscriptionId
    The subscription id where the automation account exists.  Note that the Azure Run As account 
    must have appropriate permissions to the subscription provided.

.PARAMETER ResourceGroupName
    The resource group name where the automation account exists.

.PARAMETER AutomationAccountName
    The automation account name to query for the hybrid workers.

.PARAMETER AzureRunAsConnectionName
    Optional.  The name of the Azure Run As Account connection asset.  This is the asset that
    identifies the tenant, application and certificate details for authentication.

    Default value: AzureRunAsConnection

.PARAMETER Environment
    Optional.  Specifies the Azure cloud to authenticate into.

    Default value: AzureCloud

    Other options include: AzureUSGovernment

.PARAMETER MinutsSinceLastSeen
    The number of minutes without any communication of the hybrid worker to Azure that identifes
    a hybrid worker as being flagged as disconnected.

.EXAMPLE
    .\Find-DisconnectedHybridWorkers.ps1 `
        -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -ResourceGroupName MyResourceGroup `
        -AutomationAccountName MyAutomationAccount

    The above will query hybrid workers that reside in automation account "MyAutomationAccount"
    and report any hybrid workers that have not communicated in the last 60 minutes (default value).

.EXAMPLE
    .\Find-DisconnectedHybridWorkers.ps1 `
        -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -ResourceGroupName MyResourceGroup `
        -AutomationAccountName MyAutomationAccount `
        -MinutesSinceLastSeen 180

    The above wil query hybrid workers that reside in automation account "MyAutomationAccount"
    and report any hybrid workers that have not communicated in the last 180 minutes.

#>

Param (
    [Parameter(Mandatory=$true)]
    [String] $SubscriptionId,
    [Parameter(Mandatory=$true)]
    [String] $ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [String] $AutomationAccountName,
    [Parameter(Mandatory=$false)]
    [String] $AzureRunAsConnectionName = 'AzureRunAsConnection',
    [Parameter(Mandatory=$false)]
    [string] $Environment = 'AzureCloud',
    [Parameter(Mandatory=$false)]
    [int] $MinutesSinceLastSeen = 60
)

#region Authentication and authorization helpers

    Function Check-IsAzureTokenExpiring
    {
        Param (
            [Parameter(Mandatory=$false)]
            [int] $Threshold = 5
        )

        (($SCRIPT:AzureToken.ExpiresOn.UtcDateTime.AddMinutes(-$Threshold)) -le ((Get-Date).ToUniversalTime()))
    }

    Function Set-AzureToken
    {
        try
        {
            $SCRIPT:AzureContext = Get-AzureRmContext
            if (!$SCRIPT:AzureContext)
            {
                Write-Error ("Azure context is null.")
            }
            else 
            {
                $SCRIPT:AzureToken = ($SCRIPT:AzureContext.TokenCache.ReadItems())[0]
                if ($SCRIPT:AzureToken)
                {
                    Write-Output ("Set token for client id '{0}', displayable id '{1}' with expiration: {2} ({3} UTC)." -f `
                        $SCRIPT:AzureToken.ClientId, $SCRIPT:AzureToken.DisplayableId, $SCRIPT:AzureToken.ExpiresOn.LocalDateTime, $SCRIPT:AzureToken.ExpiresOn.UtcDateTime)
                }
                else
                {
                    Write-Output ("No token could be retrieved from Azure context.")
                }
            }
        }
        catch
        {
            Write-Error ("Exception trapped attempting to set Azure token.  Exception: {0}" -f $_.Exception.Message)
        }
    }

    Function Refresh-AzureToken
    {
        Write-Output ("Executing benign PowerShell statement in an attempt to refresh access token.")
        $null = Get-AzureRmSubscription
        Set-AzureToken
        if (Check-IsAzureTokenExpiring)
        {
            Write-Error ("Failed to refresh Azure token for client id {0}.  Token expiration: {1} ({2} UTC)." -f `
                $SCRIPT:AzureToken.ClientId, $SCRIPT:AzureToken.ExpiresOn.LocalDateTime, $SCRIPT:AzureToken.ExpiresOn.UtcDateTime)
        }
    }

    Function Get-AzureAccessToken
    {
        $SCRIPT:AzureToken.AccessToken
    }

    Function Login-Azure 
    {
        # Clearing any Azure cached contexts for the current user
        Write-Output ("Clearing Azure cached contexts for the current process.")
        Clear-AzureRmContext -Scope Process -Force

        # Enable the ability for auto save of context to process
        Write-Output ("Enabling context auto save for process scope.")
        Enable-AzureRmContextAutosave -Scope Process
        
        # Get run as connection details
        $RunAsConnection = Get-AutomationConnection -Name $AzureRunAsConnectionName

        # Login to Azure.
        Write-Output ("Logging into Azure environment '{0}' using application id '{1}'." -f $Environment, $RunAsConnection.ApplicationId)
        $SCRIPT:AzureContext = Connect-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $RunAsConnection.TenantId `
            -ApplicationId $RunAsConnection.ApplicationId `
            -CertificateThumbprint $RunAsConnection.CertificateThumbprint `
            -Environment $Environment `
            -Scope Process
        if (!($SCRIPT:AzureContext)) 
        {
            throw ("Unable to successfully authenticate to Azure for environment '{0}' using application id '{1}'.  Script cannot proceed." -f $Environment, $RunAsConnection.ApplicationId)
        }
        Write-Output ($SCRIPT:AzureContext | Format-List | Out-String)
    }

    #endregion

    Function Invoke-AzureGetOrListAPI 
    {
        Param 
        (
            [Parameter(Mandatory=$true)]
            [string] $Url,
            [Parameter(Mandatory=$false)]
            [string] $ContentType = 'application/json',
            [Parameter(Mandatory=$false)]
            [int] $MaximumResults = 1000000,
            [Parameter(Mandatory=$false)]
            [int] $ThrottlingRetryIntervalInSeconds = 1,
            [Parameter(Mandatory=$false)]
            [int] $Retries = 3,
            [Parameter(Mandatory=$false)]
            [int] $RetryInterval = 1
        )

        Write-Verbose ("Maximum results set to {0}." -f $MaximumResults)
        $RetryCount = 1
        $resultCount = 0
        $results = @()
        do 
        {
            if (Check-IsAzureTokenExpiring)
            {
                Refresh-AzureToken
            }
            $Headers = @{
                Authorization = ("Bearer {0}" -f (Get-AzureAccessToken))
            }
            try 
            {
                Write-Verbose ("Invoking REST method GET for resource {0}." -f $Url)
                $MethodResults = Invoke-RestMethod -Method GET -Uri $Url -Headers $Headers -ContentType $ContentType -UseBasicParsing
                Write-Verbose ("Data successfully retrieved from {0}" -f $Url)
                if ((($MethodResults.PSObject.Properties | Where-Object { $_.Name -eq 'value' }) | Measure-Object).Count -ne 0) 
                {
                    Write-Verbose ("Next link: {0}" -f $MethodResults.nextLink)
                    $CurrentResultCount = ($MethodResults.value | Measure-Object).Count
                    Write-Verbose ("Current result count: {0}, previous total result count: {1}, new total result count: {2}, maximum results count: {3}." -f $CurrentResultCount, $resultCount, ($resultCount + $CurrentResultCount), $MaximumResults)
                    if (($resultCount + $CurrentResultCount) -ge $MaximumResults)
                    {
                        Write-Verbose ("Maximum results will be exceeded.  Triming current result count to first {0}." -f ($MaximumResults - $resultCount))
                        $results += $MethodResults.value | Select-Object -First ($MaximumResults - $resultCount)
                        $Url = $null
                    }
                    else
                    {
                        $results += $MethodResults.value
                        $resultCount = ($results | Measure-Object).Count
                        $Url = $MethodResults.nextlink
                    }
                } 
                else 
                {
                    $results += $MethodResults
                    $Url = $null
                }
            } 
            catch 
            {
                if ($_.ErrorDetails.Message -match 'RequestsThrottled') 
                {
                    $SleepPeriodInSeconds = $ThrottlingRetryIntervalInSeconds
                    Write-Output ("Encountered resource throttling.  Sleeping for {0} second(s) then trying again." -f $SleepPeriodInSeconds)
                    Start-Sleep -Second $SleepPeriodInSeconds
                } 
                else 
                {
                    if ($RetryCount -ge $Retries)
                    {
                        Write-Output ("Error encountered invoking method for url {0}" -f $Url)
                        $Url = $null
                        Write-Error $_
                    }
                    else
                    {
                        Write-Output ("Error encountered invoking method for url {0}" -f $Url)
                        Write-Error $_
                        Write-Output ("Sleeping for {0} second(s) and then retrying operation." -f $RetryInterval)
                        Start-Sleep -Seconds $RetryInterval
                        $RetryCount++
                    }
                }
            }
        } until (!$Url)
        $results
    }

Login-Azure
if ($SCRIPT:AzureContext)
{
    Set-AzureToken
}

    Function GetEmptyHybridWorkerGroups 
    {
        $Uri = ("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Automation/automationAccounts/{3}/hybridRunbookWorkerGroups?api-version=2015-10-31" -f $AzureManagementBaseUri, $SubscriptionId, $ResourceGroupName, $AutomationAccountName)
        $HWGList = Invoke-AzureGetOrListAPI -Url $Uri
        foreach ($HWG in $HWGList) 
        {
            Write-Verbose ($HWG | Format-List | Out-String)
            # If there are no workers in the group, then consider the group orphaned
            if (($HWG.hybridRunbookWorkers | Measure-Object).Count -eq 0) 
            { 
                Write-Output ("~[Empty Hybrid Worker Group] Hybrid worker group named '{0}' does not have any hybrid runbook workers." -f $HWG.name)
            }
        }
    }

    Function GetDisconnectedHybridWorkers
    {
        $currentTime = Get-Date
        $currentTimeUTC = $currentTime.ToUniversalTime()
        Write-Verbose ("Current Time: {0} ({1} UTC)" -f $currentTime, $currentTimeUTC)
        $Uri = ("{0}subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Automation/automationAccounts/{3}/hybridRunbookWorkerGroups?api-version=2015-10-31" -f $AzureManagementBaseUri, $SubscriptionId, $ResourceGroupName, $AutomationAccountName)
        $HWGList = Invoke-AzureGetOrListAPI -Url $Uri
        foreach ($HWG in $HWGList) 
        {
            # If there are no workers in the group, then consider the group orphaned
            if (($HWG.hybridRunbookWorkers | Measure-Object).Count -gt 0) 
            { 
                Write-Verbose ($HWG | Format-List | Out-String)
                foreach ($HW in $HWG.hybridRunbookWorkers)
                {
                    Write-Verbose ($HW | Format-List | Out-String)
                    $lastSeen = Get-Date($HW.lastSeenDateTime)
                    $lastSeenUTC = $lastSeen.ToUniversalTime()
                    if ($lastSeenUTC -lt $currentTimeUTC.AddMinutes(-$MinutesSinceLastSeen))
                    {
                        Write-Output ("~[Disconnected Hybrid Worker] Hybrid worker named '{0}' in hybrid worker group '{1}' has not sent a heartbeat since '{2}' UTC." -f $HW.Name, $HWG.name, $lastSeenUTC)
                    }
                }
            }
        }
    }

# Selecting the subscription
Write-Output ("Setting subscription to '{0}'." -f $SubscriptionId)
$SCRIPT:AzureContext = Set-AzureRmContext -SubscriptionId $SubscriptionId -Scope Process

# Setting Azure Resource Manager endpoint
$AzureManagementBaseUri = $AzureContext.Environment.ResourceManagerUrl
Write-Output ("Setting resource manager endpoint to '{0}'." -f $AzureManagementBaseUri)

# Get the list of hybrid worker groups that have no hybrid workers
Write-Output ("Getting hybrid worker groups that have no hybrid workers in automation account '{0}'." -f $AutomationAccountName)
GetEmptyHybridWorkerGroups

# Get the list of hybrid workers that have not sent a heartbeat in n minutes
Write-Output ("Retrieving list of hybrid workers that have not sent a heartbeat in more than '{0}' minute(s) in automation account '{1}'." -f $MinutesSinceLastSeen, $AutomationAccountName)
GetDisconnectedHybridWorkers
