function Get-KMSstatus {
    <#
.SYNOPSIS
    Returns KMS status of given computer or list of computers
.DESCRIPTION
    This function is designed to be compatible with Get-ADComputer Jump cmdlet. You can pipe cmdlet output to a function. Follow the links below to the source material
.EXAMPLE
    Get-ADComputer -Filter {Name -like "DENPASS01-S"} -Properties * | Get-KMSstatus
.EXAMPLE
    Get-ADComputer -Filter * -Properties DNSHostName | ForEach-Object {Get-KMSstatus -DNSHostName $_.DNSHostName}
.LINK
    https://social.technet.microsoft.com/wiki/contents/articles/5675.powershell-determine-windows-license-activation-status.aspx
.LINK
    https://stackoverflow.com/questions/29368414/need-script-to-find-server-activation-status
#>

    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = 'single computer to get KMS status of')][string]$DNSHostName = $Env:COMPUTERNAME
    )
    
    if (Test-WSMan $DNSHostName -ErrorAction SilentlyContinue) {
        Get-CimInstance -ClassName SoftwareLicensingProduct -computerName $DNSHostName |
        Where-Object PartialProductKey | 
        Select-Object 
        @{Name = 'Server'; Expression = { $_.Pscomputername } }, 
        @{Name = 'OS'; Expression = { $_.Name } },
        @{Name = 'LicenseStatus'; Expression = {
                switch ($_.LicenseStatus) {
                    0 { 'Unlicensed' }
                    1 { 'Licensed' }
                    2 { 'Out-Of-Box Grace Period' }
                    3 { 'Out-Of-Tolerance Grace Period' }
                    4 { 'Non-Genuine Grace Period' }
                    5 { 'Notification' }
                    6 { 'Extended Grace' }
                    Default { 'Unknown value' }
                };
            }
        }
    }
    else {
        Write-Output (Select-Object `
            @{Name = 'Server'; Expression = { $DNSHostName } }, 
            @{Name = 'OS'; Expression = { "Unknown" } }, 
            @{Name = 'LicenseStatus'; Expression = { $Error[0].FullyQualifiedErrorId } } 
        )   
    }
}
