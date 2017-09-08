# Basic details needed for email
$From = 'fromuser@domain.com'
$ToRecipients = @('torecipient1@domain.com','torecipient2@domain.com')
$CcRecipients = @('ccrecipient1@domain.com','ccrecipient2@domain.com')
$BccRecipients = @('bccrecipient1@domain.com','bccrecipient2@domain.com')
$Subject = 'Email subject'
$Body = 'Email body'

# Details for smtp connection
$SmtpServer = 'smtp-mail.outlook.com'
$Port       = 587
$UseSsl     = $true

# Get PS Credential asset from automation account for authentication to Smtp server
$Credential = Get-AutomationPSCredential -Name "SmtpUser"

# Build parameters hash
# Comment out any parameters you aren't using such as Cc or Bcc
$Parameters = @{
    To                          = $ToRecipients
    Subject                     = $Subject
    Body                        = $Body
    From                        = $From
    Cc                          = $CcRecipients
    Bcc                         = $BccRecipients
    SmtpServer                  = $SmtpServer
    Port                        = $Port
    UseSsl                      = $UseSsl
    Credential                  = $Credential
}

Send-MailMessage @Parameters
