Param (
    [string] $Value1,
    [string] $Value2
)

Write-Output ("Value1 = {0}" -f $Value1)
Start-Sleep -Seconds 30
Write-Output ("Value2 = {0}" -f $Value2)
