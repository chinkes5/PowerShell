Function Test-portTCP {
    <#
    .SYNOPSIS 
        scans the hosts and ports via TCP
    .EXAMPLE
        port-scan-tcp 10.10.0.1 137
    .EXAMPLE
        port-scan-tcp 10.10.0.1 (135,137,445)
    .EXAMPLE
        port-scan-tcp (gc .\ips.txt) 137
    .EXAMPLE
        port-scan-tcp (gc .\ips.txt) (135,137,445)
    .EXAMPLE
        0..255 | foreach { port-scan-tcp 10.10.0.$_ 137 }
    .EXAMPLE
        0..255 | foreach { port-scan-tcp 10.10.0.$_ (135,137,445) }
    .LINK
        forked from https://github.com/InfosecMatter/Minimalistic-offensive-security-tools/blob/master/port-scan-tcp.ps1
    #>
    param(
        [Parameter(HelpMessage = 'a list of hosts to scan', Position = 1)][string[]]$hosts, 
        [Parameter(HelpMessage = 'a list of ports to scan', Position = 2)][string[]]$ports,
        [Parameter(HelpMessage = 'file path or name to output results')][string]$out = ".\scanresults.txt"
    )

    if (!$ports) {
        Write-Output "usage: Test-portTCP <host|hosts> <port|ports>"
        Write-Output " e.g.: Test-portTCP 192.168.1.2 445`n"
        return
    }
    foreach ($port in $ports) {
        Write-Verbose "Working on port $port..."

        $PortUsage = @{
            "WINS replication" = 42;
            "DNS" = 53;
            "Kerberos" = 88;
            "RPC" = 135;
            "NetBIOS name service" = 137;
            "NetBIOS datagram" = 138;
            "NetBIOS session service" = 139;
            "SMB" = 445;
            "LDAP" = 389;
            "Secure LDAP" = 636;
            "WINS resolution" = 1512;
            "Global Catalog LDAP" = 3268;
            "Secure Global Catalog LDAP " = 3269;
        }
        if($PortUsage[$port]){
            Write-Verbose "Swapping $port for port number..."
            $port = $PortUsage[$port]
        }
        
        foreach ($h in $hosts) {
            Write-Verbose "Working on host $h..."
            $x = (Get-Content $out -EA SilentlyContinue | select-string "^$h,tcp,$port,")
            if ($x) {
                Get-Content $out | select-string "^$h,tcp,$port,"
                continue
            }
            $msg = "$h,tcp,$port,"
            $t = new-Object system.Net.Sockets.TcpClient
            $c = $t.ConnectAsync($h, $port)
            for ($i = 0; $i -lt 10; $i++) {
                # loop 10 times to wait for connection
                if ($c.isCompleted) { 
                    # connection complete
                    break; 
                }
                # waiting for connection to return
                Start-Sleep -milliseconds 100
            }
            $t.Close();
            $r = "Filtered"
            if ($c.isFaulted -and $c.Exception -match "actively refused") {
                Write-Verbose "Connection actively refused"
                $r = "Closed"
            }
            elseif ($c.Status -eq "RanToCompletion") {
                Write-Verbose "Connection successful"
                $r = "Open"
            }
            $msg += $r
            Write-Verbose "$msg"
            Write-Output $msg >>$out
        }
    }
}
