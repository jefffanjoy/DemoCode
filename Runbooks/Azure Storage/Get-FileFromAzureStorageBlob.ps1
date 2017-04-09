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
    -Destination $TargetFolderPath

$result | Add-Member -MemberType NoteProperty -Name 'TargetFolderPath' -Value $TargetFolderPath
$result | Add-Member -MemberType NoteProperty -Name 'TargetFilePath' -Value ("{0}\{1}" -f $TargetFolderPath, $result.Name)
$result
