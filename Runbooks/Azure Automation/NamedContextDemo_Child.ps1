$SubscriptionId = '140aa888-06f1-45b7-9457-17d5aa7c1b33'

Write-Output "Logging into Azure..."
$ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $ServicePrincipalConnection.TenantId `
    -ApplicationId $ServicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint

$AzureContext = Select-AzureRmSubscription -SubscriptionId $SubscriptionId

Get-AzureRmContext -DefaultProfile $AzureContext | Format-List
