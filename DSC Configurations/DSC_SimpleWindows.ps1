Configuration DSC_SimpleWindows {
    Node Test {
        File DirectoryExists {
            Ensure = "Present"
            Type = "Directory"
            DestinationPath = "C:\Temp\DSC_SimpleWindowsTest"
        }

        Log AfterDirectoryExists {
            Message = "Finished running resource with ID DirectoryExists."
            DependsOn = "[File]DirectoryExists"
        }
    }
}