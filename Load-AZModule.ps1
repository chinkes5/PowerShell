If ($null -eq (Get-InstalledModule Az)) {
    #main pre-req to get AZ cmdlet
    Write-Output "Downloading PS Get so we can update modules from PSGallery..."
    Install-Module -Name PowerShellGet -Force -AllowClobber
    Write-Output "Downloading Azure module..."
    #need this module to run any commands against Azure
    Save-Module -Name Az -Repository PSGallery -Path $env:ProgramFiles\WindowsPowerShell\Modules
    Write-Output "Importing Azure module so the commands can be used..."
    Import-Module -Name Az -Force
}
else {
    Write-Output "Azure PowerShell Module installed"
}
