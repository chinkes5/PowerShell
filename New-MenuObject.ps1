function New-MenuObject {
    <#
    .SYNOPSIS
        presents a menu from options and returns index value of selected
    .LINK
        https://adamtheautomator.com/powershell-menu/
    .EXAMPLE
        New-Menu -Title 'Colors' -Question 'What is your favorite color?' -Options @('red', 'blue', 'yellow')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The title of the menu, displayed at the top')][ValidateNotNullOrEmpty()][string]$Title,
        [Parameter(Mandatory, HelpMessage = 'The menu prompt, the question you are asking')][ValidateNotNullOrEmpty()][string]$Question,
        [Parameter(Mandatory, HelpMessage = 'an array to use as your menu selections')][ValidateNotNullOrEmpty()][string[]]$Options
    )
    
    $OptionList = @()
    foreach ($item in $Options) {
        $OptionList += (New-Object System.Management.Automation.Host.ChoiceDescription "&$($item.ToUpper())", "$Title : $item")
    }

    $return = $host.ui.PromptForChoice($Title, $Question, $OptionList, 0)
    Write-Verbose $return
    return $return
}
