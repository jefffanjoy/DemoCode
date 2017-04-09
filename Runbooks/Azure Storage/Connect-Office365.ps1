# Connect to Office 365
$O365Credential = Get-AutomationPSCredential -Name 'O365Credential'
$O365Session = New-PSSession `
    -ConfigurationName Microsoft.Exchange `
    -ConnectionUri 'https://outlook.office365.com/powershell-liveid' `
    -Credential $O365Credential `
    -Authentication Basic `
    -AllowRedirection

# Import modules from the Office 365 remote powershell session and bring
# that session into local scope
Import-Module (Import-PSSession -Session $O365Session) -Global

# Connect to MSOnline
Connect-MsolService -Credential $O365Credential
