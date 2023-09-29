Function Private:Write-Log() {
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = 'The message to put in the log file', Mandatory = $true)][String]$messageToLog,
        [Parameter(HelpMessage = 'Name of log file')][string]$logName = "Password_Recycling",
        [Parameter(HelpMessage = 'Path to log file')][string]$logPath = "C:\logs\",
        [Parameter(HelpMessage = 'Number of days of logs to keep, reducing this will irrevocably delete files')][int]$LogDaysToKeep = 365
    )

    $now = get-date
    If (-not (Test-Path $logPath -PathType Container)) {
        mkdir $logPath
        $logMessage = "$now $env:COMPUTERNAME $messageToLog"
    }
    else {
        # Found the folder, now to clean it up!
        $files = Get-ChildItem -Path $logPath -Filter $logName | Where-Object { $_.LastWriteTimeUtc -lt (Get-Date).AddDays(-$LogDaysToKeep) }
        if ($files.Count -gt 0) {
            $logMessage = "$now $env:COMPUTERNAME Deleting files: $($files.Name -join `"`n`")`n" # -join revises the array with new delimiter
            $files | Remove-Item -Force
        }
        $logMessage += "$now $env:COMPUTERNAME $messageToLog"
    }
    Write-Output $logMessage
    $logMessage | Out-File -FilePath (Join-Path -Path $logPath -ChildPath "$logName-$(Get-Date -Format "yyyyMMMdd").log") -Append
}
