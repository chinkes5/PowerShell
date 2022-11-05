Function Initialize-Terraform {
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = "The path to the terraform zip file",Mandatory)]$TFzip
    )

    $TFPath = "C:\Program Files\Terraform\"
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
        New-Item -Path "C:\Program Files\Terraform\" -ItemType Directory
        # the expand-archive will make the destination if doesn't exist but I'm being extra
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
            exit 0
        }
    }
    Write-Verbose "Did not find Terraform in Path, adding..."
    # $env:Path += ";$TFPath"
    # setx /M path "%PATH%;$TFPath"
    [Environment]::SetEnvironmentVariable("PATH", "$($Env:PATH);$TFPath", [EnvironmentVariableTarget]::Machine)

    $env:Path
}
