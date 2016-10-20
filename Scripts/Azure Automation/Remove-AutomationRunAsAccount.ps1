<#
.SYNOPSIS
    Script to remove an Azure Automation Run As Account.

.DESCRIPTION
    This script will login to Azure Automation, and prompt the user for details
    relating to the subscription, automation account and service principal (Run As Account)
    that is to be deleted and will then delete the selected service principal and its
    associated Azure AD Application.

.PARAMETER
    Optional.  AutomationAccountName
    The automation account name connected to the service principal.  If this parameter is
    not provided, then a list of existing automation accounts will be presented.  If the 
    automation account has been deleted, then this parameter becomes required.

.EXAMPLE
    .\Remove-AutomationRunAsAccount -AutomationAccountName 'MyAutomationAccount'

.EXAMPLE
    .\Remove-AutomationRunAsAccount

.NOTES
    AUTHOR  : Jeffrey Fanjoy
    LASTEDIT: 10/20/2016
#>
Param (
    [Parameter(Mandatory=$false)]
    [string] $AutomationAccountName
)

# Login to Azure Resource Manager
Login-AzureRmAccount

# Select the desired Azure subscription
$Subscription = (Get-AzureRmSubscription | Out-GridView -PassThru -Title 'Select the desired Azure subscription')
if (!($Subscription)) { throw "A subscription must be selected." }
$Subscription | Select-AzureRmSubscription

# If no automation account name was provided, present a list to select from
if (!($AutomationAccountName)) {
    $AutomationAccountName = (Get-AzureRmAutomationAccount | Select-Object AutomationAccountName, Location | Out-GridView -PassThru -Title 'Select the desired Automation account').AutomationAccountName
    if (!($AutomationAccountName)) { throw "An automation account must be selected." }
}

# Select the service principal to be deleted.  There is typically only one
# but just in case there are more this allows us to select the desired one
$ServicePrincipal = (Get-AzureRmADServicePrincipal -SearchString $AutomationAccountName | Out-GridView -PassThru -Title 'Select the service principal to delete')
if (!($ServicePrincipal)) { throw "A service principal must be selected." }
$ServicePrincipal | Format-List

# Get the AD application associated with our service principal
$ADApplication = Get-AzureRmADApplication -ApplicationId $ServicePrincipal.ApplicationId
$ADApplication | Format-List

# Construct a UI prompt to confirm deletion
$YesPrompt = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Yes - I am sure'
$NoPrompt = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'No - I changed my mind'
$PromptOptions = [System.Management.Automation.Host.ChoiceDescription[]] ($YesPrompt, $NoPrompt)
$Prompt = ("Are you sure you want to remove service principal and AD application '{0}'?" -f $ADApplication.DisplayName)
$Choice = $Host.UI.PromptForChoice($null, $prompt, $PromptOptions, 1)

# If user confirmed the deletion then go ahead and delete
if ($Choice -eq 0) {
    Write-Host ("Removing AD application {0} ({1})." -f $ADApplication.ApplicationId, $ADApplication.DisplayName)
    Remove-AzureRmADApplication -ObjectId $ADApplication.ApplicationId
    Write-Host ("Removing service principal {0} ({1})." -f $ServicePrincipal.Id, $ServicePrincipal.DisplayName)
    Remove-AzureRmServicePrincipal -ObjectId $ServicePrincipal.Id
}
