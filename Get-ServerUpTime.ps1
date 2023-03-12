function Get-ServerUptime {
    <#
.SYNOPSIS
    Gets the time since the last boot of this computer
.DESCRIPTION
    Gets the days, hours, and minutes since last boot
    Optionally can get the last boot event, if in the last 5000 
#>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = 'Additionally, get the last boot event, if can be found')][switch]$LastBootEvent,
        [Parameter(HelpMessage='The number of events to search for last boot events')][int]$MaxEvents = 5000
    )
    try {
        if ($LastBootEvent) {
            $lastEvent = Get-WinEvent -LogName System -MaxEvents $MaxEvents | Where-Object Id -in 41, 1074, 1076, 6005, 6006, 6008, 6009 | Sort-Object TimeCreated
            if ($null -eq $lastEvent) {
                Write-Warning "Can't find boot events in last $MaxEvents events!"
            }
            else {
                Write-Output "Last Boot Events:" 
                $lastEvent | Format-Table TimeCreated, Id, UserName, Message -AutoSize
            }
        }

        $uptime = (Get-Date) - (Get-CimInstance -ClassName win32_operatingsystem | Select-Object lastbootuptime).lastbootuptime
        Write-Output "Uptime: $($Uptime.Days) days, $($Uptime.Hours) hours, $($Uptime.Minutes) minutes" 
    }
    catch {
        Write-Error "Can't get server uptime - $($Error[0].Exception.Message)"
    }
}
