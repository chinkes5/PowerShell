Function Initialize-Terraform {
    <#
.SYNOPSIS
    A script to download ZIP of Terraform and install it in a given location
.DESCRIPTION
    This will look at the given ZIP file and try to install it, setting the path environment variable, in the path you give.
.PARAMETER TFzip
    Path to save the download at, default is your home directory, i.e. $HOME\Downloads.
.PARAMETER TFPath
    Path to Terraform program, default is C:\Program Files
.EXAMPLE
    Initialize-Terraform -TFzip C:\Downloads\
.LINK
    https://gist.github.com/rchaganti/078556db37f43ec4d33de8f3a2bb9b16
#>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = "The path to the terraform zip file")]$TFzipPath = "$HOME\Downloads\",
        [Parameter(HelpMessage = 'Path to where you want Terraform running from, default is C:\Program Files')]$TFPath = "C:\Program Files\Terraform\"
    )

    # Starting with version 1.5.5, as that's where we are today, will hope to find latest from this...
    # TODO: use the ideas from link to get the version stuff better
    Write-Verbose "Downloading checksums and hope to find the latest version..."
    $ChecksumURL = "https://releases.hashicorp.com/terraform/1.5.5/terraform_1.5.5_SHA256SUMS"
    $ChecksumList = Invoke-RestMethod -Uri $ChecksumURL -ContentType "text/plain"
    foreach ($line in $ChecksumList -split "`n") {
        Write-Verbose "working on $line..."
        if ($line.Contains("_windows_386.zip")) {
            # $ChecksumList[$ChecksumList.IndexOf($line)]
            $Checksum = ($line.Split(' ')[0]).Trim()
            $file = ($line.Split(' ')[2]).Trim()
            $version = $file.Split('_')[1]
            break
        }
    }

    Write-Verbose "Downloading Terraform $version..."
    $DownloadURL = "https://releases.hashicorp.com/terraform/$version/terraform_$version`_windows_386.zip"
    Invoke-RestMethod -Uri $DownloadURL -OutFile (Join-Path $TFzipPath -ChildPath "terraform_$version`_windows_386.zip")

    Write-Verbose "Testing Checksum..."
    $downloadHash = Get-FileHash -Path $TFzipPath -Algorithm SHA256
    if ($downloadHash.Hash -ne $Checksum) {
        throw "Checksums don't match!"
    }

    if (Test-Path $TFPath) {
        Write-Verbose "Found the Terraform program folder"
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

    if (test-path $TFzip) {
        Write-Verbose "Found the path as given, unzipping Terraform..."
        Expand-Archive -LiteralPath $TFzip -DestinationPath $TFPath -Force
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

    Write-Output "Current Terraform Version after script has run:"
    terraform -version
}
