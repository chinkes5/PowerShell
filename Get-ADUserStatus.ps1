function Set-OU {
    param (
        [Parameter(HelpMessage = 'The domain server to search on', Mandatory = $true)][string]$Domain
    )
    Write-Verbose "Setting OU for domain server: $Domain"
    switch -wildcard ($Domain) {
        "*.test.qrails.com" { 
            $OU = "DC=test,DC=example,DC=com"
            break
        }
        "*.prod.qrails.com" { 
            $OU = "DC=prod,DC=example,DC=com"
            break
        }
        "*.dmz.qrails.com" { 
            $OU = "DC=dmz,DC=example,DC=com"
            break
        }
        "*.testdmz.qrails.com" { 
            $OU = "DC=testdmz,DC=example,DC=com"
            break
        }
        Default { 
            $OU = "DC=example,DC=com"
        }
    }

    return $OU
}

function Get-UserFromAD {
    <#
    .SYNOPSIS
        function to search Active Directory and get one user back
    .DESCRIPTION
        There are several flags to change the search as well as further questions to the user to help narrow the results to one user
    .OUTPUTS
        Microsoft.ActiveDirectory.Management.ADUser
    .NOTES
        Requires the Get-MenuSelection function to be available
    .EXAMPLE
        Get-UserFromAD -userName $userName ## returns a user matching given name or name part, if wildcards used
    .EXAMPLE
        Get-UserFromAD -userName $userName -elevated ## returns elvated user account matching given name or name part, if wildcards used
    .EXAMPLE
        Get-UserFromAD -userName $userName -disabled ## returns a disabled user account matching given name or name part, if wildcards used
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = 'The user name to search on, using wildcards is recommended', Mandatory = $true)]
        [ValidatePattern("^\*?[a-z]+\*?$")]$searchUserString, # any letters, optionally starting or ending with a "*"
        [Parameter(HelpMessage = 'The domain server to search on', Mandatory = $true)][string]$Domain,
        [Parameter(HelpMessage = 'The OU to limit the search to')][string]$OU,
        [Parameter(HelpMessage = 'Switch if you want to find disabled users')][switch]$disabled,
        [Parameter(HelpMessage = 'Switch if you want to search all OU')][switch]$searchAllOU,
        [Parameter(HelpMessage = 'Switch if you want to find only elevated users')][switch]$elevated,
        [Parameter(HelpMessage = 'Switch if you want to search on Security Account Manager vs User name')][switch]$SAMName
    )
    if ([string]::IsNullOrEmpty($OU)) {
        Write-Verbose "Setting OU for given domain server: $Domain"
        $OU = Set-OU -Domain $Domain
    }
    try {
        if ($disabled) {
            Write-Verbose "Searching Active Directory for users in every OU who might also be disabled"
            $filter = "Name -like `'$searchUserString`' -and Enabled -eq $False"
        }
        elseif ($searchAllOU) {
            Write-Verbose "Searching Active Directory in every OU"
            $filter = "{(Name -like `'$searchUserString`') -and (Enabled -eq $True)}"
        }
        elseif ($elevated) {
            Write-Verbose "Searching Active Directory for only elevated users"
            $filter = "SamAccountName -like '*-e'"
        }
        elseif ($SAMName) {
            $filter = "SamAccountName -like `'$searchUserString`'"
        }
        else {
            Write-Verbose "Searching Active Directory with default parameters"
            # $filter = "(Name -like '$searchUserString') -and (Enabled -eq $True)"
            $filter = "Name -like '$searchUserString'"
        }
        # Get-Help about_ActiveDirectory_Filter
        $userSearch = Get-ADUser -Server $Domain -Credential $Credential -Filter $filter -errorAction silentlyContinue |  Select-Object Name, SamAccountName | Sort-Object Name

        if ($null -eq $userSearch) {
            Write-Error "No user matches $searchUserString."
            return $false
        }
        else {
            if ($userSearch.Count -gt 1) {
                Write-Warning "Found more than one user!"
                $multiUserReturn = Get-MenuSelection -MenuItems $userSearch.SamAccountName -MenuPrompt "More than one user matches, please select which one to work on:" 
                # We're returning AD user object, get the whole thing-
                $returnName = Get-ADUser -Server $Domain -Credential $Credential -Filter "SamAccountName -eq '$multiUserReturn'" -Properties "Title", "Manager", "Department", "Enabled", "LockedOut", "displayName", "AccountLockoutTime", "PasswordExpired", "msDS-UserPasswordExpiryTimeComputed", "LastLogonDate", "LastBadPasswordAttempt", "Company"
                Write-Host "Selected user: $($returnName.Name)" -ForegroundColor Green
            }
            else {
                # We're returning AD user object, get the whole thing-
                $returnName = Get-ADUser -Server $Domain -Credential $Credential -Filter "SamAccountName -eq '$($userSearch.SamAccountName)'" -Properties "Title", "Manager", "Department", "Enabled", "LockedOut", "displayName", "AccountLockoutTime", "PasswordExpired", "msDS-UserPasswordExpiryTimeComputed", "LastLogonDate", "LastBadPasswordAttempt", "Company"
                Write-Host "Found user: $($returnName.Name)" -ForegroundColor Green
            }
        }

        return $returnName
    }
    catch {
        Write-Error "$($Error[0].Exception.Message)"
    }
}

$AdminLogin = Read-Host "What admin account will be used to do this?"
$credential = Get-Credential -Message "Domain user for $($domain.Name)" -UserName "$($domain.Name)\$AdminLogin"
Invoke-Command -ComputerName $domain.Value -Credential $credential -ScriptBlock {

    Write-Output "filter- Name -like `'$USING:userName`'"
    $userResults = Get-ADUser -Filter {Name -like $USING:userName} -Properties "DisplayName", "msDS-UserPasswordExpiryTimeComputed", `
        "LockedOut", "PasswordExpired", "LastLogonDate", "LastBadPasswordAttempt", "AccountLockoutTime"

    if ($userResults.Count -lt 1) { 
        $i = 0 
    } 
    else { 
        $i = $userResults.Count
    }
    Write-Output "Found $i users matching $($USING:userName)"
    if ($userResults.Count -gt 0) {
        foreach ($user in $userResults ) {
            # Write-Host "Found $($user.SamAccountName)!" -ForegroundColor Green
            Write-Host "Found $($user.UserPrincipalName)!" -ForegroundColor Green
            if ($user.LockedOut) {
                Write-Warning "$($user.displayName) is locked out as of $($user.AccountLockoutTime)"
            }
            else {
                Write-Output "$($user.displayName) is not locked out"
            }
            if ($user.PasswordExpired) {
                Write-Warning "Password is expired: $($user.PasswordExpired)"
            }
            else {
                Write-Output "Password for $($user.displayName) is not expired"
            }
            Write-Output "Password expires on $([datetime]::FromFileTime($user."msDS-UserPasswordExpiryTimeComputed"))"
            Write-Output "Last successful login: $($user.LastLogonDate)"
            Write-Output "Last bad password attempt: $($user.LastBadPasswordAttempt)"
        }
    }
    else {
        Write-Output "No users found matching `"$USING:userName`""
    }
}
