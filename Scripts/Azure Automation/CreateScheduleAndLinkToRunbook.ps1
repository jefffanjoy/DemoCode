$ResourceGroupName = "MyResourceGroup"
$AutomationAccountName = "MyAutomationAccount"
$RunbookName = "MyRunbook"

# Set the start of the schedule to be 20 minutes from creation
$StartDate = (Get-Date).AddMinutes(20)

$DaysOfWeek = @(
    [System.DayOfWeek]::Monday, 
    [System.DayOfWeek]::Tuesday, 
    [System.DayOfWeek]::Wednesday
)

New-AzureRmAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'MySchedule' -StartTime $StartDate -WeekInterval 1 -DaysOfWeek $DaysOfWeek
Register-AzureRmAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -RunbookName $RunbookName -ScheduleName 'MySchedule'
