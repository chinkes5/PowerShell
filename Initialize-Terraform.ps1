Function Initialize-Terraform {
    <#
.SYNOPSIS
    A script to take a downloaded ZIP of Terraform and install it in a given location
.DESCRIPTION
    This will look at the given ZIP file and try to install it, setting the path environment variable, in the path you give.
.PARAMETER TFzip
    This the ZIP file you downloaded from Terraform, likely https://developer.hashicorp.com/terraform/downloads. A full path and the file is required.
.PARAMETER TFPath
.EXAMPLE
    Initialize-Terraform -TFzip C:\Downloads\terraform_1.4.4_windows_amd64.zip
#>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = "The path to the terraform zip file", Mandatory)]$TFzip,
        [Parameter(HelpMessage = 'Path to where you want Terraform running from, default is C:\Program Files')]$TFPath = "C:\Program Files\Terraform\"
    )

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
