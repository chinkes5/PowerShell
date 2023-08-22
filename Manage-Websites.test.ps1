Import-Module Pester

Describe "Get-IPListeners" {
    It "Should return a hashtable of IP listeners" {
        $result = Get-IPListeners
        $result | Should -BeOfType [hashtable]
    }

    It "Should contain valid IP addresses" {
        $result = Get-IPListeners
        foreach ($entry in $result.Values) {
            $entry | Should -Match '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'
        }
    }

    It "Should handle errors gracefully" {
        $errorActionPreference = 'Stop'
        { Get-IPListeners } | Should -Throw
    }
}

Describe "Get-SiteDetails" {
    Context "When no site name is provided" {
        It "Should return all site details" {
            # Arrange
            Mock Get-Website { @(@{ Name = "Site1"; ID = 1; ApplicationPool = "AppPool1"; PreloadEnabled = $true }) }

            # Act
            $result = Get-SiteDetails

            # Assert
            $result | Should -HaveCount 1
            $result[0].SiteName | Should -Be "Site1"
            $result[0].SiteID | Should -Be 1
            $result[0].AppPool | Should -Be "AppPool1"
            $result[0].PreloadEnabled | Should -Be $true
            # ... additional assertions for other properties
        }
    }

    Context "When a site name is provided" {
        It "Should return details for the specified site" {
            # Arrange
            Mock Get-Website { @(@{ Name = "Site2"; ID = 2; ApplicationPool = "AppPool2"; PreloadEnabled = $false }) }

            # Act
            $result = Get-SiteDetails -SiteName "Site2"

            # Assert
            $result | Should -HaveCount 1
            $result[0].SiteName | Should -Be "Site2"
            $result[0].SiteID | Should -Be 2
            $result[0].AppPool | Should -Be "AppPool2"
            $result[0].PreloadEnabled | Should -Be $false
            # ... additional assertions for other properties
        }
    }
}

Describe "Get-AppPoolDetails" {
    Context "When no AppPoolName is specified" {
        It "Should return an array of application pool details" {
            $result = Get-AppPoolDetails
            $result | Should -BeOfType [System.Object[]]
        }
    
        It "Should include the expected properties in the output" {
            $result = Get-AppPoolDetails
            $result | Should -ContainProperty "name"
            $result | Should -ContainProperty "pipelineMode"
            $result | Should -ContainProperty "runtimeVersion"
            $result | Should -ContainProperty "autostart"
            $result | Should -ContainProperty "poolState"
            $result | Should -ContainProperty "startMode"
            $result | Should -ContainProperty "maxProcesses"
        }
    }
    
    Context "When an AppPoolName is specified" {
        It "Should return details for the specified app pool" {
            $result = Get-AppPoolDetails -AppPoolName "MyAppPool"
            $result | Should -BeOfType [System.Object[]]
            $result | Should -ContainProperty "name" -WithValue "MyAppPool"
        }
    }
    
    Context "When an invalid AppPoolName is specified" {
        It "Should write an error message" {
            { Get-AppPoolDetails -AppPoolName "InvalidAppPool" } | Should -Throw
        }
    }
}
    

# Run the tests
Invoke-Pester