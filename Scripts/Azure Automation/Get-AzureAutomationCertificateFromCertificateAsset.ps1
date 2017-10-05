Param (
    [Parameter(Mandatory=$true)]
    [String] $ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [String] $AutomationAccountName,
    [Parameter(Mandatory=$false)]
    [String] $CertificateAssetName = 'AzureRunAsCertificate',
    [Parameter(Mandatory=$true)]
    [String] $CertificatePassword,
    [Parameter(Mandatory=$false)]
    [Switch] $ImportCertificate,
    [Parameter(Mandatory=$false)]
    [ValidateSet('LocalMachine', 'CurrentUser')]
    [String] $ImportCertificateStore = 'CurrentUser'
)

# Login to Azure
Write-Output "Prompting user to login to Azure."
Add-AzureRmAccount

# If there is more than one subscription, prompt user to select the desired one
$subscriptions = Get-AzureRmSubscription
If($subscriptions.count -gt 1)
{
    Write-Output "Prompting user to select the desired subscription."
    $subscription = $subscriptions | Out-GridView -PassThru
    if ($Subscription.Id) {
        $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.Id
    } else {
        $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.SubscriptionId
    }
    $AzureContext
} 

# Check to confirm that the certificate asset exists
Write-Output ("Getting details of certificate asset with name '{0}'." -f $CertificateAssetName)
$CertificateAsset = Get-AzureRmAutomationCertificate -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $CertificateAssetName
if ($CertificateAsset -eq $null) {
    throw ("Certificate asset with name '{0}' was not found in automation account '{1}'." -f $CertificateAssetName, $AutomationAccountName)
} else {
    $CertificateAsset
    if ($CertificateAsset.Exportable -eq $false) {
        throw ("Certificate asset with name '{0}' is configured as non-exportable." -f $CertificateAssetName)
    }
}

# Check to confirm that there is an AzureRunAsConnection as this is required for the 
# runbook that we are going to create to function
$RunAsConnection = Get-AzureRmAutomationConnection -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'AzureRunAsConnection'
if ($RunAsConnection -eq $null)
{
    throw "RunAs connection is not available in the automation account. Please create one first."
}

# Construct the temporary runbook that we are going to import and execute
$ExportCert = @'
param (
    [Parameter(Mandatory=$true)]
    [String] $StorageAccountName,
    [Parameter(Mandatory=$true)]
    [String] $ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [String] $AutomationAccount,
    [Parameter(Mandatory=$true)]
    [String] $CertificateAssetName
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
$RunAsCert = Get-AutomationCertificate -Name $CertificateAssetName

# Set the password used for this certificate
$Password = Get-AutomationVariable -Name "CertPassword"
	
# location to store temporary certificate in the Automation service host
$CertPath = ("C:\{0}.pfx" -f $CertificateAssetName)
   
# Save the certificate to the Automation service host so it can be referenced in the REST calls
$Cert = $RunAsCert.Export("pfx", $Password)
Set-Content -Value $Cert -Path $CertPath -Force -Encoding Byte | Write-Verbose 

$Account = Get-AzureRmAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccount
$Location = $Account.Location
$ModuleContainer = "runascert"

$StorageAccount = New-AzureRMStorageAccount -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Location $Location -Type Standard_LRS

$StorageKey = Get-AzureRmStorageAccountKey -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName

#$StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey ($StorageKey.Value | Select -First 1)
$StorageContext = $StorageAccount.Context

New-AzureStorageContainer -Name $ModuleContainer -Context $StorageContext  -ErrorAction SilentlyContinue -WarningAction Ignore | Write-Verbose

# Copy file to blob storage
$BlobName = (Split-Path $CertPath -Leaf)
$Blob = Set-AzureStorageBlobContent -Context $StorageContext -Container $ModuleContainer -File $CertPath -BlobType  Block -Blob $BlobName -Force 

'@

try
{
    Write-Output ("Importing runbook Export-Cert to automation account {0} in resource group {1}." -f $AutomationAccountName, $ResourceGroupName)
    Set-Content -Path (Join-Path $env:TEMP "Export-Cert.ps1") -Value $ExportCert -Force | Write-Verbose
    Import-AzureRmAutomationRunbook `
        -Path (Join-Path $env:TEMP "Export-Cert.ps1") `
        -Name "Export-Cert" `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Type PowerShell `
        -Published | Write-Verbose 

    $RandomNumber = (Get-Random -Minimum 10000 -Maximum 100000)
    $StorageAccountName = "tempstorage" + $RandomNumber

    New-AzureRmAutomationVariable `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name "CertPassword" `
        -Value $NewCertPassword `
        -Encrypted $true | Write-Verbose 

    $Params = @{
        StorageAccountName      = $StorageAccountName
        ResourceGroupName       = $ResourceGroupName
        AutomationAccount       = $AutomationAccountName
        CertificateAssetName    = $CertificateAssetName
    }
    Write-Verbose ("Starting runbook Export-Cert with parameters: {0}" -f ($Params | ConvertTo-Json))
    $Job = Start-AzureRmAutomationRunbook `
        -Name Export-Cert `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Parameters $Params
    Write-Verbose ("Job id: {0}" -f $Job.JobId)

    do {
        $Job = Get-AzureRmAutomationJob -Id $Job.JobId -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
        Write-Output ("Retrieving certificate from automation service..." + "Job Status is " + $Job.Status)
        Sleep 5
    } while ($Job.Status -ne "Completed" -and $Job.Status -ne "Failed" -and $Job.Status -ne "Suspended")

    if ($Job.Status -eq "Completed")
    {
        Write-Output ("Downloading certificate from storage account {0}" -f $StorageAccountName)
        Write-Verbose ("Getting storage account details for storage account {0} in resource group {1}." -f $StorageAccountName, $ResourceGroupName)
        $StorageAccount = Get-AzureRmStorageAccount -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName
        Write-Verbose ("Getting blob data from storage account.")
        $Blob = Get-AzureStorageBlob -Context $StorageAccount.Context -Container runascert

        $TargetFolderPath = $env:TEMP
        $result = Get-AzureStorageBlobContent `
            -Blob $Blob.Name `
            -Container runascert `
            -Context $StorageAccount.Context `
            -Destination $TargetFolderPath `
            -Force

        $result | Add-Member -MemberType NoteProperty -Name 'TargetFolderPath' -Value $TargetFolderPath
        $result | Add-Member -MemberType NoteProperty -Name 'TargetFilePath' -Value ("{0}\{1}" -f $TargetFolderPath, $result.Name)
        $result

        if ($ImportCertificate) {
            Write-Output ("Importing certificate from '{0}' to 'Cert:\{1}\my'." -f $result.TargetFilePath, $ImportCertificateStore)
            $SecurePassword = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force
            Import-PfxCertificate `
                -FilePath $result.TargetFilePath `
                -CertStoreLocation ("Cert:\{0}\my" -f $ImportCertificateStore) `
                -Password $SecurePassword `
                -Exportable
        }
    }
    else
    {
        Write-Output ("Failed to get certificate from automation account.")
        Write-Output $Job.Exception
    }
}
Catch 
{ 
    Write-Error $_
}
finally
{
    Write-Verbose ("Removing storage account {0}." -f $StorageAccountName)
    Remove-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force
    Write-Verbose ("Removing runbook Export-Cert.")
    Remove-AzureRmAutomationRunbook "Export-Cert" -ResourceGroupName $ResourceGroupName -AutomationAccount $AutomationAccountName -Force
    Write-Verbose ("Removing automation variable CertPassword.")
    Remove-AzureRmAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccount $AutomationAccountName -Name CertPassword
}

