﻿<#
.SYNOPSIS
    Get a list of modules from an Azure Automation account.

.DESCRIPTION
    Get the listing of modules in a given Azure Automation account including
    details such as module version number, date last modified and size.

.PARAMETER ResourceGroupName
    The resource group name where the Automation account exists.

.PARAMETER AutomationAccountName
    The name of the Automation account to query for the modules to list.

.EXAMPLE
    .\Get-AutomationModuleDetails.ps1 -ResourceGroupName 'MyResourceGroup' -AutomationAccountName 'MyAutomationAccount'

.NOTES
    AUTHOR  : Jeffrey Fanjoy
    LASTEDIT: 10/28/2016
#>
Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory=$true, Position=1)]
    [string] $AutomationAccountName
)

# Make sure required modules are available
$RequiredModules = @('AzureRM.profile', 'AzureRM.automation', 'AzureRM.resources')
$ModuleMissing = $false
foreach ($Module in $RequiredModules) {
    Write-Verbose ("Checking for module '{0}'." -f $Module)
    if (!(Get-Module -Name $Module -ListAvailable)) { 
        Write-Output ("Module '{0}' was not found." -f $Module)
        $ModuleMissing = $true 
    }
}
if ($ModuleMissing -eq $true) { throw 'At least one required module was not found.' }

# Login to Azure.
Login-AzureRmAccount

# Select subscription if more than one is available
$Subscriptions = Get-AzureRmSubscription
if (($Subscriptions | Measure-Object).Count -gt 1) {
    Select-AzureRmSubscription -SubscriptionName (($Subscriptions | Out-GridView -Title 'Select Azure Subscription' -PassThru).SubscriptionName)
}

$ModuleList = Get-AzureRmAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction Stop
$Modules = @()
foreach ($Module in $ModuleList) {
    $Modules += Get-AzureRmAutomationModule -Name $Module.Name -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
}
$Modules | Format-Table -AutoSize | Out-String -Width 8000