$ResourceGroupName = 'Testing1'
$AutomationAccountName = 'Testing1'
$Instances = 10

# Login to Azure for the sake of creating and check status of automation jobs
# Here we are using the run as account but this could be user credentials as well
$servicePrincipalConnection=Get-AutomationConnection -Name 'AzureRunAsConnection'         
Write-Output ("Logging in to Azure...")
Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 

# Create jobs of the child runbook
$Jobs = @()
1..$Instances | ForEach-Object {
    $Parameters = @{
        Value1 = ("Instance {0}, Value 1" -f $_)
        Value2 = ("Instance {0}, Value 2" -f $_)
    }
    $Job = Start-AzureRmAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'ParallelExecutionDemo_Child' -Parameters $Parameters
    Write-Output ("Job with id {0} created." -f $Job.JobId.ToString())
    # Add this job to the list of jobs to wait for completion
    $Jobs += @{
        JobId = $Job.JobId.ToString()
        Status = ''
    }
}

# Check job status in a loop until all jobs have finished
$Completed = $false
while (-not $Completed) {
    Write-Output ("Checking for completed jobs...")
    # Get job details for each of our jobs where the status has not been populated yet
    $Jobs | Where-Object { $_.Status -eq '' } | ForEach-Object {
        # Get the details of the job to see if it has finished yet
        $Job = Get-AzureRmAutomationJob -Id $_.JobId -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
        # If there is an end time then the job has finished
        if ($Job.EndTime) { 
            $_.Status = $Job.Status 
            Write-Output ("Job '{0}' has finished with a status of '{1}'." -f $Job.JobId, $Job.Status)
        }
    }
    # If all jobs have finished, then set the completed flag to true
    if (($Jobs | Where-Object { $_.Status -eq "" }).Count -eq 0) { 
        $Completed = $true 
    } else {
        # Wait 10 seconds before checking again just so we don't overflow the output stream with noise
        Start-Sleep -Seconds 10
    }
}
Write-Output ("All child jobs have completed.")

