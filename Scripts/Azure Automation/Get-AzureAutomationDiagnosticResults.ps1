
<#PSScriptInfo

.VERSION 1.1.2.1

.GUID 5922fab0-f90c-41a8-a59b-be5409271e6e

.AUTHOR Jeffrey Fanjoy

.COMPANYNAME 

.COPYRIGHT 

.TAGS Azure Automation AzureAutomationNotSupported

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES

#>

<# 

.DESCRIPTION 
Capture diagnostic information for Azure Automation accounts. 

NOTE: While the script is for Azure Automation, it is not supported to run in Azure Automation.

#> 

<#
.SYNOPSIS
    Get information about Azure Automation accounts and the content.

.DESCRIPTION
    This script will enumerate Automation accounts and capture information about
    the account as well as the contents under the account.

    - Details about the Automation account.
    - Details about the Module assets.
    - Details about the Variable assets.
    - Details about the Connection assets.
    - Details about the Credential assets.
    - Details about the Schedule assets.
    - Details about the scheduled runbooks (schedules linked to runbooks).
    - Summary details about each runbook.
    - Export of each runbook.
    - Summary details of last N jobs (see NumberOfJobs parameter).
    - Summary details of job stream data for last N jobs.
    - Details of job stream values data (Error streams only by default, see 
      IncludeAllStreamValues parameter).

    Results will be written to $env:TEMP\AzureAutomationDiagnostics\yyyyMMddHHmmss.
    The script will open File Explorer to that location when it has completed.

.PARAMETER Environment
    Optional.  Identifies the Azure environment that is to be used.  By default the
    environment AzureCloud is used.

    Available options are:

        - AzureCloud
        - AzureUSGovernment

.PARAMETER AutomationAccountNames
    Optional.  An array of Automation account names to be processed.  By default
    all Automation accounts in the subscription will be included.

.PARAMETER RunbookNames
    Optional.  An array of Runbook names to be processed.  By default all Runbooks
    in each Automation account are included.  Since Runbooks are referenced by
    name, if the same Runbook name exists in more than one Automation account it
    will be processed in each account.

.PARAMETER JobIds
    Optional.  An array of Job identifiers to be processed.  By default the last N
    Jobs in each Automation account are included (see NumberOfJobs parameter).  If
    Job identifiers are provided, then only Jobs matching those identifiers will be
    processed even across all Automation accounts.  Result may be that some 
    Automation accounts have no Jobs included in the results because they didn't 
    have any matching Jobs.

.PARAMETER IncludeAllStreamValues
    Optional.  By default, stream values are only included for "Error" streams.  The
    summary of all job streams is captured, but capturing the full values of streams
    is a very performance intensive process as it has to make a web service call for
    every stream.

    THIS PARAMETER CAN CAUSE THE SCRIPT TO TAKE A VERY LONG TIME TO COMPLETE IF OTHER
    PARAMETERS ARE NOT INCLUDED TO SCOPE DOWN THE RUNBOOKS/JOBS THAT ARE PROCESSED.

.PARAMETER NumberOfJobs
    Optional.  By default, the last 5 jobs for each runbook in each Automation
    account are processed.  This parameter defines the last N jobs that will be 
    processed for each runbook.

.PARAMETER NumberOfDays
    Optional.  By default, the last 7 days of jobs are processed.  This parameter
    defines the last N days of jobs that will be processed.

.EXAMPLE
    .\Get-AutomationDiagnosticResults.ps1

    The above will process all Automation accounts, Runbooks and last N Jobs in the 
    chosen subscription.

.EXAMPLE
    .\Get-AutomationDiagnosticResults.ps1 -AutomationAccounts 'MyAutomationAccount'

    The above will process all Runbooks and last N Jobs in the Automation account
    named 'MyAutomationAccount' only.

.EXAMPLE
    .\Get-AutomationDiagnosticResults.ps1 -AutomationAccounts @('MyFirstAutomationAccount','MySecondAutomationAccount') -NumberOfJobs 20 -IncludeAllStreamValues

    The above will process all Runbooks and last 20 Jobs in the Automation accounts
    'MyFirstAutomationAccount' and 'MySecondAutomationAccount' and will include full
    stream values for all stream types for each of the last 20 Jobs.

.EXAMPLE
    .\Get-AutomationDiagnosticResults.ps1 -RunbookNames 'MyRunbook'

    The above will process only runbooks named 'MyRunbook' in each of the Automation
    accounts and will only include Job results for that runbook.  Summary details
    about all the Automation accounts will still be included such as Module and
    Schedule assets.

.EXAMPLE
    .\Get-AutomationDiagnosticResults.ps1 -AutomationAccountNames 'MyAutomationAccount' -RunbookNames @('MyFirstRunbook','MySecondRunbook')
    
    The above will process only Runbooks named 'MyFirstRunbook' and 'MySecondRunbook'
    in the Automation account 'MyAutomationAccount'.  Summary details about the
    Automation account 'MyAutomationAccount' will also be included.

.EXAMPLE
    .\Get-AutomationDiagnosticResults.ps1 -AutomationAccountNames 'MyAutomationAccount' -RunbookName 'MyRunbook' -JobIds '12345678-9012-3456-7890-123456789012'

    The above will process only the Job with the specified id and will only include
    information about the Runbook named 'MyRunbook' and only the Automation account
    named 'MyAutomationAccount'.

.NOTES
    AUTHOR  : Jeffrey Fanjoy

    Requires: AzureRM
#>

Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('AzureCloud','AzureUSGovernment')]
    [Alias('EnvironmentName')]
    [string] $Environment = 'AzureCloud',
    [Parameter(Mandatory=$false)]
    [string[]] $AutomationAccountNames,
    [Parameter(Mandatory=$false)]
    [string[]] $RunbookNames,
    [Parameter(Mandatory=$false)]
    [string[]] $JobIds,
    [Parameter(Mandatory=$false)]
    [switch] $IncludeAllStreamValues,
    [Parameter(Mandatory=$false)]
    [int] $NumberOfJobs = 5,
    [Parameter(Mandatory=$false)]
    [int] $NumberOfDays = 7
)

    # Assume going in that requirements have been met unless otherwise determined
    $RequirementsMet = $true
    $RequiredModulesMet = $true

    # List of modules that are required
    $Modules = @(
        @{ Name = 'AzureRM.profile'; Version = [System.Version]'3.4.0' }
        @{ Name = 'AzureRM.automation'; Version = [System.Version]'3.4.0' }
        @{ Name = 'AzureRM.resources'; Version = [System.Version]'4.4.0' }
    )

    $AzureManagementBaseUri = 'https://management.azure.com'

    # Check to confirm that dependency modules are installed
    Function CheckDependencyModules {
        Write-Host ("Checking for presence of required modules.")
        foreach ($Module in $Modules) {
            if ([string]::IsNullOrEmpty($Module.Version)) {
                Write-Host ("Checking for module '{0}'." -f $Module.Name)
            } else {
                Write-Host ("Checking for module '{0}' of at least version '{1}'." -f $Module.Name, $Module.Version)
            }
            $LatestVersion = (Find-Module -Name $Module.Name).Version
            $CurrentModule = Get-Module -Name $Module.Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
            if ($CurrentModule) {
                Write-Host ("Found version '{0}' of module '{1}' installed." -f $CurrentModule.Version, $CurrentModule.Name)
                if ($LatestVersion) {
                    if ($LatestVersion.Version -gt $CurrentModule.Version) {
                        Write-Host ("There is a newer version of module '{0}'.  Version '{1}' is available." -f $LatestVersion.Name, $LatestVersion.Version)
                    }
                }
                if ($CurrentModule.Version -lt $Module.Version) {
                    Write-Error ("Installed version '{0}' of module '{1}' does not meet minimum requirements." -f $CurrentModule.Version, $CurrentModule.Name)
                    $script:RequirementsMet = $false
                    $script:RequiredModulesMet = $false
                }
            } else {
                Write-Error ("Could not find module '{0}' installed." -f $Module.Name)
                $script:RequirementsMet = $false
                $script:RequiredModulesMet = $false
            }
        }
    }

    Function CheckDependencies {
        Write-Host ("Checking for dependencies.")
        CheckDependencyModules
    }

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
        Write-Host ("Creating folders for diagnostic results.")
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
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of modules imported into Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $ModuleList = Get-AzureRmAutomationModule -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($ModuleList | Measure-Object).Count -eq 0) {
            Write-Host ("No modules found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' module(s) in Automation account '{1}'." -f ($ModuleList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            $Modules = @()
            $ModuleList | ForEach-Object {
                Write-Host ("Getting details for module '{0}'." -f $_.Name)
                $Modules += Get-AzureRmAutomationModule -Name $_.Name -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName
            }
            Write-Host ("Writing module summary to '{0}\ModulesSummary.txt'." -f $ResultsFolder)
            $Modules | Sort-Object Name | Select-Object Name, IsGlobal, ProvisioningState, Version, SizeInBytes, ActivityCount, CreationTime, LastModifiedTime | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\ModulesSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing module summary in CSV to '{0}\ModulesSummary.csv'." -f $ResultsFolder)
            $Modules | Sort-Object Name | Select-Object Name, IsGlobal, ProvisioningState, Version, SizeInBytes, ActivityCount, CreationTime, LastModifiedTime | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\ModulesSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteRunbookDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )
        
        Write-Host ("Retrieving list of runbooks imported into Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        if ($RunbookNames) {
            $RunbookNames | ForEach-Object { Write-Host ("Scoping results to include runbook named '{0}'." -f $_) }
            $RunbooksList = Get-AzureRmAutomationRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName | Where-Object { $RunbookNames -contains $_.Name }
        } else {
            $RunbooksList = Get-AzureRmAutomationRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        }
        if (($RunbooksList | Measure-Object).Count -eq 0) {
            Write-Host ("No runbooks found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' runbook(s) in Automation account '{1}'." -f ($RunbooksList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            $Runbooks = @()
            $RunbooksList | ForEach-Object {
                Write-Host ("Getting details for runbook '{0}'." -f $_.Name)
                $Runbooks += Get-AzureRmAutomationRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName -Name $_.Name
            }
            Write-Host ("Writing runbook summary to '{0}\RunbooksSummary.txt'." -f $ResultsFolder)
            $Runbooks | Sort-Object Name | Select-Object Name, RunbookType, State, JobCount, Location, CreationTime, LastModifiedTime, LastModifiedBy, LogVerbose, LogProgress | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\RunbooksSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing runbook summary in CSV to '{0}\RunbooksSummary.csv'." -f $ResultsFolder)
            $Runbooks | Sort-Object Name | Select-Object Name, RunbookType, State, JobCount, Location, CreationTime, LastModifiedTime, LastModifiedBy, LogVerbose, LogProgress | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\RunbooksSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing runbook details in JSON to '{0}\RunbooksJSON.txt'." -f $ResultsFolder)
            $Runbooks | Sort-Object Name | ConvertTo-Json -Depth 10 | Out-File ("{0}\RunbooksJSON.txt" -f $ResultsFolder) -Encoding ascii -Force

            # Exporting runbooks
            $RunbookExportsResultFolder = ("{0}\RunbookExports" -f $AutomationAccountResultFolder)
            CreateFolder $RunbookExportsResultFolder
            $RunbookExportsPublishedResultFolder = ("{0}\Published" -f $RunbookExportsResultFolder)
            CreateFolder $RunbookExportsPublishedResultFolder
            $RunbookExportsDraftResultFolder = ("{0}\Draft" -f $RunbookExportsResultFolder)
            CreateFolder $RunbookExportsDraftResultFolder
            Write-Host ("Exporting published runbooks to folder '{0}'." -f $RunbookExportsPublishedResultFolder)
            $Runbooks | Where-Object { $_.State -ne 'New' } | ForEach-Object {
                Write-Host ("Exporting published version of runbook '{0}' to '{1}'." -f $_.Name, $RunbookExportsPublishedResultFolder)
                $null = Export-AzureRmAutomationRunbook -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName -Name $_.Name -Slot Published -OutputFolder $RunbookExportsPublishedResultFolder -Force
            }
            Write-Host ("Exporting draft runbooks to folder '{0}'." -f $RunbookExportsPublishedResultFolder)
            $Runbooks | Where-Object { $_.State -ne 'Published' } | ForEach-Object {
                Write-Host ("Exporting draft version of runbook '{0}' to '{1}'." -f $_.Name, $RunbookExportsDraftResultFolder)
                $null = Export-AzureRmAutomationRunbook -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName -Name $_.Name -Slot Draft -OutputFolder $RunbookExportsDraftResultFolder -Force
            }
        }
    }

    Function WriteScheduleDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of schedules in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $ScheduleList = Get-AzureRmAutomationSchedule -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($ScheduleList | Measure-Object).Count -eq 0) {
            Write-Host ("No schedules found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' schedule(s) in Automation account '{1}'." -f ($ScheduleList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            $Schedules = @()
            $ScheduleList | ForEach-Object {
                Write-Host ("Getting details for schedule '{0}'." -f $_.Name)
                $Schedules += Get-AzureRmAutomationSchedule -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName -Name $_.Name
            }
            Write-Host ("Writing schedule summary to '{0}\SchedulesSummary.txt'." -f $ResultsFolder)
            $Schedules | Sort-Object Name | Select-Object Name, IsEnabled, StartTime, ExpiryTime, NextRun, Interval, Frequency, TimeZone, CreationTime, LastModifiedTime | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\SchedulesSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing schedule summary in CSV to '{0}\SchedulesSummary.csv'." -f $ResultsFolder)
            $Schedules | Sort-Object Name | Select-Object Name, IsEnabled, StartTime, ExpiryTime, NextRun, Interval, Frequency, TimeZone, CreationTime, LastModifiedTime | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\SchedulesSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing schedule details in JSON to '{0}\SchedulesJSON.txt'." -f $ResultsFolder)
            $Schedules | Sort-Object Name | ConvertTo-Json -Depth 10 | Out-File ("{0}\SchedulesJSON.txt" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteScheduledRunbookDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of scheduled runbooks in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $ScheduledRunbookList = Get-AzureRmAutomationScheduledRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($ScheduledRunbookList | Measure-Object).Count -eq 0) {
            Write-Host ("No scheduled runbooks found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' scheduled runbook(s) in Automation account '{1}'." -f ($ScheduledRunbookList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            $ScheduledRunbooks = @()
            $ScheduledRunbookList | ForEach-Object {
                Write-Host ("Getting details for scheduled runbook job schedule id '{0}' of schedule '{1}' against runbook '{2}'." -f $_.JobScheduleId, $_.ScheduleName, $_.RunbookName)
                $ScheduledRunbooks += Get-AzureRmAutomationScheduledRunbook -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName -JobScheduleId $_.JobScheduleId
            }
            Write-Host ("Writing scheduled job summary to '{0}\ScheduledRunbooksSummary.txt'." -f $ResultsFolder)
            $ScheduledRunbooks | Sort-Object ScheduleName | Select-Object ScheduleName, RunbookName, JobScheduleId, RunOn | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\ScheduledRunbooksSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing scheduled job summary in CSV to '{0}\ScheduledRunbooksSummary.csv'." -f $ResultsFolder)
            $ScheduledRunbooks | Sort-Object ScheduleName | Select-Object ScheduleName, RunbookName, JobScheduleId, RunOn | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\ScheduledRunbooksSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing scheduled job details in JSON to '{0}\ScheduledRunbooksJSON.txt'." -f $ResultsFolder)
            $ScheduledRunbooks | Sort-Object ScheduleName | ConvertTo-Json -Depth 10 | Out-File ("{0}\ScheduledRunbooksJSON.txt" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteVariableDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of variables in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $AutomationVariables = Get-AzureRmAutomationVariable -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($AutomationVariables | Measure-Object).Count -eq 0) {
            Write-Host ("No variables found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' variable(s) in Automation account '{1}'." -f ($AutomationVariables | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            Write-Host ("Writing variables summary to '{0}\VariablesSummary.txt'." -f $ResultsFolder)
            $AutomationVariables | Sort-Object Name | Select-Object Name, Encrypted, Value, CreationTime, LastModifiedTime, Description | Format-Table -AutoSize | Out-String -Width 8000 | Out-File ("{0}\VariablesSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing variables summary in CSV to '{0}\VariablesSummary.csv'." -f $ResultsFolder)
            $AutomationVariables | Sort-Object Name | Select-Object Name, Encrypted, Value, CreationTime, LastModifiedTime, Description | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\VariablesSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteCredentialDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of credentials in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $AutomationCredentials = Get-AzureRmAutomationCredential -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($AutomationCredentials | Measure-Object).Count -eq 0) {
            Write-Host ("No credentials found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' credential(s) in Automation account '{1}'." -f ($AutomationCredentials | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            Write-Host ("Writing credentials summary to '{0}\CredentialsSummary.txt'." -f $ResultsFolder)
            $AutomationCredentials | Sort-Object Name | Select-Object Name, UserName, CreationTime, LastModifiedTime, Description | Format-Table -AutoSize | Out-String -Width 8000 | Out-File ("{0}\CredentialsSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing credentials summary in CSV to '{0}\CredentialsSummary.csv'." -f $ResultsFolder)
            $AutomationCredentials | Sort-Object Name | Select-Object Name, UserName, CreationTime, LastModifiedTime, Description | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\CredentialsSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteCertificateDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of certificates in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $AutomationCertificates = Get-AzureRmAutomationCertificate -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($AutomationCertificates | Measure-Object).Count -eq 0) {
            Write-Host ("No certificates found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' certificate(s) in Automation account '{1}'." -f ($AutomationCertificates | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            Write-Host ("Writing certificates summary to '{0}\CertificatesSummary.txt'." -f $ResultsFolder)
            $AutomationCertificates | Sort-Object Name | Select-Object Name, Exportable, ExpiryTime, Thumbprint, CreationTime, LastModifiedTime, Description | Format-Table -AutoSize | Out-String -Width 8000 | Out-File ("{0}\CertificatesSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing certificates summary in CSV to '{0}\CertificatesSummary.csv'." -f $ResultsFolder)
            $AutomationCertificates | Sort-Object Name | Select-Object Name, Exportable, ExpiryTime, Thumbprint, CreationTime, LastModifiedTime, Description | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\CertificatesSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteConnectionDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of connections in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $ConnectionList = Get-AzureRmAutomationConnection -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($ConnectionList | Measure-Object).Count -eq 0) {
            Write-Host ("No connections found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' connection(s) in Automation account '{1}'." -f ($ConnectionList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            $Connections = @()
            $ConnectionList | ForEach-Object {
                Write-Host ("Getting details for connection '{0}'." -f $_.Name)
                $Connections += Get-AzureRmAutomationConnection -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName -Name $_.Name
            }
            Write-Host ("Writing connection summary to '{0}\ConnectionsSummary.txt'." -f $ResultsFolder)
            $Connections | Sort-Object Name | Select-Object Name, ConnectionTypeName, CreationTime, LastModifiedTime | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\ConnectionsSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing connection summary in CSV to '{0}\ConnectionsSummary.csv'." -f $ResultsFolder)
            $Connections | Sort-Object Name | Select-Object Name, ConnectionTypeName, CreationTime, LastModifiedTime | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\ConnectionsSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing connection details in JSON to '{0}\ConnectionsJSON.txt'." -f $ResultsFolder)
            $Connections | Sort-Object Name | ConvertTo-Json -Depth 10 | Out-File ("{0}\ConnectionsJSON.txt" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteJobDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of runbooks imported into Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        if ($RunbookNames) {
            $RunbookNames | ForEach-Object { Write-Host ("Scoping results to include runbook named '{0}'." -f $_) }
            $RunbooksList = Get-AzureRmAutomationRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName | Where-Object { $RunbookNames -contains $_.Name }
        } else {
            $RunbooksList = Get-AzureRmAutomationRunbook -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName 
        }
        Write-Host ("Found '{0}' runbook(s) in Automation account '{1}'." -f ($RunbooksList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
        $JobsList = @()
        If ($JobIds) {
            foreach ($JobId in $JobIds) {
                Write-Host ("Scoping results to include job id '{0}'." -f $JobId)
                $JobsList += Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName -Id $JobId
            }
            Write-Host ("Retrieved a total of '{0}' job(s) from Automation account '{1}'." -f ($JobsList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Retrieving jobs that have executed in the last '{0}' day(s) from Automation account '{1}'." -f $NumberOfDays, $AutomationAccount.AutomationAccountName)
            $JobsLastNDays = Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName -StartTime ((Get-Date).AddDays(-$NumberOfDays)) 
            Write-Host ("Retrieved a total of '{0}' job(s) from Automation account '{1}'." -f ($JobsLastNDays | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            foreach ($Runbook in $RunbooksList) {
                Write-Host ("Filtering last '{0}' job(s) for runbook '{1}' in Automation account '{2}' having executed in the last '{3}' day(s)." -f $NumberOfJobs, $Runbook.Name, $AutomationAccount.AUtomationAccountName, $NumberOfDays)
                $RunbookJobsList = $JobsLastNDays | Where-Object { $_.RunbookName -eq $Runbook.Name } | Sort-Object CreationTime | Select-Object -Last $NumberOfJobs | Sort-Object CreationTime -Descending
                Write-Host ("Filtered '{0}' job(s) for runbook '{1}'." -f ($RunbookJobsList | Measure-Object).Count, $Runbook.Name)
                $JobsList += $RunbookJobsList
            }
            if (!$RunbookNames) {
                Write-Host ("Filtering job(s) from Automation account '{0}' with no attached runbook (e.g. system jobs)." -f $AutomationAccount.AutomationAccountName)
                $OrphanJobs = $JobsLastNDays | Where-Object { $RunbooksList.Name -notcontains $_.RunbookName } | Sort-Object CreationTime | Sort-Object CreationTime -Descending
                Write-Host ("Filtered '{0}' job(s) with no attached runbooks." -f ($OrphanJobs | Measure-Object).Count)
                $JobsList += $OrphanJobs
            }
        }

        if (($JobsList | Measure-Object).Count -eq 0) {
            Write-Host ("No jobs found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Retrieved '{0}' job(s) in Automation account '{1}'." -f ($JobsList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            $Jobs = @()
            $JobsList | Sort-Object CreationTime -Descending | ForEach-Object {
                Write-Host ("Getting details for job id '{0}' of runbook '{1}'." -f $_.JobId, $_.RunbookName)
                $Jobs += Get-AzureRmAutomationJob -ResourceGroupName $_.ResourceGroupname -AutomationAccountName $_.AutomationAccountName -Id $_.JobId
            }
            Write-Host ("Writing job summary to '{0}\JobsSummary.txt'." -f $ResultsFolder)
            $Jobs | Select-Object JobId, RunbookName, Status, StatusDetails, HybridWorker, StartedBy, CreationTime, StartTime, EndTime, @{Name="Duration";Expression={$_.EndTime - $_.StartTime}}, Exception | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\JobsSummary.txt" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing job summary in CSV to '{0}\JobsSummary.csv'." -f $ResultsFolder)
            $Jobs | Select-Object JobId, RunbookName, Status, StatusDetails, HybridWorker, StartedBy, CreationTime, StartTime, EndTime, @{Name="Duration";Expression={$_.EndTime - $_.StartTime}}, Exception | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\JobsSummary.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing job details in JSON to '{0}\JobsJSON.txt'." -f $ResultsFolder)
            $Jobs | Select-Object *, @{Name="Duration";Expression={$_.EndTime - $_.StartTime}} | ConvertTo-Json -Depth 10 | Out-File ("{0}\JobsJSON.txt" -f $ResultsFolder) -Encoding ascii -Force

            # Process each job to capture job stream data
            $Jobs | Select-Object *, @{Name="Duration";Expression={$_.EndTime - $_.StartTime}}  | ForEach-Object {
                Write-Host ("Retrieving job streams for job id '{0}' of runbook '{1}'." -f $_.JobId, $_.RunbookName)
                $Uri = ("{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Automation/automationAccounts/{3}/jobs/{4}/streams?api-version=2015-10-31" -f $AzureManagementBaseUri, $AutomationAccount.SubscriptionId, $AutomationAccount.ResourceGroupName, $AutomationAccount.AutomationAccountName, $_.JobId)
                Write-Host ("Retrieving job stream data from '{0}'." -f $Uri)
                $results = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
                Write-Host ("Found '{0}' streams for job id '{1}'." -f $results.value.Count, $_.JobId)
                if (($results.value | Measure-Object).Count -gt 0) {
                    Write-Host ("Retrieving stream details.  This may take some time.")
                    $Streams = @()
                    foreach ($stream in $results.value) {
                        $Uri = ("https://management.azure.com{0}?api-version=2015-10-31" -f $stream.id)
                        $StreamResults = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
                        $Streams += $StreamResults.properties
                    }

                    # Add the data from this job to the output and all streams reports
                    $ReportHeader = @"
#########################################################################################################
START OF STREAM DATA
          Job Id: $($_.JobId)
    Runbook name: $($_.RunbookName)
          Status: $($_.Status)
  Status Details: $($_.StatusDetails)
   Hybrid Worker: $($_.HybridWorker)
   Creation Time: $($_.CreationTime)
      Start Time: $($_.StartTime)
        End Time: $($_.EndTime)
        Duration: $($_.Duration)
       Exception: $($_.Exception)
#########################################################################################################

"@

                    $ReportFooter = @"

#########################################################################################################
END OF STREAM DATA
          Job Id: $($_.JobId)
    Runbook name: $($_.RunbookName)
#########################################################################################################

"@

                    Write-Host ("Adding stream data for job id '{0}' to '{1}\JobsStreamsOutput.txt'." -f $_.JobId, $ResultsFolder)
                    $ReportHeader | Out-File ("{0}\JobsStreamsOutput.txt" -f $ResultsFolder) -Encoding ascii -Append
                    ($Streams | Where-Object { $_.streamType -eq 'Output' } | Select-Object jobStreamId, time, streamType, streamText | Sort-Object jobStreamId).streamText | Out-File ("{0}\JobsStreamsOutput.txt" -f $ResultsFolder) -Encoding ascii -Append
                    $ReportFooter | Out-File ("{0}\JobsStreamsOutput.txt" -f $ResultsFolder) -Encoding ascii -Append
                    Write-Host ("Adding stream data for job id '{0}' to '{1}\JobsStreamsAllStreams.txt'." -f $_.JobId, $ResultsFolder)
                    $ReportHeader | Out-File ("{0}\JobsStreamsAllStreams.txt" -f $ResultsFolder) -Encoding ascii -Append
                    $Streams | Select-Object jobStreamId, time, streamType, streamText | Sort-Object jobStreamId | Format-List | Out-File ("{0}\JobsStreamsAllStreams.txt" -f $ResultsFolder) -Encoding ascii -Append
                    $ReportFooter | Out-File ("{0}\JobsStreamsAllStreams.txt" -f $ResultsFolder) -Encoding ascii -Append
                }
            }
        }
    }

    Function WriteHybridWorkerDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [object] $AutomationAccount,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Retrieving list of hybrid worker groups registered in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        $Uri = ("https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}/hybridRunbookWorkerGroups?api-version=2015-10-31" -f $AutomationAccount.SubscriptionId, $AutomationAccount.ResourceGroupName, $AutomationAccount.AutomationAccountName)
        Write-Host ("Retrieving Hybrid Worker data from '{0}'." -f $Uri)
        $results = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
        $HWGList = $results.value
        # $HWGList = Get-AzureRmAutomationHybridWorkerGroup -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.AutomationAccountName
        if (($HWGList | Measure-Object).Count -eq 0) {
            Write-Host ("No hybrid worker groups found in Automation account '{0}'." -f $AutomationAccount.AutomationAccountName)
        } else {
            Write-Host ("Found '{0}' hybrid worker group(s) in Automation account '{1}'." -f ($HWGList | Measure-Object).Count, $AutomationAccount.AutomationAccountName)
            Write-Host ("Writing hybrid worker groups in JSON to '{0}\HybridWorkerGroups.txt'." -f $ResultsFolder)
            $HWGList | Sort-Object Name | ConvertTo-Json -Depth 10 | Out-File ("{0}\HybridWorkerGroups.txt" -f $ResultsFolder) -Encoding ascii -Force
            $HybridWorkers = @()
            $HWGList | ForEach-Object {
                foreach ($worker in $_.hybridRunbookWorkers) {
                    $HybridWorker = New-Object PSObject -Property @{
                        HybridWorkerGroupId    = $_.id
                        HybridWorkerGroupName  = $_.name
                        HybridWorkerGroupType  = $_.groupType
                        Credential             = $_.credential
                        Name                   = $worker.name
                        IP                     = $worker.ip
                        RegistrationTime       = $worker.registrationTime
                        LastSeenTime           = $worker.lastSeenDateTime
                    }
                    $HybridWorkers += $HybridWorker
                }
            }
            Write-Host ("Writing hybrid workers in CSV to '{0}\HybridWorkers.csv'." -f $ResultsFolder)
            $HybridWorkers | Sort-Object HybridWorkerGroupName, Name | Select-Object HybridWorkerGroupName, HybridWorkerGroupType, Name, IP, RegistrationTime, LastSeenTime, Credential, HybridWorkerGroupId | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\HybridWorkers.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing hybrid workers to '{0}\HybridWorkers.txt'." -f $ResultsFolder)
            $HybridWorkers | Sort-Object HybridWorkerGroupName, Name | Select-Object HybridWorkerGroupName, HybridWorkerGroupType, Name, IP, RegistrationTime, LastSeenTime, Credential, HybridWorkerGroupId | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\HybridWorkers.txt" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function GetAzureAccessToken {
        Param ()

        $context = Get-AzureRmContext
        $token = ($context.TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $context.Tenant.Id })[-1]
        if (($token.ExpiresOn.UtcDateTime.AddMinutes(-5)) -le ((Get-Date).ToUniversalTime())) {
            Write-Host ("Executing benign PowerShell statement in an attempt to refresh access token.")
            $null = Get-AzureRmSubscription
            $token = ($context.TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $context.Tenant.Id })[-1]
        }
        $token.AccessToken
    }

    Function GetAuthorizationHeader {
        Param ()

        $AccessToken = GetAzureAccessToken
        ("Bearer {0}" -f $AccessToken)
    }

    Function BuildHeaders {
        Param ()

        @{
            Authorization = GetAuthorizationHeader
        }
    }
    Function GetLinkedWorkspaceFromAutomationAccount {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $SubscriptionId,
            [Parameter(Mandatory=$true)]
            [string] $ResourceGroupName,
            [Parameter(Mandatory=$true)]
            [string] $AutomationAccountName
        )

        $Uri = ("{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Automation/automationAccounts/{3}/linkedWorkspace?api-version=2017-05-15-preview" -f $AzureManagementBaseUri, $SubscriptionId, $ResourceGroupName, $AutomationAccountName)
        Write-Host ("Retrieving Log Analytics linked workspace endpoint (if any) from '{0}'." -f $Uri)
        $results = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
        $results.id
    }

    Function WriteLogAnalyticsWorkspaceDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $WorkspaceResourceUri,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Getting details for Log Analytics workspace '{0}'." -f $WorkspaceResourceUri)
        $Uri = ("{0}{1}?api-version=2017-01-01-preview" -f $AzureManagementBaseUri, $WorkspaceResourceUri)
        Write-Host ("Retrieving Log Analytics workspace details from '{0}'." -f $Uri)
        $results = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
        if ($results) {
            Write-Host ("Writing Log Analytics workspace details in JSON to '{0}\LogAnalytics_WorkspaceDetails.txt'." -f $ResultsFolder)
            $results | ConvertTo-Json -Depth 10 | Out-File ("{0}\LogAnalytics_WorkspaceDetails.txt" -f $ResultsFolder) -Encoding ascii -Force
        } else {
            Write-Host ("No workspace details found for workspace '{0}'." -f $WorkspaceResourceUri)
        }
    }

    Function ExecuteLogAnalyticsQuery {
        Param(
            [Parameter(Mandatory=$true)]
            [string] $WorkspaceResourceUri,
            [Parameter(Mandatory=$true)]
            [string] $Query
        )

        $Uri = ("{0}{1}/api/query?api-version=2017-01-01-preview" -f $AzureManagementBaseUri, $WorkspaceResourceUri)
        Write-Host ("Executing Log Analytics query against target '{0}'." -f $Uri)
        $BodyObject = New-Object PSObject -Property @{
            query = $Query
        }
        $Body = $BodyObject | ConvertTo-Json
        $results = Invoke-RestMethod -Method POST -Uri $Uri -Headers (BuildHeaders) -Body $Body -ContentType "application/json" -UseBasicParsing
        $dt = New-Object System.Data.DataTable
        foreach ($col in $results.Tables[0].Columns) {
            $null = $dt.Columns.Add($col.ColumnName)
        }
        foreach ($row in $results.Tables[0].Rows) {
            $null = $dt.Rows.Add($row)
        }
        $dt
    }

    Function WriteLogAnalyticsComputerHeartbeatDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $WorkspaceResourceUri,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        $query = "Heartbeat | summarize arg_max(TimeGenerated,*) by Computer | order by Computer asc"
        Write-Host ("Executing query against Log Analytics workspace '{0}'.  Query: {1}" -f $WorkspaceResourceUri, $query)
        $results = ExecuteLogAnalyticsQuery -WorkspaceResourceUri $WorkspaceResourceUri -Query $query
        Write-Host ("Returned '{0}' record(s)." -f ($results | Measure-Object).Count)
        if (($results | Measure-Object).Count -gt 0) {
            Write-Host ("Writing Computer heartbeat summary in CSV to '{0}\LogAnalytics_ComputerHeartbeats.csv'." -f $ResultsFolder)
            $results | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\LogAnalytics_ComputerHeartbeats.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing Computer heartbeat summary to '{0}\LogAnalytics_ComputerHeartbeats.txt'." -f $ResultsFolder)
            $results | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\LogAnalytics_ComputerHeartbeats.txt" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteLogAnalyticsUpdatesDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $WorkspaceResourceUri,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        $query = @"
Update
| where TimeGenerated>ago(14h) and SourceComputerId in (
    (
        Heartbeat
        | where TimeGenerated>ago(12h) and notempty(Computer)
        | summarize arg_max(TimeGenerated, Solutions) by SourceComputerId
        | where Solutions has "updates"
        | distinct SourceComputerId
    )
)
| summarize hint.strategy=partitioned arg_max(TimeGenerated, *) by Computer, SourceComputerId, Product, ProductArch
| order by Computer asc
"@
        Write-Host ("Executing query against Log Analytics workspace '{0}'.  Query: {1}" -f $WorkspaceResourceUri, $query)
        $results = ExecuteLogAnalyticsQuery -WorkspaceResourceUri $WorkspaceResourceUri -Query $query
        Write-Host ("Returned '{0}' record(s)." -f ($results | Measure-Object).Count)
        if (($results | Measure-Object).Count -gt 0) {
            Write-Host ("Writing updates details in CSV to '{0}\LogAnalytics_Updates.csv'." -f $ResultsFolder)
            $results | ConvertTo-Csv -NoTypeInformation | Out-File ("{0}\LogAnalytics_Updates.csv" -f $ResultsFolder) -Encoding ascii -Force
            Write-Host ("Writing updates details to '{0}\LogAnalytics_Updates.txt'." -f $ResultsFolder)
            $results | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File ("{0}\LogAnalytics_Updates.txt" -f $ResultsFolder) -Encoding ascii -Force
        }
    }

    Function WriteLogAnalyticsUpdatesMicrosoftDefaultComputerGroupDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $WorkspaceResourceUri,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Getting details for Log Analytics saved searches for workspace '{0}'." -f $WorkspaceResourceUri)
        $Uri = ("{0}{1}/savedSearches?api-version=2017-01-01-preview" -f $AzureManagementBaseUri, $WorkspaceResourceUri)
        Write-Host ("Retrieving Log Analytics saved search details from '{0}'." -f $Uri)
        $results = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
        if ($results) {
            Write-Host ("Writing Log Analytics Update Management MicrosoftDefaultComputerGroup saved search details to '{0}\LogAnalytics_SavedSearches.txt'." -f $ResultsFolder)
            $results.value | ConvertTo-Json -Depth 10 | Out-File ("{0}\LogAnalytics_SavedSearches.txt" -f $ResultsFolder) -Encoding ascii -Force
        } else {
            Write-Host ("No saved searches found for workspace '{0}'." -f $WorkspaceResourceUri)
        }
    }

    Function WriteLogAnalyticsScopeConfigurationDetails {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $WorkspaceResourceUri,
            [Parameter(Mandatory=$true)]
            [string] $ResultsFolder
        )

        Write-Host ("Getting details for Log Analytics scope configurations for workspace '{0}'." -f $WorkspaceResourceUri)
        $Uri = ("{0}{1}/configurationScopes?api-version=2015-11-01-preview" -f $AzureManagementBaseUri, $WorkspaceResourceUri)
        Write-Host ("Retrieving Log Analytics scope configuration details from '{0}'." -f $Uri)
        $results = Invoke-RestMethod -Method GET -Uri $Uri -Headers (BuildHeaders) -ContentType "application/json" -UseBasicParsing
        if ($results) {
            Write-Host ("Writing Log Analytics scope configuration details to '{0}\LogAnalytics_ScopeConfigurations.txt'." -f $ResultsFolder)
            $results | Format-List | Out-File ("{0}\LogAnalytics_ScopeConfigurations.txt" -f $ResultsFolder) -Encoding ascii -Force
        } else {
            Write-Host ("No scope configurations found for workspace '{0}'." -f $WorkspaceResourceUri)
        }
    }

$ScriptVersion = '1.1.2.1'

# Create folder structure needed for results
CreateResultFolder
Start-Transcript -Path ("{0}\Transcript.txt" -f $AzureAutomationDiagResultPath)

# Write the script version
Write-Host ("Script version: {0}" -f $ScriptVersion)

# Write the command line that was used when the script was called
Write-Host ("Command line: {0}" -f $MyInvocation.Line)

# Get the current time in UTC
Write-Host ("Current UTC time: {0}" -f [System.DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))

# Confirm that all dependencies are available and if not, install where
# possible
CheckDependencies
if (!$RequirementsMet) { 
    Write-Error ("Script execution aborted as minimum requirements have not been met.  See tracing above for details.") 
    if (!$RequiredModulesMet) {
        Write-Warning ("To install latest version of AzureRM cmdlets, see: https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps")
    }
    Stop-Transcript
    Break
}

# Login to Azure.
Write-Host ("Prompting user to login to Azure environment '{0}'." -f $Environment)
$account = Add-AzureRmAccount -Environment $Environment
if (!($account)) {
    throw ("Unable to successfully authenticate to Azure for environment '{0}'." -f $Environment)
}

# Select subscription if more than one is available
Write-Host ("Selecting desired Azure Subscription.")
$Subscriptions = Get-AzureRmSubscription
Write-Host ("Found {0} subscription(s)." -f ($Subscriptions | Measure-Object).Count)
$Subscriptions | Format-Table -AutoSize | Out-String -Width 8000
switch (($Subscriptions | Measure-Object).Count) {
    0 { throw "No subscriptions found." }
    1 { 
        if ($Subscriptions[0].Id) {
            $AzureContext = Set-AzureRmContext -SubscriptionId $Subscriptions[0].Id
        } else {
            $AzureContext = Set-AzureRmContext -SubscriptionId $Subscriptions[0].SubscriptionId
        }
    }
    default { 
        Write-Host ("Multiple Subscriptions found, prompting user to select desired Azure Subscription.")
        $Subscription = ($Subscriptions | Out-GridView -Title 'Select Azure Subscription' -PassThru)
        if ($Subscription.Id) {
            $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.Id
        } else {
            $AzureContext = Set-AzureRmContext -SubscriptionId $Subscription.SubscriptionId
        }
    }
}
Write-Host ("Subscription successfully selected.")
$AzureContext | Format-List

# Get list of Automation accounts to be processed
if ($AutomationAccountNames) {
    $AutomationAccountNames | ForEach-Object { Write-Host("Scoping results to include Automation account '{0}'." -f $_) }
    $AutomationAccountsResults = Get-AzureRmAutomationAccount | Where-Object { $AutomationAccountNames -contains $_.AutomationAccountName } | Sort-Object AutomationAccountName
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

# Write Automation accounts out to results folder
$AutomationAccountsResultsFile = ("{0}\AutomationAccounts.txt" -f $AzureAutomationDiagResultPath)
Write-Host ("Writing Azure automation account details to '{0}'." -f $AutomationAccountsResultsFile)
$AutomationAccounts | Format-Table * -AutoSize | Out-String -Width 8000 | Out-File $AutomationAccountsResultsFile -Encoding ascii -Force

# Enumerate through the Automation accounts
$AutomationAccounts | ForEach-Object {
    $AutomationAccountResultFolder = ("{0}\{1}" -f $AzureAutomationDiagResultPath, $_.AutomationAccountName)
    CreateFolder $AutomationAccountResultFolder
    WriteModuleDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteRunbookDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteScheduleDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteScheduledRunbookDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteVariableDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteConnectionDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteCertificateDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteCredentialDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteJobDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder
    WriteHybridWorkerDetails -AutomationAccount $_ -ResultsFolder $AutomationAccountResultFolder

    # If there is an associated Log Analytics workspace we can get additional information for
    # features that leverage LA query data such as Update, Change and Inventory management.
    Write-Host ("Checking to see if there is a linked Log Analytics workspace.")
    $WorkspaceResourceId = GetLinkedWorkspaceFromAutomationAccount -SubscriptionId $_.SubscriptionId -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName
    if ($WorkspaceResourceId) {
        Write-Host ("Found linked Log Analytics workspace '{0}'." -f $WorkspaceResourceId)
        WriteLogAnalyticsWorkspaceDetails -WorkspaceResourceUri $WorkspaceResourceId -ResultsFolder $AutomationAccountResultFolder
        WriteLogAnalyticsComputerHeartbeatDetails -WorkspaceResourceUri $WorkspaceResourceId -ResultsFolder $AutomationAccountResultFolder
        WriteLogAnalyticsUpdatesMicrosoftDefaultComputerGroupDetails -WorkspaceResourceUri $WorkspaceResourceId -ResultsFolder $AutomationAccountResultFolder
        WriteLogAnalyticsScopeConfigurationDetails -WorkspaceResourceUri $WorkspaceResourceId -ResultsFolder $AutomationAccountResultFolder
        WriteLogAnalyticsUpdatesDetails -WorkspaceResourceUri $WorkspaceResourceId -ResultsFolder $AutomationAccountResultFolder
    }
}

Write-Host ("Execution completed.")
Stop-Transcript

# Open the diagnostics result path in Explorer
start $AzureAutomationDiagResultPath
