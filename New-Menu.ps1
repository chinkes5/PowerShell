function New-MenuFunction {
    <#
.SYNOPSIS
    Make a menu of given array or hashtable with paging
.PARAMETER pageSize
    The number of elements in list to display at once, default is 5
.PARAMETER menuHeader
    Text for prompt for the menu selection, default is 'Select from the following'
.PARAMETER returnIndexNum
    Set this switch if you only want the index number and not the value from entered list
.PARAMETER MenuInputList
    The array or hashtable to base the menu off of. The list will be sorted before display. There is a limit of 99 elements in the array
#>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = 'The number of elements in list to display at once, default is 5')][int]$pageSize = 5,
        [Parameter(HelpMessage = 'Text for prompt for the menu selection')][string]$menuHeader = "Select from the following",
        [Parameter(HelpMessage = 'Set this switch if you only want the index number and not the value from entered list')][switch]$returnIndexNum,
        [Parameter(HelpMessage = 'The array or hashtable to base the menu off of')]$MenuInputList
    )

    # private function to build a page of menu items
    function Private:Update-MenuPage {
        [CmdletBinding()]
        param (
            [Parameter(HelpMessage = 'the number of elements in list to display at once')][int]$pageSize,
            [Parameter(HelpMessage = 'start point for the displayed list vs whole list')][int]$offset,
            [Parameter(HelpMessage = 'the whole list to get a page of')][array]$menuArray
        )

        Clear-Variable -Name menuHash
        $endOfList = $false
        # set the page up option if not at the beginning of the list
        if ($offset -eq 0) {
            $menuHash = @()
        }
        else {
            $menuHash = @( "($offset) Page Up" )
        }
        # adjust the page size if the rest of the list is less than page size
        if ($menuArray.Count -lt $pageSize + $offset) {
            # if there are less items than the page size, reset the page size
            $pageSize = $menuArray.Count - $offset
            $endOfList = $true
        }
        # build the menu page
        for ($i = 0; $i -lt $pageSize; $i++) {
            # make the selector entry
            $selector = $offset + $i + 1
            # build out the list of items to select as an array
            $menuHash += "($selector) $($menuArray[$offset + $i])"
        }
        # set the page down option if not at the end of the list
        if ($endOfList) {
            return $menuHash
        }
        else {
            $menuHash += "($($offset + $pageSize + 1)) Page Down"
            return $menuHash
        }
    }

    # start offset from the start of the menu at 0
    $offset = 0

    # turn hash tables into array so I can work with each entry by index number
    if ($MenuInputList.GetType().Name -eq "Hashtable") {
        $menuArray = $MenuInputList.GetEnumerator().ForEach({ $_.Value }) | Sort-Object
    }
    else {
        $menuArray = $MenuInputList | Sort-Object
    }

    # loop the menu pages until a menu item is selected
    do {
        Update-MenuPage -pageSize $pageSize -offset $offset -menuArray $menuArray
        $key = Read-Host $menuHeader
        $key = [int]$key.Substring(0, [Math]::Min($key.Length, 2))
        # two ways to slice this but this is were we only take two digit answers for our menu selection
        # https://jeffbrown.tech/powershell-7-ternary/ - shows how the following is PSv7+ way
        #$key = [int]$key.Substring(0, ($key.Length -ge 2)?2:1)
        # $key
        switch ($key) {
            $offset {
                # "up a page"
                $offset -= $pageSize
                Update-MenuPage -pageSize $pageSize -offset $offset -menuArray $menuArray
                $result = $false
                break
            }
            ($pageSize + 1) {
                # "down a page"
                $offset += $pageSize
                Update-MenuPage -pageSize $pageSize -offset $offset -menuArray $menuArray
                $result = $false
                break
            }
            default {
                $MenuIndex = $key + $offset - 1
                # "you selected item number $MenuIndex"
                $result = $true
            }
        }
    } until ($result -eq $true)

    # return either the index number or the value, as selected
    if ($returnIndexNum) {
        return $menuArray[$MenuIndex]
    }
    else {
        return $MenuInputList.($menuArray[$MenuIndex])
    }
}

<#$RoleDescriptions = @{
    "AD"     = "Active Directory Domain Controller";
    "AERP"   = "Acumentica ERP";
    "AHV"    = "Nutanix Host";
    "AHVPRI" = "Nutanix Host";
    "API"    = "QRails API server";
    "AZCON"  = "Azure Connector server";
    "BS"     = "Build Server";
    "BU"     = "Backup server";
    "CA"     = "Certificate Authority";
}
#>

$RoleDescriptions = @(
    "Active Directory Domain Controller",
    "Acumentica ERP",
    "Nutanix Host",
    "Nutanix Host",
    "QRails API server",
    "Azure Connector server",
    "Build Server",
    "Backup server",
    "Certificate Authority"
)

# New-MenuFunction -MenuInputList $RoleDescriptions
