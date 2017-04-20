Param (
    [Parameter(Mandatory=$true)]
    [string] $AADApplicationDisplayName,
    [Parameter(Mandatory=$true)]
    [string] $AADApplicationPassword
)

# Login to Azure
Login-AzureRmAccount

# Select subscription if more than one is available
$Subscriptions = Get-AzureRmSubscription
switch (($Subscriptions | Measure-Object).Count) {
    0 { throw "No subscriptions found." }
    1 { 
        $Subscription = $Subscriptions[0] 
        $AzureContext = Get-AzureRmContext
    }
    default { 
        $Subscription = ($Subscriptions | Out-GridView -Title 'Select Azure Subscription' -PassThru)
        $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.SubscriptionId
    }
}
$AzureContext

# Use key credentials and create an Azure AD application
$Application = New-AzureRmADApplication -DisplayName $AADApplicationDisplayName -HomePage ("http://" + $AADApplicationDisplayName) -IdentifierUris ("http://" + $AADApplicationDisplayName) -Password $AADApplicationPassword
$ServicePrincipal = New-AzureRMADServicePrincipal -ApplicationId $Application.ApplicationId
$GetServicePrincipal = Get-AzureRmADServicePrincipal -ObjectId $ServicePrincipal.Id

# Sleep here for a few seconds to allow the service principal application to become active (ordinarily takes a few seconds)
Sleep -s 15
$NewRole = New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
$Retries = 0;
While ($NewRole -eq $null -and $Retries -le 6)
{
    Sleep -s 10
    New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId | Write-Verbose -ErrorAction SilentlyContinue
    $NewRole = Get-AzureRMRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
    $Retries++;
}

$Application.ApplicationId.ToString();
