configuration SimpleLinux {
    Import-DscResource -Module nx

    Node jfanjoy-ubuntu1604 {
        nxFile TestFile {
            DestinationPath = "/etc/test"
            Ensure = 'Absent'
        }
    }
}