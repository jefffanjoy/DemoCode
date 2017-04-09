Param (
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountName,
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountKey,
    [Parameter(Mandatory=$true)]
    [string] $ContainerName,
    [Parameter(Mandatory=$true)]
    [string] $BlobName,
    [Parameter(Mandatory=$true)]
    [string] $SourceFilePath
)

$context = New-AzureStorageContext `
    -StorageAccountName $StorageAccountName `
    -StorageAccountKey $StorageAccountKey

$result = Set-AzureStorageBlobContent `
    -File $SourceFilePath `
    -Container $ContainerName `
    -Blob $BlobName `
    -Context $context `
    -Force

$result | Add-Member -MemberType NoteProperty -Name 'SourceFilePath' -Value $SourceFilePath
$result
