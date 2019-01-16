<#
.SYNOPSIS
    Invoke a scriptblock with retries on scriptblock failure.

.DESCRIPTION
    This function executes a scriptblock provided as a string variable and 
    executes that block trapping any errors that occur.  If an error is 
    trapped, an interval of time is passed and then the block is executed
    again until either the block executes successfully or the maximum number of
    retries is reached at which point the error is thrown and execution stops.

.PARAMETER ScriptBlock
    The script contents to execute provided as a string.

.PARAMETER Retries
    The maximum number of times to retry the execution of the scriptblock
    provided in the ScriptBlock parameter.

    Default value is 5.

.PARAMETER RetryInterval
    The amount of time in seconds to wait between retrying the execution of the
    scriptblock provided in the ScriptBlock parameter.

    Default value is 2.

.PARAMETER ThrowErrorOnException
    If true, causes any exception caught while executing the script block to
    result in a terminating error/exception.  If false, the exception is 
    written to the error stream.

    Default value is $false.

.EXAMPLE
    .\Invoke-ScriptBlock.ps1 -ScriptBlock { Get-Process -Name powershell } -Retries 5 -RetryInterval 2

.NOTES
    AUTHOR: Jeffrey Fanjoy
    LASTEDIT: January 16, 2019
#>

Param (
    [Parameter(Mandatory=$true)]
    [string] $ScriptBlock, 
    [Parameter(Mandatory=$false)]
    [int] $Retries = 5, 
    [Parameter(Mandatory=$false)]
    [int] $RetryInterval = 2,
    [Parameter(Mandatory=$false)]
    [boolean] $ThrowExceptionOnError = $false
)

Write-Verbose ("Entering Invoke-ScriptBlock")

    Function InvokeScriptBlock {
        Param (
            [Parameter(Mandatory=$true)]
            [string] $ScriptBlock, 
            [Parameter(Mandatory=$false)]
            [int] $Retries = 5, 
            [Parameter(Mandatory=$false)]
            [int] $RetryInterval = 2,
            [Parameter(Mandatory=$false)]
            [switch] $ThrowExceptionOnError
        )
        
        Write-Verbose ("Entering InvokeScriptBlock")

        # Set $ErrorActionPreference to "Stop" so that even non-terminating errors terminate and the
        # try..catch will be able to trap any exceptions.
        $ErrorActionPreference="Stop"

        # Construct a proper scriptblock object from the string scriptblock passed in.    
        $ScriptBlockToExecute = [Scriptblock]::Create($ScriptBlock)
        Write-Verbose ("Executing ScriptBlock [{0}] with retry maximum of [{1}] and retry interval of [{2}]." -f $ScriptBlockToExecute, $Retries, $RetryInterval)

        # Set the lifecycle variables for use in the while loop.
        $RetryCount = 1
        $Completed = $false
        while (!$Completed) {
            try {
                # Execute the scriptblock
                $result = & $ScriptBlockToExecute
                $result
                Write-Verbose ("ScriptBlock [{0}] executed successfully." -f $ScriptBlockToExecute)
                $Completed = $true
            } catch {
                if ($RetryCount -ge $Retries) {
                    Write-Verbose ("ScriptBlock [{0}] failed the maximum number of {1} times." -f $ScriptBlockToExecute, $RetryCount)
                    if ($ThrowExceptionOnError) {
                        throw $_
                    } else {
                        $ErrorActionPreference="Continue"
                        Write-Error $_
                    }
                    $Completed = $true
                } else {
                    Write-Verbose ("ScriptBlock [{0}] failed. Retrying in {1} second(s)." -f $ScriptBlockToExecute, $RetryInterval)
                    Start-Sleep $RetryInterval
                    $RetryCount++
                }
            }
        }

        Write-Verbose ("Exiting InvokeScriptBlock")
    }

if ($ThrowExceptionOnError) {
    InvokeScriptBlock -ScriptBlock $ScriptBlock -Retries $Retries -RetryInterval $RetryInterval -ThrowExceptionOnError
} else {
    InvokeScriptBlock -ScriptBlock $ScriptBlock -Retries $Retries -RetryInterval $RetryInterval
}

Write-Verbose ("Exiting Invoke-ScriptBlock")
