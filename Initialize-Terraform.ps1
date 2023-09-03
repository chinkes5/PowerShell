Function Initialize-Terraform {
    <#
.SYNOPSIS
    A script to download latest Terraform ZIP and install it in a given location
.DESCRIPTION
    This will look for the latest stable Terraform version, download it to a file, and try to install it, setting the path environment variable in the path you give.
.PARAMETER TFzipPath
    Path to save the download at, default is your home directory, i.e. $HOME\Downloads.
.PARAMETER TFPath
    Path to Terraform program, default is C:\Program Files
.EXAMPLE
    Initialize-Terraform -TFzip C:\TEMP\
.LINK
    # TODO: use the ideas from link to get the version stuff better
    https://gist.github.com/rchaganti/078556db37f43ec4d33de8f3a2bb9b16
#>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = "The path where to download the terraform zip file to, default is `$HOME\Downloads")]$TFzipPath = "$HOME\Downloads\",
        [Parameter(HelpMessage = 'Path to where you want Terraform running from, default is C:\Program Files')]$TFPath = "C:\Program Files\Terraform\"
    )

    try {
        Write-Verbose "Getting list of Terraform versions..."    
        $getVersionList = Invoke-RestMethod -Uri "https://api.github.com/repos/hashicorp/terraform/releases"
        
        $versionList = $getVersionList | Where-Object { !$_.prerelease } | Sort-Object created_at -Descending | Select-Object -First 1
        Write-Verbose "Found version $($versionList.name)!"
        $version = $versionList.name.trim('v')
    }
    catch {
        Throw "Can't get list of Terraform versions - $($Error[0].Exception.Message)"
    }

    try {
        Write-Verbose "Downloading checksums and hope to find the latest version..."
        $ChecksumURL = "https://releases.hashicorp.com/terraform/$version/terraform_$version`_SHA256SUMS"
        $ChecksumList = Invoke-RestMethod -Uri $ChecksumURL -ContentType "text/plain"
        foreach ($line in $ChecksumList -split "`n") {
            Write-Verbose "working on $line..."
            if ($line.Contains("_windows_amd64.zip")) {
                $Checksum = ($line.Split(' ')[0]).Trim()
                break
            }
        }
    }
    catch {
        Throw "Can't get checksum data for Terraform - $($Error[0].Exception.Message)"
    }

    try {
        Write-Verbose "Downloading Terraform $version..."
        $DownloadFile = Join-Path $TFzipPath -ChildPath "terraform_$version`_windows_amd64.zip"
        $DownloadURL = "https://releases.hashicorp.com/terraform/$version/terraform_$version`_windows_amd64.zip"
        Invoke-RestMethod -Uri $DownloadURL -OutFile $DownloadFile
    }
    catch {
        Throw "Can't get Terraform download - $($Error[0].Exception.Message)"
    }

    try {
        Write-Verbose "Testing Checksum..."
        $downloadHash = Get-FileHash -Path $DownloadFile -Algorithm SHA256
        if ($downloadHash.Hash -ne $Checksum) {
            throw "Checksums don't match!"
        }
        else {
            Unblock-File -Path $DownloadFile
        }
    
        if (Test-Path $TFPath -PathType Container) {
            Write-Verbose "Found the Terraform program folder!"
            $TFexe = Get-ChildItem $TFPath
            if ($TFexe.Name -ne "terraform.exe") {
                Write-Verbose "No Terraform executable!"
            }
            # no 'else' here, not deleting the existing file or whatever
        }
        else {
            Write-Verbose "Making destination for Terraform..."
            New-Item -Path $TFPath -ItemType Directory
            # the expand-archive will make the destination if doesn't exist but I'm being extra careful
        }
    
        if (test-path $DownloadFile -PathType Leaf) {
            Write-Verbose "Found the path as given, unzipping Terraform..."
            Expand-Archive -LiteralPath $DownloadFile -DestinationPath $TFPath -Force
        }
        else {
            throw "Can't find path to terraform zip file!"
        }
    
        Write-Verbose "Check PATH for Terraform..."
        foreach ($item in $env:Path.Split(";")) { 
            if ($item -eq $TFPath) {
                Write-Verbose "Found Terraform Path variable, stopping..."
    
                Write-Output "Current Terraform Version after script has run:"
                terraform -version
            
                exit 0
            }
        }
        Write-Verbose "Did not find Terraform in Path, adding..."
        # $env:Path += ";$TFPath"
        # setx /M path "%PATH%;$TFPath"
        [Environment]::SetEnvironmentVariable("PATH", "$($Env:PATH);$TFPath", [EnvironmentVariableTarget]::Machine)
        $env:Path.Split(';')
    }
    catch {
        Throw "Can't get install Terraform - $($Error[0].Exception.Message)"
    }
    Write-Output "Current Terraform Version after script has run:"
    terraform -version
}

