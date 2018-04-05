Write-Output "Logging into Azure..."
$ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $ServicePrincipalConnection.TenantId `
    -ApplicationId $ServicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint

$AzureContext = Select-AzureRmSubscription -SubscriptionId $ServicePrincipalConnection.SubscriptionID

$ChildRunbookName = 'NamedContextDemo_Child'
$Instances = 100
$AutomationAccountName = 'Testing4'
$ResourceGroupName = 'Testing4'

1..$Instances | ForEach-Object {
    Write-Output ("Starting instance {0} of child runbook {1}." -f $_, $ChildRunbookName)
    Start-AzureRmAutomationRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $ChildRunbookName `
        -DefaultProfile $AzureContext
}
