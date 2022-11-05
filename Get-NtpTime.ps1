Function Get-NtpTime () {
    <#
.SYNOPSIS
    Get the time from given time server
.LINK
    https://madwithpowershell.blogspot.com/2016/06/getting-current-time-from-ntp-service.html
.EXAMPLE
    Get-NTPDateTime -NTPServer time-a-b.nist.gov
#>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = "the address of the NTP server to check time on", Mandatory)][String]$NTPServer,
        [Parameter(HelpMessage = "The port number to use for NTP service, default is 123")][int]$NTPport = 123
    )
    Write-Verbose "Build NTP request packet. We'll reuse this variable for the response packet"
    $NTPData = New-Object byte[] 48  # Array of 48 bytes set to zero
    $NTPData[0] = 27                 # Request header: 00 = No Leap Warning; 011 = Version 3; 011 = Client Mode; 00011011 = 27

    try {
        Write-Verbose "Open a connection to the NTP service..."
        $Socket = New-Object Net.Sockets.Socket ( 'InterNetwork', 'Dgram', 'Udp' )
        $Socket.SendTimeOut = 2000  # ms
        $Socket.ReceiveTimeOut = 2000  # ms
        $Socket.Connect($NTPServer, $NTPport)
	
        Write-Verbose "Make the request..."
        $Null = $Socket.Send($NTPData)
        $Null = $Socket.Receive($NTPData)
	
        Write-Verbose "Clean up the connection..."
        $Socket.Shutdown('Both')
        $Socket.Close()
    }
    catch {
        Write-Error "Can't make socket connection to time server: $($Error[0].Exception.Message)"
    }

    Write-Verbose "Extract relevant portion of first date in result (Number of seconds since 'Start of Epoch')..."
    $Seconds = [BitConverter]::ToUInt32($NTPData[43..40], 0)

    Write-Verbose "Add them to the 'Start of Epoch', convert to local time zone, and return"
    return ( [datetime]'1/1/1900' ).AddSeconds( $Seconds ).ToLocalTime()
}
