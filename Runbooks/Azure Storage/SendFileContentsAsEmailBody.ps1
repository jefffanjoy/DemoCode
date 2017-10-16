    Function Get-FileFromAzureStorageBlob {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $StorageAccountName,
            [Parameter(Mandatory=$true)]
            [string] $StorageAccountKey,
            [Parameter(Mandatory=$true)]
            [string] $ContainerName,
            [Parameter(Mandatory=$true)]
            [string] $BlobName,
            [Parameter(Mandatory=$false)]
            [string] $TargetFolderPath = ($env:TEMP)
        )

        $context = New-AzureStorageContext `
            -StorageAccountName $StorageAccountName `
            -StorageAccountKey $StorageAccountKey

        $result = Get-AzureStorageBlobContent `
            -Blob $BlobName `
            -Container $ContainerName `
            -Context $context `
            -Destination $TargetFolderPath `
            -Force

        $result | Add-Member -MemberType NoteProperty -Name 'TargetFolderPath' -Value $TargetFolderPath
        $result | Add-Member -MemberType NoteProperty -Name 'TargetFilePath' -Value ("{0}\{1}" -f $TargetFolderPath, $result.Name)
        $result
    }

    Function Send-SmtpEmail {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $From,
            [Parameter(Mandatory=$true)]
            [string[]] $ToRecipients,
            [Parameter(Mandatory=$true)]
            [string] $Subject,
            [Parameter(Mandatory=$true)]
            [string] $Body
        )

        # Details for smtp connection
        $SmtpServer = 'smtp.sendgrid.net'
        $Port       = 587
        $UseSsl     = $false

        # Get PS Credential asset from automation account for authentication to Smtp server
        $Username = 'USERNAMEGOESHERE'
        $Password = 'PASSWORDGOESHERE'
        $secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential ($Username, $secpasswd)

        # Build parameters hash
        # Comment out any parameters you aren't using such as Cc or Bcc
        $Parameters = @{
            To                          = $ToRecipients
            Subject                     = $Subject
            Body                        = $Body
            From                        = $From
            SmtpServer                  = $SmtpServer
            Port                        = $Port
            UseSsl                      = $UseSsl
            Credential                  = $Credential
        }

        Send-MailMessage @Parameters
    }

$StorageAccountName = 'STORAGEACCOUNTNAMEGOESHERE'
$StorageAccountKey = 'STORAGEACCOUNTKEYGOESHERE'
$ContainerName = 'CONTAINERNAMEGOESHERE'
$BlobName = 'FILENAMEGOESHERE'

$Blob = Get-FileFromAzureStorageBlob -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -ContainerName $ContainerName -BlobName $BlobName
$Body = Get-Content -Path $Blob.TargetFilePath | Out-String

Send-SmtpEmail -From 'FROMEMAILADDRESSGOESHERE' -ToRecipients 'TOEMAILADDRESSGOESHERE' -Subject 'SendGrid Test' -Body $Body
