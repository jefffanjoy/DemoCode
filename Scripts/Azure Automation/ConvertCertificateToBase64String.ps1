<#
.SYNOPSIS
    Convert a certificate to a base 64 string export representation.

.DESCRIPTION
    This script will import a given certificate and password (if applicable) and produce
    a base 64 string from the contents of that certificate.

    Intended use is to generate the base64Value property contents for an Azure Resource 
    Manager template that will be used to create a certificate asset in an Azure Automation
    account.

.PARAMETER FilePath
    The path to the certificate file (.PFX or .CER)

.PARAMETER Password
    (Optional) The private key (applies to .PFX certificats).

.EXAMPLE
    .\ConvertCertificateToBase64String -FilePath 'c:\temp\mycertificate.pfx' -Password 'MyPassword'

.NOTES
    AUTHOR  : Jeffrey Fanjoy
    MODIFIED: 2/14/2019
#>

Param
(
    [Parameter(Mandatory=$true)]
    [string] $FilePath,
    [Parameter(Mandatory=$false)]
    [string] $Password = [System.String]::Empty
)

# Set the required key storage flags
$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable `
    + [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet `
    + [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet 
# Load the certificate into memory
$cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($FilePath, $Password, $flags)
# Export the certificate and convert into base 64 string
[System.Convert]::ToBase64String($cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12))
