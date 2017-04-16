Import-Module -Name 'MgmtSvcConfig'

$name = "automation"
$adminForwardingAddress = "https://server:9090"
$adminUser = "DOMAIN\user"
$adminPassword = "password"


$rp = New-MgmtSvcResourceProviderConfiguration -Name $name -DisplayName 'Automation' -AdminForwardingAddress $adminForwardingAddress -AdminAuthenticationMode 'Basic' -AdminAuthenticationUserName $adminUser -AdminAuthenticationPassword $adminPassword
$connectionString=(Get-MgmtSvcSetting -Namespace AdminAPI -Name ManagementStore).Value
$decryptionKey = (Get-MgmtSvcSetting AdminAPI machineKey.decryptionKey).Value
$algorithm = (Get-MgmtSvcSetting AdminAPI machineKey.decryption).Value

# Remove existing automation resource provider configuration
$automationResource = Get-MgmtSvcResourceProviderConfiguration -As Xml -ConnectionString $connectionString -EncryptionAlgorithm $algorithm -EncryptionKey $decryptionKey -Name automation
Remove-MgmtSvcResourceProviderConfiguration -Name $name -InstanceId $automationResource.ResourceProvider.InstanceId

Add-MgmtSvcResourceProviderConfiguration -ConnectionString $connectionString -EncryptionKey $decryptionKey -EncryptionAlgorithm $algorithm -ResourceProvider $rp
