$CertificateName = 'AzureRunAsCertificate'
$CertificateOutputFolder = 'c:\temp'
$CertificatePassword = 'password'
$CertificateExpirationInMonths = 12
$AzureADSPNName = 'https://spn/'

    Function CreateSelfSignedCertificate {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $CertificateName,
            [Parameter(Mandatory=$true)]
            [string] $Password,
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

        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
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

# Create self-signed certificate
CreateSelfSignedCertificate -CertificateName $CertificateName -Password $CertificatePassword -OutputFolder $CertificateOutputFolder -ExpirationInMonths $CertificateExpirationInMonths
# Load the pfx certificate into an object
$PfxCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(("{0}\{1}.pfx" -f $CertificateOutputFolder, $CertificateName), $CertificatePassword)
# Load the certificte contents into a Base64 encoded string
$CertValue = [System.Convert]::ToBase64String($PfxCert.GetRawCertData())

Login-AzureRmAccount

# This is the most likely failure point as modifying the SPN may require a higher level of permissions
New-AzureRmADSpCredential -ServicePrincipalName $AzureADSPNName -CertValue $CertValue -StartDate ((Get-Date).AddMinutes(1)) -EndDate $PfxCert.GetExpirationDateString()
