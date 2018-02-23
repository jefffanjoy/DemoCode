# Replace values for the following variables
$SubscriptionId = 'AZURESUBSCRIPTIONIDGOESHERE'
$WorkspaceId = 'OMSWORKSPACEIDGOESHERE'
$WorkspaceKey = 'OMSWORKSPACEKEYGOESHERE'

# If you want to install the extension even if it wasn't there before, set to true.
$ForceInstallOfExtension = $false
$DefaultExtensionName = 'MicrosoftMonitoringAgent'

# Populate the VMs you want to process.  Example is a simple array but you could
# Use Get-AzureRmVM, Find-AzureRmResource, import from a text file etc.  End
# result just needs to be an array of VM names that exist in the subscription id
# provided above.
$VMsToProcess = @(
    'VMNAMEGOESHERE',
    'VMNAMEGOESHERE'
)

# ===================================================================#
# DON'T CHANGE ANYTHING BELOW HERE UNLESS YOU KNOW WHAT YOU'RE DOING #
# ===================================================================#

# Login to azure
Write-Output("Logging into Azure...")
Add-AzureRmAccount
Write-Output ("Selecting Azure subscription with id '{0}'." -f $SubscriptionId)
Select-AzureRmSubscription -Subscription $subscriptionId 

# Define the public workspace configuration
$PublicConf = @"
{{
    "workspaceId": "{0}",
    "stopOnMultipleConnections": true
}}
"@ -f $WorkspaceId

Write-Output ("Applying public configuration: `r`n{0}" -f $PublicConf)

# Define the private workspace configuration
$PrivateConf = @"
{{
    "workspaceKey": "{0}"
}}
"@ -f $WorkspaceKey
Write-Output ("Applying private configuration: `r`n{0}" -f $PrivateConf)

$VMs = Get-AzureRMVM | Where-Object { $VMsToProcess -contains $_.Name }
foreach ($VM in $VMs)
{
    Write-Output ("Processing Virtual Machine '{0}'." -f $VM.Name)
    Write-Output ("Retrieving VM status information for VM '{0}'." -f $VM.Name)
    $Statuses = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status
    $PowerState = $Statuses.Statuses | Where-Object { $_.Code -like 'PowerState*' }
    if ($PowerState.Code -eq 'PowerState/running') {
        Write-Output ("Virtual machine '{0}' is currently in a running state." -f $VM.Name)
        if ($VM.StorageProfile.OsDisk.OsType -eq "Windows")
        {
            $InstallExtension = $ForceInstallOfExtension
            $ExtensionInstallName = $null
            foreach ($Extension in $VM.Extensions) {
                $ExtensionName = $Extension.Id.Split("/")[-1]
                Write-Output ("Getting details for extension named '{0}'." -f $ExtensionName)
                $ext = Get-AzureRmVMExtension -VMName $Vm.Name -ResourceGroupName $vm.ResourceGroupName -Name $ExtensionName
                if ($ext.ExtensionType -eq 'MicrosoftMonitoringAgent') {
                    Write-Output ("Removing extension named '{0}' of type '{1}'." -f $ExtensionName, $ext.ExtensionType)
                    try {
                        Remove-AzureRmVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name $ExtensionName -Force
                        $InstallExtension = $true
                        $ExtensionInstallName = $ExtensionName
                    } catch {
                        Write-Error $_.Exception
                    }
                } else {
                    Write-Output ("Ignoring extension named '{0}' of type '{1}'." -f $ExtensionName, $ext.ExtensionType)
                }
            }
            if ($InstallExtension) {
                if (!$ExtensionInstallName) { $ExtensionInstallName = $DefaultExtensionName }
                Write-Output ("Installing MicrosoftMonitoringAgent extension to virtual machine '{0}' using extension name '{1}'." -f $VM.Name, $ExtensionInstallName)
                try {
                    Set-AzureRmVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name $ExtensionInstallName -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "MicrosoftMonitoringAgent" -TypeHandlerVersion '1.0' -Location $VM.Location -Settingstring $PublicConf -ProtectedSettingString $PrivateConf -ForceRerun True
                } catch {
                    Write-Error $_.Exception
                }
            }
        } else {
            Write-Output ("Skipping virtual machine '{0}' as the operating system is not Windows." -f $VM.Name)
        }
    } else {
        Write-Error ("Virtual Machine '{0}' is not currently in a running state which is required to reinstall the extension." -f $VM.Name)
    }
}
