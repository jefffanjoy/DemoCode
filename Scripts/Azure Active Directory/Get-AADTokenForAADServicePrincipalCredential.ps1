# Change these three variables to reflect your tenant id, AAD application id and associated secret
$TenantId = 'AADTENANTID'
$ClientId = 'AADAPPLICATIONID'
$ClientSecret = 'AADAPPLICATIONSECRET'

$TokenEndpoint = {https://login.windows.net/{0}/oauth2/token} -f $TenantId
$ApiEndPointUri = "https://management.azure.com/"

$Body = @{
    'resource'=$ApiEndPointUri
    'client_id'= $ClientId
    'grant_type' = 'client_credentials'
    'client_secret' = $ClientSecret
}

$params = @{
    ContentType = 'application/x-www-form-urlencoded'
    Headers = @{'accept'='application/json'}
    Body = $Body
    Method = 'Post'
    URI = $TokenEndpoint
}

$token = Invoke-RestMethod @params

$token | select access_token, @{L='Expires';E={[timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($_.expires_on))}} | fl *
$token
