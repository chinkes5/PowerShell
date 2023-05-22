Write-Output "test the function..."
Describe 'Split-ServerName' {
    Context 'ERP server in Denver' {
        It 'Should split server name' {
            $result = Split-ServerName -serverName 'DENAERP01-D'
            $result.Datacenter | Should -Be "Denver Data Centre"
            $result.Name | Should -Be "DENAERP01-D"
            $result.Domain | Should -Be "dev"
            $result.FDQN | Should -Be "denaerp01-d.dev.example.com"
            $result.ServerCountID | Should -Be "01"
            $result.Environment | Should -Be "None"
            $result.Role | Should -Be "Acumentica ERP"
        }
    }

    Context 'Active Directory server in Cincinnati' {
        It 'Should split server name' {
            $result = Split-ServerName -serverName 'cinad02-z.dmz.example.com'
            $result.Datacenter | Should -Be "Cincinnati Data Centre"
            $result.Name | Should -Be "CINAD02-Z"
            $result.Domain | Should -Be "dmz"
            $result.FDQN | Should -Be "cinad02-z.dmz.example.com"
            $result.ServerCountID | Should -Be "02"
            $result.Environment | Should -Be "None"
            $result.Role | Should -Be "Active Directory Domain Controller"
        }
    }
}