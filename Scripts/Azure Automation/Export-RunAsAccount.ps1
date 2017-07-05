
<#
.SYNOPSIS 
   Downloads a RunAs certificate from the automation service and imports into current user local certificate store so
   it can be used on the local computer

.DESCRIPTION
   Downloads a RunAs certificate from the automation service and imports into current user local certificate store so
   it can be used on the local computer. This allows you to work in the Azure Automation ISE Add-on using the same credentials
   that are used in the service. It creates a runbook that will export the certificate to a new Azure Storage account and then
   downloads this certificate to the local computer.
   It then installs the certificate into the local current users certificate store. You can export from the store with the 
   supplied password if it is needed on other computers.
    
.EXAMPLE
   sfd

.NOTES
    AUTHOR: Azure/OMS Automation Team
    LASTEDIT: Sep 24, 2016  
#>
Param(
[Parameter(Mandatory=$true)]
[String] $AutomationResourceGroup,

[Parameter(Mandatory=$true)]
[String] $AutomationAccount,

[Parameter(Mandatory=$true)]
[String] $NewCertPassword
)

Add-AzureRmAccount

$subscriptions = Get-AzureRmSubscription
If($subscriptions.count -gt 1)
{
    $subscription = $subscriptions | Out-GridView -PassThru
    if ($Subscription.Id) {
        $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.Id
    } else {
        $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.SubscriptionId
    }
#    Select-AzureRmSubscription -SubscriptionId $subscription.Subscriptionid
} 

$ExportCert = @'
param (
[Parameter(Mandatory=$true)]
[String] $StorageAccountName,

[Parameter(Mandatory=$true)]
[String] $AutomationResourceGroup,

[Parameter(Mandatory=$true)]
[String] $AutomationAccount
)
$ErrorActionPreference = 'stop'

$RunAsConnection = Get-AutomationConnection -Name AzureRunAsConnection
if ($RunAsConnection -eq $null)
{
    throw "RunAs connection is not available in the automation account. Please create one first"
}
Add-AzureRmAccount `
-ServicePrincipal `
-TenantId $RunAsConnection.TenantId `
-ApplicationId $RunAsConnection.ApplicationId `
-CertificateThumbprint $RunAsConnection.CertificateThumbprint | Write-Verbose

Select-AzureRmSubscription -SubscriptionId $RunAsConnection.SubscriptionID  | Write-Verbose 
    
# Get the management certificate that will be used to make calls into Azure Service Management resources
$RunAsCert = Get-AutomationCertificate -Name "AzureRunAsCertificate"

# Set the password used for this certificate
$Password = Get-AutomationVariable -Name "CertPassword"
	
# location to store temporary certificate in the Automation service host
$CertPath = "C:\AzureRunAsCertificate.pfx"
   
# Save the certificate to the Automation service host so it can be referenced in the REST calls
$Cert = $RunAsCert.Export("pfx",$Password)
Set-Content -Value $Cert -Path $CertPath -Force -Encoding Byte | Write-Verbose 

$Account = Get-AzureRmAutomationAccount -ResourceGroupName $AutomationResourceGroup -Name $AutomationAccount
$Location = $Account.Location
$ModuleContainer = "runascert"

$StorageAccount = New-AzureRMStorageAccount -ResourceGroupName $AutomationResourceGroup -StorageAccountName $StorageAccountName -Location $Location -Type Standard_LRS

$StorageKey = Get-AzureRmStorageAccountKey -StorageAccountName $StorageAccountName -ResourceGroupName $AutomationResourceGroup

#$StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey ($StorageKey.Value | Select -First 1)
$StorageContext = $StorageAccount.Context

New-AzureStorageContainer -Name $ModuleContainer -Context $StorageContext  -ErrorAction SilentlyContinue -WarningAction Ignore | Write-Verbose

# Copy file to blob storage
$BlobName = (Split-Path $CertPath -Leaf)
$Blob = Set-AzureStorageBlobContent -Context $StorageContext -Container $ModuleContainer -File $CertPath -BlobType  Block -Blob $BlobName -Force 

'@

try
{

    Set-Content -Path (Join-Path $env:TEMP "Export-Cert.ps1") -Value $ExportCert -Force | Write-Verbose
    Import-AzureRmAutomationRunbook -Path (Join-Path $env:TEMP "Export-Cert.ps1") -Name "Export-Cert" `
                                        -ResourceGroupName $AutomationResourceGroup -AutomationAccountName $AutomationAccount `
                                        -Type PowerShell -Published | Write-Verbose 

    $RandomNumber = (Get-Random -Minimum 10000 -Maximum 100000)
    $StorageAccountName = "runascertificate" + $RandomNumber

    New-AzureRmAutomationVariable -ResourceGroupName $AutomationResourceGroup -AutomationAccountName $AutomationAccount `
                                  -Name "CertPassword" -Value $NewCertPassword -Encrypted $true | Write-Verbose 

    $Params = @{"StorageAccountName"=$StorageAccountName;"AutomationResourceGroup"=$AutomationResourceGroup;"AutomationAccount"=$AutomationAccount}
    $Job = Start-AzureRmAutomationRunbook -Name Export-Cert -ResourceGroupName $AutomationResourceGroup `
                                          -AutomationAccountName $AutomationAccount -Parameters $Params

    do {
        $Job = Get-AzureRmAutomationJob -Id $Job.JobId -ResourceGroupName $AutomationResourceGroup -AutomationAccountName $AutomationAccount
        Write-Output ("Retrieving certificate from automation service..." + "Job Status is " + $Job.Status)
        Sleep 5
    } while ($Job.Status -ne "Completed" -and $Job.Status -ne "Failed" -and $Job.Status -ne "Suspended")

    if ($Job.Status -eq "Completed")
    {
        Write-Output ("Downloading certificate from storage account " + $StorageAccountName)
        $StorageAccount = Get-AzureRmStorageAccount -StorageAccountName $StorageAccountName -ResourceGroupName $AutomationResourceGroup
        $Blob = Get-AzureStorageBlob -Context $StorageAccount.Context -Container runascert

        Get-AzureStorageBlobContent -Context $StorageAccount.Context -Container runascert -Blob $Blob.Name -Destination (Join-Path $env:TEMP $Blob.Name) -Force | Write-Verbose
        # Import certificate into current user store
        Write-Output ("Importing certificate into local store from " + (Join-Path $env:TEMP $Blob.Name))
        $SecurePassword = ConvertTo-SecureString $NewCertPassword -AsPlainText -Force
        Import-PfxCertificate -FilePath (Join-Path $env:TEMP $Blob.Name) -CertStoreLocation Cert:\CurrentUser\my -Password $SecurePassword -Exportable | Write-Verbose
    }
    else
    {
        Write-Output ("Failed to get certificate from automation account")
        Write-Output $Job.Exception
    }
}
Catch 
{ 
    Write-Error $_
}
finally
{
    Remove-AzureRmStorageAccount -ResourceGroupName $AutomationResourceGroup -Name $StorageAccountName
    Remove-AzureRmAutomationRunbook "Export-Cert" -ResourceGroupName $AutomationResourceGroup -AutomationAccount $AutomationAccount -Force
    Remove-AzureRmAutomationVariable -ResourceGroupName $AutomationResourceGroup -AutomationAccount $AutomationAccount -Name CertPassword
}



