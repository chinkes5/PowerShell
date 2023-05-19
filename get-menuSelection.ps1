function Get-MenuSelection {
    <#
    .SYNOPSIS
        Displays a selection menu and returns the selected item
    
    .DESCRIPTION
        Takes a list of menu items, displays the items and returns the user's selection.
        Items can be selected using the up and down arrow and the enter key.
    
    .PARAMETER MenuItems
        List of menu items to display
    
    .PARAMETER MenuPrompt
        Menu prompt to display to the user. Defaults to 'Choose from the following:'
    
    .EXAMPLE
        PS C:\> Get-MenuSelection -MenuItems @("Dogs","Cats","Fish") -MenuPrompt 'Choose from the following:'
    
    .LINK
        https://www.koupi.io/post/creating-a-powershell-console-menu
#>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String[]]$MenuItems,
        [String]$MenuPrompt = "Choose from the following:"
    )
    # store initial cursor position
    $cursorPosition = $host.UI.RawUI.CursorPosition
    $pos = 0 # current item selection
    
    function Write-Menu {
        param (
            [int]$selectedItemIndex
        )
        # reset the cursor position
        $Host.UI.RawUI.CursorPosition = $cursorPosition
        # Padding the menu prompt to center it
        $prompt = $MenuPrompt
        $maxLineLength = ($MenuItems | Measure-Object -Property Length -Maximum).Maximum + 4
        while ($prompt.Length -lt $maxLineLength + 4) {
            $prompt = " $prompt "
        }
        Write-Host $prompt -ForegroundColor Green
        # Write the menu lines
        for ($i = 0; $i -lt $MenuItems.Count; $i++) {
            $line = "    $($MenuItems[$i])" + (" " * ($maxLineLength - $MenuItems[$i].Length))
            if ($selectedItemIndex -eq $i) {
                Write-Host $line -ForegroundColor Blue -BackgroundColor Gray
            }
            else {
                Write-Host $line
            }
        }
    }
    
    Write-Menu -selectedItemIndex $pos
    $key = $null
    #KEYCODE 13 is the enter key
    while ($key -ne 13) {
        # Read the keyboard input
        $press = $host.ui.rawui.readkey("NoEcho,IncludeKeyDown")
        $key = $press.virtualkeycode
        if ($key -eq 38) {
            #KEYCODE 38 is arrow up
            $pos--
        }
        if ($key -eq 40) {
            #KEYCODE 40 is arrow down
            $pos++
        }
        #handle out of bound selection cases
        if ($pos -lt 0) { $pos = 0 }
        if ($pos -eq $MenuItems.count) { $pos = $MenuItems.count - 1 }
        
        # Draw menu
        Write-Menu -selectedItemIndex $pos
    }
    
    return $MenuItems[$pos]
}
