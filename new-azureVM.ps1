Function Assert-VMonline {
    <#
    .SYNOPSIS
    Check if VM is ready and online

    .DESCRIPTION
    Function to make sure a VM is created and running before running subsequent commands. This will loop with a definable wait time before checking again. It won't exit the loop until the server passes the check.

    .EXAMPLE
    Assert-VMonline -ResourceGroupName CCAT24RGPEQBN -VMname "$Location$CUS$SetEV$T"

    #>

    Param (
        [Parameter(Mandatory = $true, HelpMessage = "Name of server to check for")][string]$VMname,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group VM should be in")][string]$ResourceGroupName,
        [Parameter(HelpMessage = "Number of seconds to wait, default is 10")][int]$waitTime = 10
    )
    do {
        try {
            Write-Verbose "Waiting for $VMname to come online..."
            $VMCHECK = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -like "$VMname" }
            Start-Sleep $waitTime
        }
        catch {
            Write-Error "There was an issue checking if the VM was online:`n$($Error[0].Exception.Message)`n$($_.InvocationInfo.Line)"
        }
    } until ( $null -ne $VMCHECK)
    Write-Verbose "$VMname is now online" 
    return $true
}

function New-AzureVM {
    <#
    .SYNOPSIS
    Creates new VM per standards
    
    .DESCRIPTION
    Creates new Azure Virtual Machine with given values and some standards. 
    
    .PARAMETER resourceGroup
    Resource group object to put VM into

    .PARAMETER vmSubnet
    Subnet to put VM into

    .PARAMETER Credential
    Default login for VM
    
    .PARAMETER VMname
    VMname
    
    .PARAMETER VMSize
    Size of VM
    
    .PARAMETER NetworkSecurityGroup
    Optional, add a Network Security Group to the VM Network Interface

    .PARAMETER LoadBalancerBackendAddressPool
    Optional, add the VM Network Interface to a load balancer

    .PARAMETER diskQuantity
    Optional, if you want more than the OS disk, enter 1 or more additional disks

    .PARAMETER linux
    Add this parameter to make linux servers, default is Windows server
    
    .PARAMETER force
    Add this parameter to overwrite any existing VM and network interfaces

    .EXAMPLE
    New-AzureVM -resourceGroup "myResourceGroup" -vmSubnet $vnet.Subnets[0] -Credential $cred -VMname "myVM$i" -VMSize 'Standard_DS1_v2' -NetworkSecurityGroup $nsg -LoadBalancerBackendAddressPool $bepool -linux
    
    .EXAMPLE
    New-AzureVM -resourceGroup "myResourceGroup" -vmSubnet $vnet.Subnets[0] -Credential $cred -VMname "myVM$i" 
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Resource group object to put VM into')][ValidateNotNullOrEmpty()][Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceGroup]$resourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = 'Subnet to put VM into')][ValidateNotNullOrEmpty()][Microsoft.Azure.Commands.Network.Models.PSSubnet]$vmSubnet,
        [Parameter(Mandatory = $true, HelpMessage = 'Default login for VM')][ValidateNotNullOrEmpty()][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $true, HelpMessage = 'Name of VM')][ValidateNotNullOrEmpty()][string]$VMname,
        [Parameter(HelpMessage = 'Size of VM')][string]$VMSize = 'Standard_DS1_v2',
        [Parameter(HelpMessage = 'Optional, add a Network Security Group to the VM Network Interface')][Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]$NetworkSecurityGroup,
        [Parameter(HelpMessage = 'Optional, add the VM Network Interface to a load balancer')][Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool]$LoadBalancerBackendAddressPool,
        [Parameter(HelpMessage = 'Optional, if you want more than the OS disk, enter 1 or more additional disks')][int]$diskQuantity = 0,
        [Parameter(HelpMessage = 'Add this parameter to make linux servers, default is Windows server')][switch]$linux,
        [Parameter(HelpMessage = 'Add this parameter to overwrite any existing VM and network interfaces')][switch]$force
    )
    try {
        Write-Verbose "Testing if VM already exists with same name..."
        $test = Get-AzVM -Name $VMname -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction SilentlyContinue
        if (($null -ne $test) -or ($force)) {
            Write-Error "VM found with same name, exiting function..."
            Exit -100
        }

        Write-Verbose "Testing if network interface already exists with same name..."
        $test2 = Get-AzNetworkInterface -Name "$VMname-nic" -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction SilentlyContinue
        if (($null -ne $test2) -or ($force)) {
            $nicVM = $test2
            Write-Warning "Network Interface with same name found, using $($nicVM.Name)"
        }
        else {
            Write-Verbose "Making network interface for VM $VMname"
            $nicTags = @{
                "Creator"      = $env:USERNAME;
                "Date"         = Get-Date -Format ("yyyy-MM-dd_hh-mm-ss");
                "ResourceType" = "Network Interface"
            }
            $nicValues = @{
                Name              = "$VMname-nic" 
                ResourceGroupName = $resourceGroup.ResourceGroupName 
                Location          = $resourceGroup.Location 
                Subnet            = $vmSubnet 
                Tag               = $nicTags
                Force             = $true
            }
            if ($null -ne $NetworkSecurityGroup) {
                $nicValues.Add("NetworkSecurityGroup", $NetworkSecurityGroup)
            }
            if ($null -ne $LoadBalancerBackendAddressPool) {
                $nicValues.Add("LoadBalancerBackendAddressPool", $LoadBalancerBackendAddressPool)
            }
            $nicVM = New-AzNetworkInterface @nicValues
            Write-Verbose "Made $($nicVM.Name)"
        }

        ## Create a virtual machine configuration for VMs ##
        Write-Verbose "Gathering details about VM..."
        $VMTags = @{
            "Creator"      = $env:USERNAME;
            "Date"         = Get-Date -Format ("yyyy-MM-dd_hh-mm-ss");
            "ResourceType" = "VM"
        }
        $OSDiskName = "$VMname" + "-os"
        $vmsz = @{
            VMName = $VMname
            VMSize = $VMSize
            Tags   = $VMTags
        }
        if ($linux) {
            Write-Verbose "Setting OS as Unbuntu Linux 18.04-LTS..."  ##if updating below, update here too!
            $vmos = @{
                ComputerName = $VMname
                Credential   = $Credential
                Linux        = $true
            }
            $vmimage = @{
                PublisherName = 'Canonical'  ## TODO use other options?
                Offer         = 'UbuntuServer'
                Skus          = '18.04-LTS' ## TOD make variable?
                Version       = 'latest'    
            }
            #bundle everything above into one config variable to tell what sort of machine to make
            $vmConfig = New-AzVMConfig @vmsz `
            | Set-AzVMOperatingSystem @vmos `
            | Set-AzVMSourceImage @vmimage `
            | Add-AzVMNetworkInterface -Id $nicVM.Id
            
            #Set-AzVMOSDisk -VM $vmConfig -Name $OSDiskName -Linux
        }
        else {
            Write-Verbose "Setting OS as Windows Server 2019 Datacenter..."  ##if updating below, update here too!
            $vmos = @{
                ComputerName = $VMname
                Credential   = $Credential
                Windows      = $true
            }
            $vmimage = @{
                PublisherName = "MicrosoftWindowsServer"
                Offer         = "WindowsServer"
                Sku           = "2019-Datacenter" ## TODO make variable?
                Version       = "latest"
            }
            #bundle everything above into one config variable to tell what sort of machine to make
            $vmConfig = New-AzVMConfig @vmsz `
            | Set-AzVMOperatingSystem @vmos `
            | Set-AzVMSourceImage @vmimage `
            | Add-AzVMNetworkInterface -Id $nicVM.Id
            
            ### TODO get the os disk name adding right ###
            #Set-AzVMOSDisk -VM $vmConfig -Name $OSDiskName
        }

        ## Create the virtual machine for VMs ##
        $vm = @{
            ResourceGroupName = $resourceGroup.ResourceGroupName
            Location          = $resourceGroup.Location
            VM                = $vmConfig
            Zone              = "1" #TODO - availability sets
        }
        Write-Verbose "Making VM: $($vmsz.VMName)... "
        New-AzVM @vm
        $return = Get-AzVM -ResourceGroupName $resourceGroup.ResourceGroupName -Name $vmos.ComputerName
        Write-Verbose "Made $($return.vm.name)" 

        if ($diskQuantity -ge 1) {
            Write-Verbose "Configuring drive to add..."
            $VMTags.ResourceType = "HDD"
            $diskConfigValues = @{
                SkuName      = 'Premium_LRS'
                Location     = $resourceGroup.Location 
                CreateOption = 'Empty'
                DiskSizeGB   = 100
                Zone         = 1
                Tag          = $VMTags
            }
            $diskConfig = New-AzDiskConfig @diskConfigValues
            for ($i = 1; $i -le $diskQuantity; $i++) {
                $diskName = $return.name + "_datadisk_" + $i.ToString()
            }

            Write-Verbose "Making drives..."
            $DataDisk = New-AzDisk -DiskName $diskName -Disk $diskConfig -ResourceGroupName $resourceGroup.ResourceGroupName

            Write-Verbose "Adding drive to server..."
            Add-AzVMDataDisk -VM $return -Name $DiskName -CreateOption Attach -ManagedDiskId $DataDisk.Id -Lun 0
            
        }

        If (!$linux) {
            #kinda confusing, as a switch parameter, $linux is false by default, so the test is reversed from what you might expect
            #don't want to have an explicit windows switch so false $linux is windows, see? 

            if (Assert-VMonline -ResourceGroupName $resourceGroup.ResourceGroupName -VMname $return.name -Verbose) {
                Write-Verbose "Adjusting drive letters in Windows servers..."
                If (Test-WSMan -ComputerName $return.name -eq 0) {
                    Write-Verbose "$return.name is alive" 
        
                    Invoke-Command -ComputerName $return.name -ScriptBlock {
                        Write-Verbose "Formatting E drive on $ENV:COMPUTERNAME"
                        # Check if CD-ROM is using E
                        Get-WmiObject -Class Win32_volume -Filter 'DriveType=5' |
                        Select-Object -First 1 |
                        Set-WmiInstance -Arguments @{DriveLetter = 'R:' }
                        # Init the E drive
                        Get-Disk |
                        Where-Object partitionstyle -eq 'raw' |
                        Initialize-Disk -PartitionStyle MBR -PassThru |
                        New-Partition -DriveLetter E -UseMaximumSize |
                        Format-Volume -FileSystem NTFS -NewFileSystemLabel “Application” -Confirm:$false
                    }
                } 

                Write-Verbose "Update license to Azure Hybrid Benefit" 
                $return.LicenseType = "Windows_Server"
                Update-AzVM -ResourceGroupName $resourceGroup.ResourceGroupName -VM $return
            }
        }

        return $return
    }
    catch {
        Write-Error "There was an issue making the VM:`n$($Error[0].Exception.Message)`n$($_.InvocationInfo.Line)"    
    }
}

function New-AzureNetwork {
    <#
    .SYNOPSIS
    Creates new virtual network with provided inputs

    .DESCRIPTION
    Creates new virtual network with provided inputs
    
    .PARAMETER NetworkName
    The name of this network

    .PARAMETER resourceGroup
    Resource group object to put VM into

    .PARAMETER AddressPrefix
    The CIDR range for the whole network

    .PARAMETER SubnetAddressPrefix
    Array of Subnet CIDR to make within this network

    .PARAMETER force
    Add this parameter to overwrite existing virtual network
    
    .EXAMPLE
    New-AzureNetwork -NetworkName "myVNet" -AddressPrefix '172.28.0.0/16' -resourceGroup $resourceGroup -SubnetAddressPrefix @('172.28.0.0/24', '172.28.1.0/24') -Verbose
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'The name of this network')][string]$NetworkName,
        [Parameter(Mandatory = $true, HelpMessage = 'Resource group object to put VM into')][ValidateNotNullOrEmpty()][Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceGroup]$resourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = 'The CIDR range for the whole network')][string]$AddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = 'Array of Subnet CIDR to make within this network')][string[]]$SubnetAddressPrefix,
        [Parameter(HelpMessage = 'Add this parameter to overwrite existing virtual network')][switch]$force
    )

    try {
        $test = Get-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction SilentlyContinue
        if ($null -eq $test) {
            Write-Verbose "Making subnet to go within network..."
            $subnetArray = @()

            foreach ($item in $SubnetAddressPrefix) {
                Write-Verbose "making subnet '$item'..."
                $subnetValues = @{
                    Name                           = "$NetworkName-Subnet$($NetworkName[$SubnetAddressPrefix.IndexOf($item)])"
                    AddressPrefix                  = $item
                    #NatGateway = ""
                    PrivateEndpointNetworkPolicies = "Disabled"
                }
                $subnet = New-AzVirtualNetworkSubnetConfig @subnetValues #### TODO - update at some point, when NATGateways are a thing
                Write-Verbose "Made $($subnet.Name), adding to array of subnets"
                $subnetArray += $subnet
            }
            $subnetArray

            Write-Verbose "Making virtual network '$NetworkName'..."
            $netValues = @{
                Name              = $NetworkName
                ResourceGroupName = $resourceGroup.ResourceGroupName
                Location          = $resourceGroup.Location
                AddressPrefix     = $AddressPrefix
                Subnet            = $subnetArray
            }
            if ($force) {
                Write-Verbose "Setting force option on network creation" 
                $netValues.Add("Force", $true)
            }
            $vnet = New-AzVirtualNetwork @netValues
            Write-Verbose "Made $($vnet.Name)"
        }
        else {
            Write-Error "Network of this name already exists. You can rerun with -force to overwrite existing network."
            Exit -300
        }
        return $vnet
    }
    catch {
        Write-Error "There was an issue making the Virtual Network:`n$($Error[0].Exception.Message)`n$($_.InvocationInfo.Line)"
    }
}

function New-AzureSecurityGroup {
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $groupName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][ValidateSetAttribute("Tcp", "Udp", "Both")] [string] $Protocol,
        [Parameter(Mandatory = $true)][ValidateSetAttribute("Inbound", "Outbound")] [string] $Direction,
        [int] $Priority = 1000,
        [string] $sourceAddressPrefix = '*',
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $sourcePortRange,
        [string] $destinationAddressPrefix = '*',
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $destinationPortRange,
        [Parameter(Mandatory = $true)][ValidateSetAttribute("Allow", "Deny")] [string] $Access
    )
    try {
        if ($Protocol -eq "Both") { $Protocol = '*' }

        Write-Verbose "Creating Security Group Config..."
        $returnSG = New-AzNetworkSecurityRuleConfig `
            -Name $groupName  `
            -Protocol $Protocol `
            -Direction $Direction `
            -Priority $Priority `
            -SourceAddressPrefix $sourceAddressPrefix `
            -SourcePortRange $sourcePortRange `
            -DestinationAddressPrefix $destinationAddressPrefix `
            -DestinationPortRange $destinationPortRange `
            -Access $Access
    }
    catch {
        Write-Error "Can't make the security group: $($Error[0].Exception.Message)" 
    }
    return $returnSG
}

Export-ModuleMember -Function Assert-VMonline, New-AzureVM, New-AzureNetwork, New-AzureSecurityGroup
