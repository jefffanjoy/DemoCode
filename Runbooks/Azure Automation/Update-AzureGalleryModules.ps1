#Requires -Module AzureRM.Profile
#Requires -Module AzureRM.Automation

<#
.SYNOPSIS 
    Updates existing AzureRM modules on PowerShell Gallery into the Automation service.

.DESCRIPTION
    Updates modules on PowerShell Gallery into the Automation service.
    It first checks that the AzureRM module is available on the gallery.
    It then updates all of the existing modules in the Automation account to the latest.

.PARAMETER ResourceGroupName
    Optional. The name of the Azure Resource Group containing the Automation account where the
    modules will be updated.  If not provided, the Resource Group for the job that is
    executing will be used.

.PARAMETER AutomationAccountName
    Optional. The name of the Automation account where the modules will be updated.  If not
    provided, the Automation account for the job that is executing will be used.

.EXAMPLE
    Update-AzureGalleryModules
        
.EXAMPLE
    Update-AzureGalleryModules -ResourceGroupName "MyResourceGroup" -AutomationAccountName "MyAutomationAccount"

.NOTES
    AUTHOR: Jeffrey Fanjoy, modified from original sources by Azure/OMS Automation team
    LASTEDIT: October 11, 2016  
#>

Param (
    [Parameter(Mandatory=$false)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory=$false)]
    [string] $AutomationAccountName
)

$ModulesImported = @()

    Function _doImport {
        param(
            [Parameter(Mandatory=$true)]
            [String] $ResourceGroupName,

            [Parameter(Mandatory=$true)]
            [String] $AutomationAccountName,
    
            [Parameter(Mandatory=$true)]
            [String] $ModuleName,

            # if not specified latest version will be imported
            [Parameter(Mandatory=$false)]
            [String] $ModuleVersion
        )

        $Url = "https://www.powershellgallery.com/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$ModuleName%27&targetFramework=%27%27&includePrerelease=false&`$skip=0&`$top=40" 
        $SearchResult = Invoke-RestMethod -Method Get -Uri $Url -UseBasicParsing

        if($SearchResult.Length -and $SearchResult.Length -gt 1) {
            $SearchResult = $SearchResult | Where-Object -FilterScript {
                return $_.properties.title -eq $ModuleName
            }
        }

        if(!$SearchResult) {
            Write-Error "Could not find module '$ModuleName' on PowerShell Gallery."
        }
        else {
            $ModuleName = $SearchResult.properties.title # get correct casing for the module name
            $PackageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $SearchResult.id 
    
            if(!$ModuleVersion) {
                # get latest version
                $ModuleVersion = $PackageDetails.entry.properties.version
            }

            $ModuleContentUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$ModuleVersion"

            # Test if the module/version combination exists
            try {
                Invoke-RestMethod $ModuleContentUrl -ErrorAction Stop | Out-Null
                $Stop = $False
            }
            catch {
                Write-Error "Module with name '$ModuleName' of version '$ModuleVersion' does not exist. Are you sure the version specified is correct?"
                $Stop = $True
            }

            if(!$Stop) {
                # check if this module is the same version as the one in the service
                $AutomationModule = Get-AzureRmAutomationModule `
                                                -ResourceGroupName $ResourceGroupName `
                                                -AutomationAccountName $AutomationAccountName `
                                                -Name $ModuleName `
                                                -ErrorAction SilentlyContinue

                if(($AutomationModule) -and $AutomationModule.Version -eq $ModuleVersion) {
                    # Skip importing this module                
                    Write-Output "Module $ModuleName is already at latest version $ModuleVersion."
                    return
                }

                # Make sure module dependencies are imported
                $Dependencies = $PackageDetails.entry.properties.dependencies
                $Parts = $Dependencies.Split(":")
                $DependencyName = $Parts[0]
                $DependencyVersion = $Parts[1]

                if($Dependencies -and $Dependencies.Length -gt 0) {
                    $Dependencies = $Dependencies.Split("|")

                    # parse depencencies, which are in the format: module1name:module1version:|module2name:module2version:
                    $Dependencies | ForEach-Object {

                        if($_ -and $_.Length -gt 0) {
                            $Parts = $_.Replace("[","").Replace("]","").Split(":")
                            $DependencyName = $Parts[0]
                            $DependencyVersion = $Parts[1]

                            # check if we already imported this dependency module during execution of this script
                            if(!$ModulesImported.Contains($DependencyName)) {

                                $AutomationModule = Get-AzureRmAutomationModule `
                                    -ResourceGroupName $ResourceGroupName `
                                    -AutomationAccountName $AutomationAccountName `
                                    -Name $DependencyName `
                                    -ErrorAction SilentlyContinue
    
                                # check if Automation account already contains this dependency module of the right version
                                if((!$AutomationModule) -or $AutomationModule.Version -ne $DependencyVersion) {
                                
                                    Write-Output "Importing dependency module $DependencyName of version $DependencyVersion first."

                                    # this dependency module has not been imported, import it first
                                    _doImport `
                                        -ResourceGroupName $ResourceGroupName `
                                        -AutomationAccountName $AutomationAccountName `
                                        -ModuleName $DependencyName `
                                        -ModuleVersion $DependencyVersion

                                    $ModulesImported += $DependencyName
                                }
                            }
                        }
                    }
                }
            
                # Find the actual blob storage location of the module
                do {
                    $ActualUrl = $ModuleContentUrl
                    $ModuleContentUrl = (Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore).Headers.Location 
                } while($ModuleContentUrl -ne $Null)


                Write-Output "Importing $ModuleName module of version $ModuleVersion from $ActualUrl to Automation"

                $AutomationModule = New-AzureRmAutomationModule `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -Name $ModuleName `
                    -ContentLink $ActualUrl

                while(
                    $AutomationModule.ProvisioningState -ne "Created" -and
                    $AutomationModule.ProvisioningState -ne "Succeeded" -and
                    $AutomationModule.ProvisioningState -ne "Failed"
                )
                {
                    Write-Output "Polling for module import completion"
                    Start-Sleep -Seconds 10
                    $AutomationModule = $AutomationModule | Get-AzureRmAutomationModule
                }

                if($AutomationModule.ProvisioningState -eq "Failed") {
                    Write-Error "Importing $ModuleName module to Automation failed."
                }
                else {
                    Write-Output "Importing $ModuleName module to Automation succeeded."
                }
            }
        }
    }

    Function Get-CurrentJob {
        $AutomationAccounts = Find-AzureRmResource -ResourceType 'Microsoft.Automation/AutomationAccounts'

        foreach ($AutomationAccount in $AutomationAccounts) {
            $CurrentJob = Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
            if (!([string]::IsNullOrEmpty($CurrentJob))) { Break; }
        }
        $CurrentJob
    }

# Validate input parameters
if ($ResourceGroupName -xor $AutomationAccountName) {
    throw "ResourceGroupName and AutomationAccountName parameters must either be both populated or neither populated."
}

Write-Output ("Logging into Azure...")
# Login to Azure, assuming Azure Run As account
# Modify below segment if you want to authenticate in a different way
# =================================================
$ServicePrincipalConnection=Get-AutomationConnection -Name "AzureRunAsConnection"         

Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $ServicePrincipalConnection.TenantId `
    -ApplicationId $ServicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint | Format-List

# Just in case our service principal has been granted rights in other
# subscriptions we'll purposely set the context.
Write-Output ("Selecting the Azure subscription configured in our connection...")
Select-AzureRmSubscription -SubscriptionId $ServicePrincipalConnection.SubscriptionId | Format-List
# =================================================

if (!($ResourceGroupName)) { 
    Write-Output ("Retrieving resource group name and automation account name from current automation job details.")
    $CurrentJob = Get-CurrentJob
    $CurrentJob | Format-List

    $ResourceGroupName = $CurrentJob.ResourceGroupName 
    $AutomationAccountName = $CurrentJob.AutomationAccountName
}

# Update existing Azure RM modules
$ExistingModules = Get-AzureRmAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
                    | where {$_.Name -match "Azure"} | select Name

Write-Output ("Modules found...")
$ExistingModules.Name

foreach ($Module in $ExistingModules) 
{

    Write-Output ("Updating existing module {0} to latest..." -f $Module.Name)
    _doImport `
        -ResourceGroupName $CurrentJob.ResourceGroupName `
        -AutomationAccountName $CurrentJob.AutomationAccountName `
        -ModuleName $Module.Name

}

Write-Output ("Completed.")
