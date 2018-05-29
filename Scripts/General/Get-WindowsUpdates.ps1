# Get updates from Windows Updates
$WUSession = New-Object -com "Microsoft.Update.Session";
$WUSession.ClientApplicationID = "Install-Updates.ps1";
$WUSearch = $WUSession.CreateUpdateSearcher();
$SearchResults = $WUSearch.Search("IsHidden = 0 AND DeploymentAction=* AND IsInstalled =0");
              
$wuUpdates = @();
foreach ($wuUpdate in $SearchResults.Updates) {
    $update = @{
        RevisionNumber       = $wuUpdate.Identity.RevisionNumber;
        UpdateID             = $wuUpdate.Identity.UpdateID;
        DeploymentAction     = $wuUpdate.DeploymentAction;
        Title                = $wuUpdate.Title;
        Deadline             = $wuUpdate.Deadline;
        Description          = $wuUpdate.Description;
        IsHidden             = $wuUpdate.IsHidden;
        IsInstalled          = $wuUpdate.IsInstalled;
        IsMandatory          = $wuUpdate.IsMandatory;
        MsrcSeverity         = $wuUpdate.MsrcSeverity;
        Type                 = $wuUpdate.Type;
        RebootRequired       = $wuUpdate.RebootRequired;
        IsPresent            = $wuUpdate.IsPresent;
        AutoSelectOnWebSites = $wuUpdate.AutoSelectOnWebSites;
        BrowseOnly           = $wuUpdate.BrowseOnly;
        SecurityBulletinIDs  = @();
    };
              
    $wuUpdate.SecurityBulletinIDs | foreach {
        $update.SecurityBulletinIDs += $_
    }
              
    $wuUpdates += $update;
}
              
$wuUpdates | ConvertTo-Json | Out-File -FilePath wuUpdates.json; 
