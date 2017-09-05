<# 
.SYNOPSIS 
   Remove all blob contents from one storage account that are X days old. 
.DESCRIPTION  
   This script will run through a single Azure storage account and delete all blob contents in  
   all containers, which are X days old. 
.EXAMPLE 
    Remove-StorageBlobXDaysOld -StorageAccountName "storageaccountname" -AzureConnectionName "azureconnectionname" -DaysOld 7 
#> 
param( 
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountName,
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountKey,
    [Parameter(Mandatory = $true)] 
    [Int32] $DaysOld,
    [Parameter(Mandatory=$false)]
    [boolean] $WhatIf = $false
) 
    
# Authenticate to the storage account and create a context
$context = New-AzureStorageContext `
    -StorageAccountName $StorageAccountName `
    -StorageAccountKey $StorageAccountKey

$Start = [System.DateTime]::Now 
"Starting: " + $Start.ToString("HH:mm:ss.ffffzzz") 
 
# loop through each container and get list of blobs for each container and delete 
$blobsremoved = 0 
$containersremoved = 0 
    
# Get all containers
$containers = Get-AzureStorageContainer -Context $context -ErrorAction SilentlyContinue 
     
foreach($container in $containers) {  
    $blobsremovedincontainer = 0        
    Write-Output ("Searching Container: {0}" -f $container.Name)   
        
    # Get blobs in container 
    $blobs = Get-AzureStorageBlob -Container $container.Name -Context $context

    if ($blobs -ne $null) {     
        foreach ($blob in $blobs) { 
            $lastModified = $blob.LastModified 
            if ($lastModified -ne $null) { 
                $blobDays = ([System.DateTimeOffset]::Now - [System.DateTimeOffset]$lastModified) 
                Write-Output ("Blob {0} in storage for {1} days" -f $blob.Name, $blobDays)  
                
                if ($blobDays.Days -ge $DaysOld) { 
                    Write-Output ("Removing Blob: {0}" -f $blob.Name) 
                    if ($WhatIf -eq $true) {
                        Write-Output ("WHATIF: Would have deleted blob '{0}' from container '{1}'." -f $blob.Name, $container.Name)
                    } else {
                        Remove-AzureStorageBlob -Blob $blob.Name -Container $container.Name -Context $context
                    }
                    $blobsremoved += 1 
                    $blobsremovedincontainer += 1 
                } 
            } 
        } 
    } 
         
    $blobs = Get-AzureStorageBlob -Container $container.Name -Context $context
    if ($blobs -eq $null -or $blobs.Count -eq 0) { 
        Write-Output ("Removing Blob container: {0}" -f $container.Name)  
        if ($WhatIf -eq $true) {
            Write-Output ("WHATIF: Would have deleted container '{0}'." -f $container.Name)
        } else {
            Remove-AzureStorageContainer -Name $container.Name -Force -Context $context
        }
        $containersremoved += 1 
    } 
 
    Write-Output ("{0} blobs removed from container {1}." -f $blobsremovedincontainer, $container.Name)        
} 
     
$Finish = [System.DateTime]::Now 
$TotalUsed = $Finish.Subtract($Start).TotalSeconds 
    
Write-Output ("Removed {0} blobs and {1} containers in storage account {2} in {3} seconds." -f $blobsRemoved, $containersremoved, $StorageAccountName, $TotalUsed) 
"Finished " + $Finish.ToString("HH:mm:ss.ffffzzz") 
  