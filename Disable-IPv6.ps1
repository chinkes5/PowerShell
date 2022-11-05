function Disable-IPv6 {
    try {
        $adapterName = Get-NetAdapterBinding -ComponentID ms_tcpip6
    
        Write-Verbose "Testing if IPv6 is enabled..."
        if ($adapterName.Enabled) {
            Write-Output "IPv6 is enabled, turning it off..."
            Disable-NetAdapterBinding -Name $adapterName.Name -ComponentID ms_tcpip6
        }
        else {
            Write-Output "IPv6 is not enabled"
        }
    }
    catch {
        Write-Error "there was a problem getting the status of IPv6- $($Error[0].Exception.Message)"
    }
}
