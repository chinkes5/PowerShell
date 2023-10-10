# https://www.saotn.org/how-do-i-get-my-yubikey-to-work-with-ssh-in-windows-11-and-windows-10/

Write-Output "removing old ssh..."
# TODO: check if ssh is installed before removing
Remove-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Write-Output "Downloading SSH..."
# TODO: get latest version
# TODO: set download path
Invoke-RestMethod -Uri https://github.com/PowerShell/Win32-OpenSSH/releases/download/v8.9.1.0/OpenSSH-Win64-v8.9.1.0.msi -OutFile d:\downloads\OpenSSH-Win64-v8.9.1.0.msi

Write-Output "Installing SSH for this user only..."
Start-Process -NoNewWindow msiexec.exe -ArgumentList "/i d:\downloads\OpenSSH-Win64-v8.9.1.0.msi ADDLOCAL=Client ADD_PATH=1" -Wait

Write-Output "SSH Updated, reboot required"