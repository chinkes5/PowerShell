function Split-ServerName {

    <# 
.SYNOPSIS
Returns details about a given server
.DESCRIPTION
The function will attempt to determine several data points about a server from the current and prior naming standards. It will try to figure out the datacenter, domain, role, if there is an client environment designation, and if there is a increment on role.
.PARAMETER serverName
The server name to split.
.EXAMPLE
Split-ServerName -serverName DENWEB01-D

***** Should return *****
Datacenter    : DenverDataCentre
Name          : DENAERP01-D
Domain        : dev
FDQN          : denaerp01-d.dev.host.com
ServerCountID : 01
Environment   : None
Role          : Acumentica ERP
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'The name or FDQN to evaluate')][string]$serverName
    )

    try {
        if ($serverName.Split('.').Count -gt 1) {
            Write-Verbose "There are dots in the name, probably a FDQN"
            $Name = $serverName.Split('.')[0]
        }
        else {
            Write-Verbose "No dots in the name, probably just a server name"
            $Name = $serverName
        }

        # The switch statement will process the given variable with the indicated regex
        # These regex statements are using named groups to populate the default variable
        # $Match. Since they are named, we can use dot notation to retreive the values.
        # https://powershellexplained.com/2017-07-31-Powershell-regex-regular-expression/#named-matches
        # https://www.chinkes.com/powershell-regex-matching/

        # An analysis of the existing names shows we only have so many options in use
        switch -Regex ($name) {
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<environment>r2|c3|b4)(?<number>\d{2})(?<domain>-d|-tz|-t|-z)" {
                # non-core domains, environment, number
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = $Matches.domain
                $FoundRole = $Matches.role
                $FoundEnv = $Matches.environment
                $FoundServerNumber = $Matches.number
                $FoundServerset = "None"
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<environment>r2|c3|b4)(?<set>[a-d])(?<domain>-d|-tz|-t|-z)" {
                # non-core domains, environment, letters
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = $Matches.domain
                $FoundRole = $Matches.role
                $FoundEnv = $Matches.environment
                $FoundServerNumber = "None"
                $FoundServerset = $Matches.set
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<number>\d{2})(?<set>[a-d])(?<domain>-d|-tz|-t|-z)" {
                # non-core domains, number + letters 
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = $Matches.domain
                $FoundRole = $Matches.role
                $FoundEnv = "None"
                $FoundServerNumber = $Matches.number
                $FoundServerset = $Matches.set
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<number>\d{2})(?<domain>-d|-tz|-t|-z)" {
                # non-core domains, number
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = $Matches.domain
                $FoundRole = $Matches.role
                $FoundEnv = "None"
                $FoundServerNumber = $Matches.number
                $FoundServerset = "None"
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<set>[a-d])(?<domain>-d|-tz|-t|-z)" {
                # non-core domains, letters 
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = $Matches.domain
                $FoundRole = $Matches.role
                $FoundEnv = "None"
                $FoundServerNumber = "None"
                $FoundServerset = $Matches.set
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<domain>-d|-tz|-t|-z)" {
                # non-core domains
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = $Matches.domain
                $FoundRole = $Matches.role
                $FoundEnv = "None"
                $FoundServerNumber = "None"
                $FoundServerset = "None"
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<environment>r2|c3|b4)(?<number>\d{2})" {
                # Main domain, environment, number
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = "Main"
                $FoundRole = $Matches.role
                $FoundEnv = $Matches.environment
                $FoundServerNumber = $Matches.number
                $FoundServerset = "None"
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<environment>r2|c3|b4)(?<set>[a-d])" {
                # Main domain, environment, letters 
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = "Main"
                $FoundRole = $Matches.role
                $FoundEnv = $Matches.environment
                $FoundServerNumber = "None"
                $FoundServerset = $Matches.set
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)(?<number>\d{2})" {
                # Main domain and a number
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = "Main"
                $FoundRole = $Matches.role
                $FoundEnv = "None"
                $FoundServerNumber = $Matches.number
                $FoundServerset = "None"
                break
            }
            "(?<datacenter>codc|den|cin)(?<role>\w+)" {
                # Main domain and role only
                $FoundDatacenter = $Matches.datacenter
                $FoundDomain = "Main"
                $FoundRole = $Matches.role
                $FoundEnv = $Matches.environment
                $FoundServerNumber = "None"
                $FoundServerset = "None"
                break
            }
            default {
                Throw "No regex pattern matches server name!"
            }
        }
                
        # test for the first part, the datacenter
        switch ($FoundDatacenter.ToUpper()) {
            'DEN' {
                Write-Verbose "Server name starts with DEN, must be in Denver"
                $Datacenter = "Denver Data Centre"
                break
            }
            'CIN' {
                Write-Verbose "Server name starts with CIN, must be Cincinnati data center"
                $Datacenter = "Cincinnati Data Centre"
                break
            }
            default {
                Write-Verbose "Server name does not start with D, probably legacy stuff"
                $Datacenter = "Denver Data Centre-Legacy"
            }
        }
    
        # test for the last part, the domain
        switch ($FoundDomain) {
            "-D" { 
                $Domain = "Dev"
                break
            }
            "-T" { 
                $Domain = "Test"
                break
            }
            "-TZ" { 
                $Domain = "TestDMZ"
                break
            }
            "-Z" { 
                $Domain = "DMZ"
                break
            }
            Default {
                $Domain = "Main"
            }
        }
        Write-Verbose "Set the domain: $Domain"
    
        # test for the client, called environment, somewhere in the end
        switch ($FoundEnv) {
            'r2' {
                Write-Verbose "Found reference to client name, $Environment"
                $Environment = "R2D2"
                break
            }
            'c3' {
                Write-Verbose "Found reference to client name, $Environment"
                $Environment = "C3PO"
                break
            }
            'b4' {
                Write-Verbose "Found reference to client name, $Environment"
                $Environment = "BB4"
                break
            }
            default {
                Write-Verbose "Found no reference to client name"
                $Environment = "None"
            }
        }
    
        # testing for the server count and any sets
        if ($FoundServerset -eq "None" -and $FoundServerNumber -eq "None") {
            Write-Verbose "No server count or set"
            $ServerCountID = "None"
        }
        elseif ($FoundServerset -eq "None") {
            Write-Verbose "Found a count"
            $ServerCountID = $FoundServerNumber 
        }
        elseif ($FoundServerNumber -eq "None") {
            Write-Verbose "Found  a set"
            $ServerCountID = $FoundServerset.ToUpper() 
        }
        else {
            Write-Verbose "Found either a count and a set"
            $ServerCountID = "$FoundServerNumber-$($FoundServerset.ToUpper())"
        }
    
        $RoleDescriptions = @{
            "AD"         = "Active Directory Domain Controller";
            "AERP"       = "Acumentica ERP";
            "API"        = "host API server";
            "ASV"        = "QualysGuard(R) Virtual Scanner Appliance";
            "AZCON"      = "Azure Connector server";
            "BS"         = "Build Server";
            "BU"         = "Backup server";
            "CA"         = "Certificate Authority";
            "DB"         = "SQL Server";
            "DC"         = "Active Directory Domain Controller";
            "DBAO"       = "SQL Server";
            "DG"         = "BI Data Gateway";
            "FS"         = "File Server";
            "LB"         = "Load Balancer Appliance";
            "LOG"        = "Processing Log server";
            "LOGCOLLECT" = "Log collector server";
            "MSG"        = "Message Broker server - Legacy";
            "NTP"        = "Network Time server";
            "PROX"       = "Proxy server";
            "SAT"        = "Gateway or Satellite";
            "SEC"        = "Server for Security";
            "SFTP"       = "Secure FTP server";
            "SQL"        = "SQL server";
            "TP"         = "Transaction Processor";
            "WEB"        = "Web Server";
        }
        if ($RoleDescriptions.$FoundRole.Count -le 0) {
            Write-Verbose "A match of the role to a description was not found, returning the regex group value: `'$FoundRole`'"
            $Role = $FoundRole
        }
        else {
            $Role = $RoleDescriptions.$FoundRole
            Write-Verbose "A role description was found, returning `'$Role`'"
        }

        return [PSCustomObject]@{
            Datacenter    = $Datacenter
            Name          = $Name.ToUpper()
            Domain        = $Domain.ToLower()
            FDQN          = $FDQN.ToLower()
            ServerCountID = $ServerCountID
            Environment   = $Environment
            Role          = $Role
        }
    
    }
    catch {
        Write-Error "Can't parse the server name as given - $($Error[0].Exception.Message)"
    }
}
