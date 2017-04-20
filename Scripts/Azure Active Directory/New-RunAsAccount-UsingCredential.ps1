Param (
    [Parameter(Mandatory=$true)]
    [String] $ResourceGroup,

    [Parameter(Mandatory=$true)]
    [String] $AutomationAccountName,

    [Parameter(Mandatory=$true)]
    [String] $Location,

    [Parameter(Mandatory=$true)]
    [String] $ApplicationDisplayName,

    [Parameter(Mandatory=$true)]
    [String] $SubscriptionId,

    [Parameter(Mandatory=$true)]
    [String] $AADApplicationPassword,

    [Parameter(Mandatory=$false)]
    [ValidateSet("AzureCloud","AzureUSGovernment")]
    [string]$EnvironmentName="AzureCloud"
)

function CreateServicePrincipalUsingCredential([string] $aADApplicationPassword, [string] $applicationDisplayName) {  

    # Use key credentials and create an Azure AD application
    $Application = New-AzureRmADApplication -DisplayName $applicationDisplayName -HomePage ("http://" + $applicationDisplayName) -IdentifierUris ("http://" + $applicationDisplayName) -Password $aADApplicationPassword
    $ServicePrincipal = New-AzureRMADServicePrincipal -ApplicationId $Application.ApplicationId
    $GetServicePrincipal = Get-AzureRmADServicePrincipal -ObjectId $ServicePrincipal.Id

    # Sleep here for a few seconds to allow the service principal application to become active (ordinarily takes a few seconds)
    Sleep -s 15
    $NewRole = New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
    $Retries = 0;
    While ($NewRole -eq $null -and $Retries -le 6)
    {
        Sleep -s 10
        New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId | Write-Verbose -ErrorAction SilentlyContinue
        $NewRole = Get-AzureRMRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
        $Retries++;
    }
    return $Application.ApplicationId.ToString();
}

function CreateAutomationCredentialAsset ([string] $resourceGroup, [string] $automationAccountName, [string] $credentialAssetName, [string] $aADApplicationId, [string] $aADApplicationPassword ) {
    $User = $aADApplicationId
    $Password = ConvertTo-SecureString $aADApplicationPassword -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password
  
    Remove-AzureRmAutomationCredential -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Name $credentialAssetName -ErrorAction SilentlyContinue
    New-AzureRmAutomationCredential -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Value $Credential -Name $credentialAssetName  | write-verbose
}
  
Import-Module AzureRM.Profile
Import-Module AzureRM.Resources

Login-AzureRmAccount -EnvironmentName $EnvironmentName
$Subscription = Select-AzureRmSubscription -SubscriptionId $SubscriptionId

$GetAzureRmResourceGroup=Get-AzureRmResourceGroup -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
if (!$GetAzureRmResourceGroup)
{
    Write-Host -ForegroundColor Yellow "Resource Group $ResourceGroup not found. Creating resource group...."
    New-AzureRmResourceGroup -ResourceGroupName $ResourceGroup -Location $Location   
}

$GetAzureRmAutomationAccount=Get-AzureRmAutomationAccount -ResourceGroupName $ResourceGroup -Name $AutomationAccountName -ErrorAction SilentlyContinue
if (!$GetAzureRmAutomationAccount)
{
    Write-Host -ForegroundColor Yellow "Automation Account $AutomationAccountName not found in $ResourceGroup. Creating automation account ....."
    New-AzureRmAutomationAccount -ResourceGroupName $ResourceGroup -Name $AutomationAccountName -Location $Location    
}

# Create a Run As account by using a service principal
$CerdentialAssetName = "AzureRunAsCerdential"

# Create a service principal
$ApplicationId = CreateServicePrincipalUsingCredential $AADApplicationPassword $ApplicationDisplayName

# Create an Automation credential asset named AzureRunAsCredentail in the Automation account. 
CreateAutomationCredentialAsset $ResourceGroup $AutomationAccountName $CerdentialAssetName $ApplicationId $AADApplicationPassword

# .\New-RunAsAccount-UsingCredential.ps1 -ResourceGroup Test-SPN-CRED-001-RG -AutomationAccountName Test-SPN-CRED-001 -Location 'East US 2' -ApplicationDisplayName Test-SPN-CRED-001-APPLication -SubscriptionId 632ce1fe-d316-4847-9f7c-919ee2b3bd48 -AADApplicationPassword sco2012. 