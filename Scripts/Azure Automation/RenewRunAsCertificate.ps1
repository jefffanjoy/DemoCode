Param (
    [Parameter(Mandatory=$true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory=$true)]
    [string] $AutomationAccountName,
    [Parameter(Mandatory=$true)]
    [string] $CertificatePassword,
    [Parameter(Mandatory=$false)]
    [int] $CertificateExpirationInMonths = 12,
    [Parameter(Mandatory=$false)]
    [ValidateSet('AzureCloud','AzureUSGovernment')]
    [Alias('EnvironmentName')]
    [string] $Environment = 'AzureCloud'
)
    Function CreateSelfSignedCertificate {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $CertificateName,
            [Parameter(Mandatory=$true)]
            [string] $CertificatePassword,
            [Parameter(Mandatory=$true)]
            [string] $OutputFolder,
            [Parameter(Mandatory=$false)]
            [string] $ExpirationInMonths = 12
        )

        $Cert = New-SelfSignedCertificate `
            -DnsName $CertificateName `
            -CertStoreLocation cert:\LocalMachine\My `
            -KeyExportPolicy Exportable `
            -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" `
            -NotAfter (Get-Date).AddMonths($ExpirationInMonths)

        $SecurePassword = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force
        Export-PfxCertificate -Cert ("Cert:\localmachine\my\" + $Cert.Thumbprint) -FilePath ("{0}\{1}.pfx" -f $OutputFolder, $CertificateName) -Password $SecurePassword -Force
        Export-Certificate -Cert ("Cert:\localmachine\my\" + $Cert.Thumbprint) -FilePath ("{0}\{1}.cer" -f $OutputFolder, $CertificateName) -Type CERT
    }

    Function Test-IsAdmin {
        ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    }

# Check if the script is run under Administrator role
if (!(Test-IsAdmin)) {
    $msg = @"
    You do not have Administrator rights to run this script!
    Creation of the self-signed certificates requires admin permissions.
    Please re-run this script as an Administrator.
"@
    Write-Warning $msg
    Break
}

# Login to Azure.
Write-Output ("Prompting user to login to Azure environment '{0}'." -f $Environment)
$account = Add-AzureRmAccount -Environment $Environment
if (!($account)) {
    throw ("Unable to successfully authenticate to Azure for environment '{0}'." -f $Environment)
}

# Select subscription if more than one is available
Write-Output ("Selecting Azure subscription with id '{0}'." -f $SubscriptionId)
$Subscription = Get-AzureRmSubscription -SubscriptionId $SubscriptionId
if (!$Subscription) { (throw "Unable to find subscription with id '{0}'." -f $SubscriptionId) }
if ($Subscription.Id) {
    $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.Id
} else {
    $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.SubscriptionId
}
Write-Output ("Subscription successfully selected.")
$AzureContext | Format-List

# Select automation account to renew
Write-Output ("Selecting Automation Account '{0}'." -f $AutomationAccountName)
$AutomationAccount = Get-AzureRmAutomationAccount | Where-Object { $_.AutomationAccountName -eq $AutomationAccountName }
if (!$AutomationAccountName) { (throw "Unable to find automation account with name '{0}'." -f $AutomationAccountName) }
# Get the current run as connection object
$AzureRunAsConnection = Get-AzureRmAutomationConnection `
    -ResourceGroupName $AutomationAccount.ResourceGroupName `
    -AutomationAccountName $AutomationAccount.AutomationAccountName `
    -Name 'AzureRunAsConnection'
if (!$AzureRunAsConnection) { throw "Connection asset 'AzureRunAsConnection' not found.  There must be an existing run as account in order to renew the certificate." }
$AzureRunAsConnection

# Get thecurrent run as certificate object
$AzureRunAsCertificate = Get-AzureRmAutomationCertificate `
    -ResourceGroupName $AutomationAccount.ResourceGroupName `
    -AutomationAccountName $AutomationAccount.AutomationAccountName `
    -Name 'AzureRunAsCertificate'
if (!$AzureRunAsCertificate) { throw "Certificate asset 'AzureRunAsCertificate' not found.  There must be an existing run as account in order to renew the certificate." }
$AzureRunAsCertificate

# Get the Azure AD application
$ADApplication = Get-AzureRmADApplication -ApplicationId $AzureRunAsConnection.FieldDefinitionValues.ApplicationId
if (!$ADApplication) { throw ("Unable to retrieve Azure Active Directory application with application id '{0}'." -f $AzureRunAsConnection.ApplicationId) }

# Get the service principal
$Spn = Get-AzureRmADServicePrincipal -ServicePrincipalName $ADApplication.ApplicationId
if (!$Spn) { throw ("Unable to retrieve service principal for Azure Active Directory application with application id '{0}'." -f $AzureRunAsConnection.ApplicationId) }

$CertificateName = 'AzureRunAsCertificate'
$CertificateOutputFolder = $env:TEMP
$AzureADSPNName = $Spn.ServicePrincipalNames | Where-Object { $_ -match 'https.*' }

# Create self-signed certificate
Write-Output ("Creating self-signed certificate with expiration in '{0}' month(s)." -f $CertificateExpirationInMonths)
CreateSelfSignedCertificate -CertificateName $CertificateName -CertificatePassword $CertificatePassword -OutputFolder $CertificateOutputFolder -ExpirationInMonths $CertificateExpirationInMonths
# Load the pfx certificate into an object
$PfxCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(("{0}\{1}.pfx" -f $CertificateOutputFolder, $CertificateName), $CertificatePassword)
# Load the certificte contents into a Base64 encoded string
$CertValue = [System.Convert]::ToBase64String($PfxCert.GetRawCertData())

# This is the most likely failure point as modifying the SPN may require a higher level of permissions
Write-Output ("Adding the new certificate as the credential for the service principal.")
New-AzureRmADSpCredential -ServicePrincipalName $AzureADSPNName -CertValue $CertValue -StartDate ((Get-Date).AddMinutes(1)) -EndDate $PfxCert.GetExpirationDateString()

# Upload the new certificate to the AzureRunAsCertificate asset
Write-Output ("Updating AzureRunAsCertificate asset with new certificate.")
$SecurePassword = ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force
Set-AzureRmAutomationCertificate `
    -ResourceGroupName $AutomationAccount.ResourceGroupName `
    -AutomationAccountName $AutomationAccount.AutomationAccountName `
    -Name $AzureRunAsCertificate.Name `
    -Path ("{0}\{1}.pfx" -f $CertificateOutputFolder, $CertificateName) `
    -Password $SecurePassword `
    -Exportable $true

# Update the AzureRunAsConnection asset with the new certificate thumbprint
Write-Output ("Updating AzureRunAsConnection asset with new certificate thumbprint.")
# Have to remove and create a new connection since there is a bug in Set-AzureRmAutomationConnectionFieldValue
# that adds quotes around any string value causing the certificate thumbprint to not match the certificate
$AzureRunAsConnection.FieldDefinitionValues.CertificateThumbprint = $PfxCert.Thumbprint
Remove-AzureRmAutomationConnection `
    -ResourceGroupName $AutomationAccount.ResourceGroupName `
    -AutomationAccountName $AutomationAccount.AutomationAccountName `
    -Name $AzureRunAsConnection.Name `
    -Force

New-AzureRmAutomationConnection `
    -ResourceGroupName $AutomationAccount.ResourceGroupName `
    -AutomationAccountName $AutomationAccount.AutomationAccountName `
    -Name $AzureRunAsConnection.Name `
    -ConnectionTypeName $AzureRunAsConnection.ConnectionTypeName `
    -ConnectionFieldValues $AzureRunAsConnection.FieldDefinitionValues
