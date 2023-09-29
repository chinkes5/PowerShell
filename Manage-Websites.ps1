import-module WebAdministration

function Get-IPListeners {
    <#
.SYNOPSIS
    gets the list of ip listeners for IIS
.EXAMPLE
    Get-IPListeners
#>
    Try {
        $ipListeners = netsh http show iplisten | Select-String -Pattern "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" | ForEach-Object { $_.Matches.Value }
        $returnList = @{}
        $i = 0

        foreach ($entry in $ipListeners) {
            $returnList.Add($i, $entry)
            $i++
        }

        return $returnList
    }
    catch {
        Write-Error "There was an error in getting IP listeners - $($_.Exception.Message)"
    }
}

function Get-SiteDetails {
    <#
.SYNOPSIS
	gets an array of site details
.DESCRIPTION
    this is a list of lists, each sub list will have site details like name, ID, bindings, application pool, and preload status
.PARAMETER SiteName
    Optional site name if you only want details on the one site
.EXAMPLE
	Get-SiteDetails
#>
    [CmdletBinding()]
    param (
        [Parameter()][string]$SiteName
    )
    Try {
        $returnSiteList = @()
        if ($null -eq $SiteName) {
            $siteList = Get-Website
        }
        else {
            $siteList = Get-Website | Where-Object { $_.Name -eq $SiteName }
        }
	    
        foreach ($site in $siteList) {
            $siteInfo = [PSCustomObject]@{
                SiteName             = $site.name
                SiteID               = $site.id
                AppPool              = $site.applicationPool
                PreloadEnabled       = $site.applicationDefaults.preloadEnabled
                HttpBindings         = @()
                HttpsBindings        = @()
                LogFileDirectory     = $site.logFile.directory
                LogFormat            = $site.logFile.logFormat
                LogRolloverLocalTime = $site.logFile.localTimeRollover
                LogRolloverPeriod    = $site.logFile.period
            }

            $bindings = $site.bindings.Collection
            foreach ($protocol in $bindings) {
                if ($protocol.protocol -eq "http") {
                    $siteInfo.HttpBindings += $protocol.bindingInformation
                }
                if ($protocol.protocol -eq "https") {
                    $siteInfo.HttpsBindings += $protocol.bindingInformation
                }
            }

            $returnSiteList += $siteInfo
        }
        return $returnSiteList
    }
    catch {
        Write-Error "There was an error in site details- $($_.Exception.Message)"
    }
}

function Get-AppPoolDetails {
    <#
.SYNOPSIS
	gets an array of application pool details
.DESCRIPTION
    this is a list of pool details like name, pipeline model, runtime version, state, start mode, and max processes
.PARAMETER AppPoolName
    Optional app pool name if you only want details on the one app pool
.EXAMPLE
	Get-AppPoolDetails
#>
    [CmdletBinding()]
    param (
        [Parameter()][string]$AppPoolName
    )
    
    Try {
        $returnPoolList = @()
        if ($null -eq $AppPoolName) {
            $appPoolList = Get-ChildItem "iis:\apppools\"
        }
        else {
            $appPoolList = Get-ChildItem "iis:\apppools\$AppPoolName"
        }

        foreach ($pool in $appPoolList) {
            $PoolList = [PSCustomObject]@{
                name           = $pool.name
                pipelineMode   = $pool.managedPipelineMode
                runtimeVersion = $pool.managedRuntimeVersion
                autostart      = $pool.autoStart
                poolState      = $pool.state
                startMode      = $pool.startMode
                maxProcesses   = $pool.processModel.maxProcesses
            }

            $recycleSchedule = $pool.recycling.periodicRestart.schedule.Collection
            $i = 1
            foreach ($timeSlot in $recycleSchedule) {
                $PoolList | Add-Member -NotePropertyName ("recycleTime$i") -NotePropertyValue $timeSlot.value
                $i++
            }

            $returnPoolList += $PoolList
        }

        return $returnPoolList
    }
    catch {
        Write-Error "There was an error in getting app pool details- $($_.Exception.Message)"
    }
}

function Get-ApplicationConfig() {
    <#
.SYNOPSIS
	update the application config file with the standard web server settings, returns the values after updating
.DESCRIPTION
    Retrieves various configuration details from the web server configuration.

    This function makes use of the "Get-WebConfiguration" cmdlet to fetch
    configuration elements related to client cache, custom headers, and HTTP
    compression. It then returns a hashtable containing the retrieved details.

.OUTPUTS
    System.Collections.Hashtable
    A hashtable containing the web server configuration details.

.EXAMPLE
    $configDetails = Get-ApplicationConfig
.NOTES
	https://www.iis.net/configreference/system.webserver/staticcontent/clientcache?showTreeNavigation=true
	
	https://www.iis.net/configreference/system.webserver/httpprotocol/customheaders?showTreeNavigation=true
	
	#How to implement HTTP Compression Setting to compress files larger than 1000 bytes?
	https://www.iis.net/configreference/system.webserver/httpcompression?showTreeNavigation=true
#>

    Try {
        $webConfigList = @{
            clientCache = (Get-WebConfiguration -Filter "/system.webServer/staticContent/clientCache")
            headers     = (Get-WebConfiguration -Filter "/system.webServer/httpProtocol/customHeaders")
            compression = (Get-WebConfiguration -Filter "/system.webServer/httpCompression")
        }
        
        $webConfigDetails = $webConfigList.clientCache
        
        $webConfigList.HeaderCount = $webConfigList.headers.Collection.Count
        $webConfigList.MinSizeForCompression = $webConfigList.compression.minFileSizeForComp
        $webConfigList.CacheControlMode = $webConfigDetails.cacheControlMode
        $webConfigList.CacheMaxAge = $webConfigDetails.cacheControlMaxAge.Days
        
        return $webConfigList
    }
    catch {
        Write-Error "There was an error in getting the application config file- $($_.Exception.Message)"
    }
}

function New-AppPool() {
    <#
.SYNOPSIS
	creates an app pool with the given parameters and our IIS standards and returns the properties of the new application pool
.DESCRIPTION
	use the flag to add a user to the application pool. Use a flag to add 3 webgardens to the application pool.
.PARAMETER appPoolName
    the name of the app pool you want to create
.PARAMETER SetUser
    flag to set the user to a given user
.PARAMETER userName
    the user name to use for this app pool
.PARAMETER password
    the password for this user
.PARAMETER setWebGarden
    flag to set web gardens to 3
.EXAMPLE
	Create-AppPool -appPoolName "CallCenter" -setWebGarden
.NOTES
	http://www.softwire.com/blog/2014/09/29/configuring-iis-with-powershell/
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string]$appPoolName,
        [switch]$SetUser,
        [string]$userName,
        [SecureString]$password,
        [switch]$setWebGarden,
        [switch]$useClassicPipelineMode
    )

    Try {
        $newAppPool = New-WebAppPool -Name $appPoolName
        #set app pool identity if flag set
        if ($SetUser) {
            $newAppPool.processModel.identityType = "SpecificUser"
            $newAppPool.processModel.userName = $userName
            $newAppPool.processModel.password = $password
        }
        if ($setWebGarden) {
            $newAppPool.processModel.workerProcesses.Collection.Count = 3
        }
        if ($useClassicPipelineMode) {
            $newAppPool.managedPipelineMode = "Classic"
        }
        else {
            $newAppPool.managedPipelineMode = "Integrated"
        }
        Set-ApplicationPoolRecycleTimes -ApplicationPoolName $appPoolName -RestartTimes @("02:00")

        #Update-idleTimeout -appPool $appPoolName
        $newAppPool.processModel.idleTimeout = [timespan]::FromMinutes(0)	
        $newAppPool.autoStart = $true
        $newAppPool.managedRuntimeVersion = "v4.0"
        $newAppPool.startMode = "AlwaysRunning"

        $newAppPool | Set-Item
		
        <#
		some good settings - http://byronpate.com/2014/01/iis-configuration-tips/
		after setting everything above, here is the output of the current settings
		#>
        $returnAppPoolDetails = @{}
        $appDetails = Get-ItemProperty IIS:\AppPools\$appPoolName | Select-Object *
        $returnAppPoolDetails.Add("pool name", $appDetails.name)
        $returnAppPoolDetails.Add("autoStart", $appDetails.autoStart)
        $returnAppPoolDetails.Add("managedPipelineMode", $appDetails.managedPipelineMode)
        $returnAppPoolDetails.Add("managedRuntimeVersion", $appDetails.managedRuntimeVersion)
        $returnAppPoolDetails.Add("startMode", $appDetails.startMode)
		
        $recycling = $appDetails.recycling
        $returnAppPoolDetails.Add("periodicRestart.schedule", $recycling.periodicRestart.schedule)
		
        $poolIdentity = $appDetails.processModel
        $returnAppPoolDetails.Add("idleTimeout", $poolIdentity.idleTimeout)
        $returnAppPoolDetails.Add("userName", $poolIdentity.userName)
        $returnAppPoolDetails.Add("password", $poolIdentity.password)
		
        $workerProcesses = $appDetails.workerProcesses
        $returnAppPoolDetails.Add("workerProcesses.Count", $workerProcesses.Collection.Count)
		
        return $returnAppPoolDetails
    }
    catch {
        Write-Error "There was an error in creating an application pool- $($_.Exception.Message)"
    }
}

function Update-ApplicationConfig() {
    <#
.SYNOPSIS
	update the application config file with the standard web server settings, returns the values after updating
.DESCRIPTION
.EXAMPLE
	Update-ApplicationConfig
.NOTES
	https://www.iis.net/configreference/system.webserver/staticcontent/clientcache?showTreeNavigation=true
	
	https://www.iis.net/configreference/system.webserver/httpprotocol/customheaders?showTreeNavigation=true
	
	#How to implement HTTP Compression Setting to compress files larger than 1000 bytes?
	https://www.iis.net/configreference/system.webserver/httpcompression?showTreeNavigation=true
#>

    Try {
	
        $webConfigList = @{}
		
        $clientCache = Get-WebConfiguration -Filter "/system.webServer/staticContent/clientCache"
        $clientCache.cacheControlMode = "UseMaxAge"
        $clientCache.cacheControlMaxAge = ( [TimeSpan]::FromDays(1))
        $clientCache | Set-WebConfiguration "/system.webServer/staticContent/clientCache/cacheControlMode"
		
        Clear-WebConfiguration "/system.webServer/httpProtocol/customHeaders/add[@name='X-Powered-By']"
        $headers = Get-WebConfiguration -Filter "/system.webServer/httpProtocol/customHeaders"
        $webConfigList.Add("Header Count", $headers.Collection.Count)
		
        $compression = Get-WebConfiguration -Filter "/system.webServer/httpCompression"
        $compression.minFileSizeForComp = 1000
        $compression | Set-WebConfiguration "/system.webServer/httpCompression"
        $compression = Get-WebConfiguration -Filter "/system.webServer/httpCompression"
        $webConfigList.Add("min size for compression", $compression.minFileSizeForComp)
		
        $webConfigDetails = Get-WebConfiguration -Filter "/system.webServer/staticContent/clientCache"
        $webConfigList.Add("cache control mode", $webConfigDetails.cacheControlMode)
        $webConfigList.Add("cache max age", $webConfigDetails.cacheControlMaxAge.Days)
		
        return $webConfigList 
    }
    catch {
        Write-Error "There was an error in adjusting the application config file- $($_.Exception.Message)"
    }
}

function Update-IdleTimeout() {
    <#
.SYNOPSIS
	sets the idle timeout for given application pools to 0
.PARAMETER appPool
    the name of the application pool to update idle timeout
.EXAMPLE
	update-idleTimeout -appPoolItem "Call Center"
.NOTES
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string]$appPool
    )
	
    "Server- $($Env:COMPUTERNAME)"
    Try {
        $appPoolItem = get-childitem "IIS:\AppPools\$appPool"
        $result = Get-ItemProperty -Path $appPoolItem.PSPath -Name processModel.idleTimeout
        "Current timeout value for $($appPoolItem.name) is $result"
        If ($result -ne "00:00:00") {
            Set-ItemProperty -Path $appPoolItem.PSPath -Name processModel.idleTimeout -value ( [TimeSpan]::FromMinutes(0))
        }
        $result = Get-ItemProperty -Path $appPoolItem.PSPath -Name processModel.idleTimeout
        "Current timeout value for $($appPoolItem.name) is $result"
    }
    catch {
        Write-Error "There was an error in setting idle timeout- $($_.Exception.Message)"
    }
}

function Set-ApplicationPoolRecycleTimes {
    <#
.SYNOPSIS
	sets the recycle times for a given application pool
.PARAMETER ApplicationPoolName
    The name of the application pool
.PARAMETER RestartTimes
	A string array of times to restart 
.EXAMPLE
	Set-ApplicationPoolRecycleTimes -ApplicationPoolName "Example Application Pool" -RestartTimes @("05:55", "12:55", "17:00")
.NOTES
	got this function from-
	https://www.habaneroconsulting.com/insights/Set-the-Specific-Times-to-Recycle-an-Application-Pool-with-PowerShell#.WIklOlMrJhE
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string]$ApplicationPoolName,
        [Parameter(Mandatory = $True)][string[]]$RestartTimes
    )
     
    Write-Output "Updating recycle times for $ApplicationPoolName"
    
    try {
        # Delete all existing recycle times
        Clear-ItemProperty IIS:\AppPools\$ApplicationPoolName -Name Recycling.periodicRestart.schedule
	     
        foreach ($restartTime in $RestartTimes) {
	 
            Write-Output "Adding recycle at $restartTime"
            # Set the application pool to restart at the time we want
            New-ItemProperty -Path "IIS:\AppPools\$ApplicationPoolName" -Name Recycling.periodicRestart.schedule -Value @{value = $restartTime }
	         
        } # End foreach restarttime
    }
    catch {
        Write-Error "There was an error in setting app pool recycle times- $($_.Exception.Message)"
    }
     
} 

function New-Website() {
    <#
.SYNOPSIS
	creates site with the given parameters and our IIS standards and returns the properties of the new site 
.DESCRIPTION
	the default port 80 is set but you can specify to add HTTPS over 443
	site URL should be the full URL expected but can be blank if using wildcards
.PARAMETER siteName
    The Name of site to create
.PARAMETER sitePath
    path of site to create
.PARAMETER siteURL
    expected URL of site, should be blank if using wildcard URL
.PARAMETER siteIP
    IP site will listen on
.PARAMETER sitePort
    optional port for initial binding (default is 80)
.PARAMETER siteID
    optional site ID
.PARAMETER appPoolName
    application pool site should run under (optional)
.PARAMETER preloadEnabled
    flag to set preload if required, typically set for main sites but not tools, LIS, Bene-calcs, maintenance, etc
.PARAMETER UseSSL
    flag to add port 443 when binding the site
.PARAMETER certPath
    path to the certificate to import
.PARAMETER pfxPass
    the password (if needed) for the certificate
.PARAMETER IISlogpath
    path to the log file, defaults to D:\Websites\Files\Logs\IIS	
.NOTES
	Got the values for logging from https://www.iis.net/configreference/system.applicationhost/sites/sitedefaults/logfile
	Value	Description
	Daily	Create a new log file daily. The numeric value is 1.
	Hourly	Create a new log file hourly. The numeric value is 4.
	MaxSize	Create a new log file when a maximum size is reached. The maximum size is specified in the truncateSize attribute. The numeric value is 0.
	Monthly	Create a new log file monthly. The numeric value is 3.
	Weekly	Create a new log file weekly. The numeric value is 2.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string]$siteName,
        [Parameter(Mandatory = $True)][string]$sitePath,
        [string]$siteURL,
        [string]$siteIP,
        [int]$sitePort = 80,
        [int]$siteID,
        [switch]$UseSSL,
        [string]$appPoolName = $null,
        [switch]$preloadEnabled,
        [string]$certPath,
        [string]$pfxPass,
        [string]$IISlogpath = "D:\Websites\Files\Logs\IIS\"
    )
    #Import-Module WebAdministration
    #set <httpRuntime enableVersionHeader="false" />??? is this removing the x-powered-by?
	
    Try {
        New-Item IIS:\Sites\$siteName -bindings @{protocol = 'HTTP'; bindingInformation = $siteIp + ':' + $sitePort + ':' + $siteURL } -PhysicalPath $sitePath -Id $siteID
        if ($UseSSL) {
            #flag set to add HTTPS binding too
            New-WebBinding -Name $siteName -IPAddress $siteIP -Port 443 -HostHeader $siteURL -Protocol "HTTPS"
            $certThumbprint = Import-PfxCertificate -certPath $certPath -pfxPass $pfxPass
            Set-CertToSite -certThumbprint $certThumbprint -SiteName $siteName
        }
		
        #test if given an app pool and add to site if so
        if ($appPoolName -ne $null) {
            Set-SiteAppPool -siteName $siteName -appPoolName $appPoolName
            if ($preloadEnabled) {
                #add preload to site
                set-itemproperty IIS:\Sites\$siteName -name applicationDefaults.preloadEnabled -value True
            }
        }
		
        #set the logging to correct folder
        Set-ItemProperty "IIS:\Sites\$SiteName" -name logFile -value @{directory = $IISlogpath }
        Set-ItemProperty "IIS:\Sites\$SiteName" -name logFile -value @{logFormat = "IIS" }
        Set-ItemProperty "IIS:\Sites\$SiteName" -name logFile -value @{localTimeRollover = $true }
        Set-ItemProperty "IIS:\Sites\$SiteName" -name logFile -value @{period = 1 }
		
        #read the site and return current values
        $returnSite = Get-Item IIS:\Sites\$siteName

        $returnList = @{
            "siteName"        = $returnSite.name
            "siteID"          = $returnSite.id
            "app pool"        = $returnSite.applicationPool
            "preload enabled" = $returnSite.applicationDefaults.preloadEnabled
        }

        $bindings = $returnSite.bindings.Collection | Where-Object { $_.protocol -in @("http", "https") } | ForEach-Object {
            @{
                $_.protocol = $_.bindingInformation
            }
        }

        $logfile = @{
            "logfile directory"       = $returnSite.logFile.directory
            "log format"              = $returnSite.logFile.logFormat
            "log rollover local time" = $returnSite.logFile.localTimeRollover
            "log rollover period"     = $returnSite.logFile.period
        }

        $returnList += @{
            "bindings" = $bindings
            "logfile"  = $logfile
        }

        $returnObject = New-Object -TypeName psobject -Property $returnList

        return $returnObject
    }
    catch {
        Write-Error "There was an error in creating a web site- $($_.Exception.Message)"
    }
}

function Set-SiteAppPool() {
    <#
.SYNOPSIS
	adds the given application pool to the given site in iis:\sites\
.PARAMETER siteName
     the name of the site to edit
.PARAMETER appPoolName
    the name of the application pool to add to site
.EXAMPLE
	Set-SiteAppPool -siteName CallCenter -appPoolName CallCenter
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string]$siteName,
        [Parameter(Mandatory = $True)][string]$appPoolName
    )

    #Import-Module WebAdministration
    Try {
        Set-ItemProperty "IIS:\sites\$siteName" -Name applicationPool -Value $appPoolName
    }
    catch {
        Write-Error "There was an error in setting a web site application pool- $($_.Exception.Message)"
    }
}

function Import-PfxCertificate { 
    <#
.SYNOPSIS
    Imports a PFX certificate into the certificate store.
.DESCRIPTION
    This function imports a PFX certificate into the specified certificate store. It supports specifying the certificate path, the certificate store, and the password for the PFX file.
.PARAMETER certPath
    The path to the PFX certificate file.
.PARAMETER certRootStore
    The root store where the certificate store is located. Default value is "LocalMachine".
.PARAMETER certStore
    The name of the certificate store. Default value is "My".
.PARAMETER pfxPass
    The password for the PFX certificate. If not provided, the function will prompt for the password.
.EXAMPLE
    Import-PfxCertificate -certPath "C:\path\to\certificate.pfx" -certRootStore "LocalMachine" -certStore "My" -pfxPass "password"

    This example imports a PFX certificate located at "C:\path\to\certificate.pfx" into the "My" certificate store in the "LocalMachine" root store.
.OUTPUTS
    The thumbprint of the imported certificate.
#>
    [CmdletBinding()]
    param(
        [String]$certPath,
        [String]$certRootStore = "localmachine",
        [String]$certStore = "My",
        [String]$pfxPass = $null
    ) 

    Add-Type -TypeDefinition @"
        using System;
        using System.Security.Cryptography.X509Certificates;

        public static class CertificateUtils
        {
            public static void ImportPfxCertificate(string certPath, string certStoreName, string certRootStoreName, string pfxPass)
            {
                using (var pfx = new X509Certificate2(certPath, pfxPass, X509KeyStorageFlags.Exportable | X509KeyStorageFlags.PersistKeySet))
                {
                    using (var store = new X509Store(certStoreName, Enum.Parse<StoreLocation>(certRootStoreName)))
                    {
                        store.Open(OpenFlags.MaxAllowed);
                        store.AddRange(new X509Certificate2Collection { pfx });
                    }
                }
            }
        }
"@

    try {
        [CertificateUtils]::ImportPfxCertificate($certPath, $certStore, $certRootStore, $pfxPass)
        $certThumbprint = (Get-PfxCertificate -FilePath $certPath).Thumbprint
        return $certThumbprint
    }
    catch {
        Write-Error "There was an error in importing certificate- $($_.Exception.Message)"
    }
}


function Set-CertToSite() {
    <#
.SYNOPSIS
    Binds a certificate to a web site.
.DESCRIPTION
    The Set-CertToSite function binds a certificate to a web site by adding the certificate to the SSL binding of the site.
.PARAMETER certThumbprint
    Specifies the thumbprint of the certificate to be bound.
.PARAMETER SiteName
    Specifies the name of the web site to which the certificate will be bound.
.EXAMPLE
    Set-CertToSite -certThumbprint "AB12C34D567E89F01234567890A1B234C567890" -SiteName "MyWebsite"

    This example binds a certificate with the specified thumbprint to a web site named "MyWebsite".
#>
    [CmdletBinding()]
    param(
        $certThumbprint,
        $SiteName
    )
    Write-Host 'Bind certificate with Thumbprint' $certThumbprint
    try {
        $obj = get-webconfiguration "//sites/site[@name='$SiteName']"
        $binding = $obj.bindings.Collection[0]
        $method = $binding.Methods["AddSslCertificate"]
        $methodInstance = $method.CreateInstance()
        $methodInstance.Input.SetAttributeValue("certificateHash", $certThumbprint)
        $methodInstance.Input.SetAttributeValue("certificateStoreName", $certStore)
        $methodInstance.Execute()
    }
    catch {
        Write-Error "There was an error in binding certificate to web site- $($_.Exception.Message)"
    }
}

function Set-SiteBindings() {
    <#
.SYNOPSIS
    Updates the bindings for a given site.
.DESCRIPTION
    This function updates the bindings for a given site by adding or replacing bindings based on the input provided.
.PARAMETER siteName
    The name of the site for which the bindings need to be updated.
.PARAMETER bindingList
    An array of binding information strings to be added or replaced.
.PARAMETER replace
    If specified, existing bindings with the same binding information will be replaced with the new bindings.
.EXAMPLE
    Set-SiteBindings -siteName "MySite" -bindingList @("http://example.com:80", "https://example.com:443") -replace
    Updates the bindings for the site "MySite" by adding or replacing the bindings "http://example.com:80" and "https://example.com:443".
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string]$siteName,
        [Parameter(Mandatory = $True)][string[]]$bindingList,
        [switch]$replace
    )

    Try {
        # Get the list of existing bindings for the site
        $existingBindings = Get-WebBinding -Name $siteName

        # Loop through the inputted bindings
        foreach ($binding in $bindingList) {
            # Check if the current binding already exists
            $existingBinding = $existingBindings | Where-Object { $_.bindingInformation -eq $binding }

            if ($existingBinding) {
                # If the replace switch is specified, remove the existing binding and add the new one
                if ($replace) {
                    Remove-WebBinding -Name $siteName -BindingInformation $binding
                    Add-WebBinding -Name $siteName -BindingInformation $binding
                }
            }
            else {
                # If the binding does not exist, add it
                Add-WebBinding -Name $siteName -BindingInformation $binding
            }
        }

        Write-Output "Site bindings updated successfully."
    }
    catch {
        Write-Error "There was an error in changing the site bindings- $($_.Exception.Message)"
    }
}
