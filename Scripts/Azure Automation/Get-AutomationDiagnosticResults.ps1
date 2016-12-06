<#
### NOT FINISHED YET

.SYNOPSIS
    Get information about Azure Automation accounts.

.DESCRIPTION

.PARAMETER ResourceGroupName

.PARAMETER AutomationAccountName

.EXAMPLE

.NOTES
    AUTHOR  : Jeffrey Fanjoy
    LASTEDIT: 12/05/2016
#>

Param (
    [Parameter(Mandatory=$false)]
    [string] $AutomationAccountName,
    [Parameter(Mandatory=$false)]
    [int] $NumberOfJobs = 100
)

    Function CreateFolder {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $FolderName
        )

        if (!(Test-Path -Path $FolderName)) {
            Write-Host ("Creating folder '{0}'." -f $FolderName)
            $null = New-Item -ItemType Directory -Path $FolderName
        }
    }

    Function CreateResultFolder {
        $script:BasePath = $env:TEMP
        Write-Host ("Setting BasePath = {0}." -f $BasePath)
        $script:AzureAutomationDiagBasePath = ("{0}\AzureAutomationDiagnostics" -f $BasePath)
        Write-Host ("Setting azure automation base diagnostics path '{0}'." -f $AzureAutomationDiagBasePath)
        CreateFolder $AzureAutomationDiagBasePath
        $script:AzureAutomationDiagResultPath = ("{0}\{1}" -f $AzureAutomationDiagBasePath, (Get-Date -Format 'yyyyMMddHHmmss'))
        Write-Host ("Setting azure automation diagnostics results folder '{0}'." -f $AzureAutomationDiagResultPath)
        CreateFolder $AzureAutomationDiagResultPath
    }

    Function WriteModuleDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of modules imported into Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $ModuleList = Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        $Modules = @()
        foreach ($Module in $ModuleList) {
            Write-Host ("Getting details for module '{0}'." -f $Module.Name)
            $Modules += Get-AzureRmAutomationModule -Name $Module.Name -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        }
        Write-Host ("Writing module details to '{0}\Modules.txt'." -f $ResultsFolder)
        $Modules | Format-Table -AutoSize | Out-String -Width 8000 | Out-File ("{0}\Modules.txt" -f $ResultsFolder) -Encoding ascii -Append -Force
    }

    Function WriteRunbookDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )
        
        Write-Host ("Retrieving list of runbooks imported into Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $RunbooksList = Get-AzureRmAutomationRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        $Runbooks = @()
        $RunbooksList | ForEach-Object {
            Write-Host ("Getting details for runbook '{0}'." -f $_.Name)
            $Runbooks += Get-AzureRmAutomationRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName -Name $_.Name
        }
        Write-Host ("Writing runbook summary to '{0}\RunbooksSummary.txt'." -f $ResultsFolder)
        $Runbooks | Sort-Object Name | Select-Object Name, RunbookType, State, JobCount, Location, CreationTime, LastModifiedTime, LastModifiedBy, LogVerbose, LogProgress | Format-Table -AutoSize | Out-String -Width 8000 | Out-File ("{0}\RunbooksSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
        Write-Host ("Writing runbook details in JSON to '{0}\RunbooksJSON.txt'." -f $ResultsFolder)
        $Runbooks | Sort-Object Name | ConvertTo-Json | Out-File ("{0}\RunbooksJSON.txt" -f $ResultsFolder) -Encoding ascii -Force
    }

    Function WriteScheduleDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )
    }

# Make sure required modules are available
Write-Host ("Checking for required modules.")
$RequiredModules = @('AzureRM.profile', 'AzureRM.automation', 'AzureRM.resources')
$ModuleMissing = $false
foreach ($Module in $RequiredModules) {
    Write-Host ("Checking for module '{0}'." -f $Module)
    if (!(Get-Module -Name $Module -ListAvailable)) { 
        Write-Host ("Module '{0}' was not found." -f $Module) -ForegroundColor Red
        $ModuleMissing = $true 
    }
}
if ($ModuleMissing -eq $true) { throw 'At least one required module was not found.  See "https://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/" for details on how to install Azure modules for PowerShell.' }

# Login to Azure.
Write-Host ("Prompting user to login to Azure.")
Login-AzureRmAccount

# Select subscription if more than one is available
Write-Host ("Selecting desired Azure Subscription.")
$Subscriptions = Get-AzureRmSubscription
switch (($Subscriptions | Measure-Object).Count) {
    0 { throw "No subscriptions found." }
    1 { 
        $Subscription = $Subscriptions[0] 
        $AzureContext = Get-AzureRmContext
    }
    default { 
        Write-Host ("Multiple Subscriptions found, prompting user to select desired Azure Subscription.")
        $Subscription = ($Subscriptions | Out-GridView -Title 'Select Azure Subscription' -PassThru)
        $AzureContext = Select-AzureRmSubscription -SubscriptionId $Subscription.SubscriptionId
    }
}
Write-Host ("Subscription successfully selected.")
$AzureContext | Format-List

if ($AutomationAccountName) {
    Write-Host ("Scoping results down to Automation account '{0}'." -f $AutomationAccountName)
    $AutomationAccountsResults = Get-AzureRmAutomationAccount | Where-Object { $_.AutomationAccountName -eq $AutomationAccountName }
} else {
    Write-Host ("Retrieving list of Automation accounts.")
    $AutomationAccountsResults = Get-AzureRmAutomationAccount | Sort-Object AutomationAccountName
}

# Retrieve all details for each automation account
$AutomationAccounts = @()
$AutomationAccountsResults | ForEach-Object {
    Write-Host ("Getting details for Automation account '{0}'." -f $_.AutomationAccountName)
    $AutomationAccounts += Get-AzureRmAutomationAccount -ResourceGroupName $_.ResourceGroupName -Name $_.AutomationAccountName
}

Write-Host ("Creating folders for diagnostic results.")
CreateResultFolder

$AutomationAccountsResultsFile = ("{0}\AutomationAccounts.txt" -f $AzureAutomationDiagResultPath)
Write-Host ("Writing Azure automation account details to '{0}'." -f $AutomationAccountsResultsFile)
$AutomationAccounts | Format-Table -AutoSize | Out-String -Width 8000 | Out-File $AutomationAccountsResultsFile -Encoding ascii -Force

# Enumerate through the Automation accounts
$AutomationAccounts | ForEach-Object {
    $AutomationAccountResultFolder = ("{0}\{1}" -f $AzureAutomationDiagResultPath, $_.AutomationAccountName)
    CreateFolder $AutomationAccountResultFolder

    WriteModuleDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteRunbookDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
}

# Get a list of all the jobs
$Jobs = Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName | Sort-Object CreationTime | Select-Object -Last $NumberOfJobs | Sort-Object CreationTime -Descending

# Populate the job history records
$JobHistoryRecords = @()
foreach ($Job in $Jobs) {
    $Job = Get-AzureRmAutomationJob -ResourceGroupName $Job.ResourceGroupName -AutomationAccountName $Job.AutomationAccountName -Id $Job.JobId
    $Streams = $Job | Get-AzureRmAutomationJobOutput -Stream Any | Sort-Object StreamRecordId
    if (($Streams | Measure-Object).Count -gt 0) {
        foreach ($Stream in $Streams) {
            $JobHistoryRecord = $Job
            $OutputRecord = $Stream | Get-AzureRmAutomationJobOutputRecord
            Add-Member -InputObject $JobHistoryRecord -MemberType NoteProperty -Name StreamRecordId -Value $OutputRecord.StreamRecordId -Force
            Add-Member -InputObject $JobHistoryRecord -MemberType NoteProperty -Name StreamTime -Value $OutputRecord.Time -Force
            Add-Member -InputObject $JobHistoryRecord -MemberType NoteProperty -Name StreamType -Value $OutputRecord.Type -Force
            Add-Member -InputObject $JobHistoryRecord -MemberType NoteProperty -Name StreamSummary -Value $OutputRecord.Summary -Force
            Add-Member -InputObject $JobHistoryRecord -MemberType NoteProperty -Name StreamValue -Value ($OutputRecord.Value | ConvertTo-Json) -Force
            $JobHistoryRecords += $JobHistoryRecord | Select-Object ResourceGroupName, AutomationAccountName, RunbookName, JobId, Status, StatusDetails, Exception, CreatedTime, StartTime, EndTime, LastModifiedTime, LastModifiedStatusTime, @{Name="JobParameters";Expression={$_.JobParameters | ConvertTo-Json}}, HybridWorker, StreamRecordId, StreamTime, StreamType, StreamSummary, StreamValue
        }
    } else {
        $JobHistoryRecord = $Job
        $JobHistoryRecords += $JobHistoryRecord | Select-Object ResourceGroupName, AutomationAccountName, RunbookName, JobId, Status, StatusDetails, Exception, CreatedTime, StartTime, EndTime, LastModifiedTime, LastModifiedStatusTime, @{Name="JobParameters";Expression={$_.JobParameters | ConvertTo-Json}}, HybridWorker
    }
}
