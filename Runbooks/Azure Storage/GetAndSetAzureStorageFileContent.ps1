$StorageAccountName = 'STORAGEACCOUNTNAME'
$StorageAccountKey = 'STORAGEACCOUNTKEY'

$AzureFileShare = 'template'
$SourceFileName = 'template.json'
$DestFileName = 'template2.json'

$context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$SourceFile = Get-AzureStorageFileContent -Context $context -ShareName $AzureFileShare -Path $SourceFileName -Destination ("{0}\{1}" -f $env:TEMP, $SourceFileName)
Set-AzureStorageFileContent -Context $context -ShareName $AzureFileShare -Path $DestFileName -Source ("{0}\{1}" -f $env:TEMP, $SourceFileName)
