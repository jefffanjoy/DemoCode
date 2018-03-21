<#
.SYNOPSIS 
    This sample automation runbook finds the current job that is running started by information.
    This runbook must be run from the Automation service since it finds the current job at runtime.

.DESCRIPTION
    This sample automation runbook finds the current job that is running started by information
    This runbook must be run from the Automation service since it finds the current job at runtime.
    You need to update the Azure modules to the latest for the Automation account and then
    import AzureRM.Insights from the module gallery.

.Example
    .\Get-RunningAutomationJobStartedBy

.NOTES
    AUTHOR: Automation Team, Modified by Jeffrey Fanjoy
    LASTEDIT: March 21st 2018
#>
# Authenticate with Azure.
$ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $ServicePrincipalConnection.TenantId `
    -ApplicationId $ServicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint | Write-Verbose

Select-AzureRmSubscription -SubscriptionId $ServicePrincipalConnection.SubscriptionID | Write-Verbose

# Get the current job that is running...
$AutomationJobId = $PSPrivateMetadata.JobId.Guid

# Find the job in order to extract the resource group
$AutomationAccounts = Find-AzureRmresource -ResourceType 'Microsoft.Automation/AutomationAccounts'
foreach ($AutomationAccount in $AutomationAccounts) {
    $CurrentJob = Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.Name -Id $AutomationJobId -ErrorAction SilentlyContinue
    if (!([string]::IsNullOrEmpty($CurrentJob))) { Break; }
}
$AutomationResourceGroupName = $CurrentJob.ResourceGroupName

# Get jobs created in last 3 hours
$StartTime = (Get-Date).AddHours(-3)
$JobAcvitityLogs = Get-AzureRmLog -ResourceGroupName $AutomationResourceGroupName -StartTime $StartTime `
                                | Where-Object {$_.Authorization.Action -eq "Microsoft.Automation/automationAccounts/jobs/write"}

# Find caller for job
$JobInfo = @{}
foreach ($Log in $JobAcvitityLogs)
{
    # Get job resource
    $JobResource = Get-AzureRmResource -ResourceId $Log.ResourceId

    if ($JobResource.Properties.jobId -eq $AutomationJobId)
    { 
        if ($JobInfo[$JobResource.Properties.jobId] -eq $null)
        {
            $JobInfo.Add($JobResource.Properties.jobId,$log.Caller)
        }
        break
    }
}

Write-Output $JobInfo
