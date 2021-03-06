﻿Param (
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountName,
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountKey,
    [Parameter(Mandatory=$true)]
    [string] $ContainerName,
    [Parameter(Mandatory=$true)]
    [string] $BlobName
)

$context = New-AzureStorageContext `
    -StorageAccountName $StorageAccountName `
    -StorageAccountKey $StorageAccountKey

$result = Remove-AzureStorageBlob `
    -Blob $BlobName `
    -Container $ContainerName `
    -Context $context

$result
