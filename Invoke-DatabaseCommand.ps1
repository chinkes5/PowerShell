function Invoke-DatabaseCommand {
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = 'The SQL server to use', Mandatory = $true)][string]$ServerInstance,
        [Parameter(HelpMessage = 'The database to use', Mandatory = $true)][string]$Database,
        [Parameter(HelpMessage = 'Number of seconds before the queries time out')][int]$QueryTimeout = 1200,
        [Parameter(HelpMessage = 'A query to run directly', ParameterSetName = 'Query')][string]$Query = $null,
        [Parameter(HelpMessage = 'The full path to a SQL file to run', ParameterSetName = 'InputFile')][string]$InputFile = $null
    )

    if ([string]::IsNullOrEmpty($InputFile)) {
        Write-Information "Found a query!"
        $sqlParams = @{
            Query = $Query
        }
    }
    else { Write-Information "No query." }  
   
    if ([string]::IsNullOrEmpty($Query)) {
        Write-Information "Found input file!"
        $sqlParams = @{
            InputFile = $InputFile
        }
    }
    else { Write-Information "No input file." }
 
    if ($null -ne $sqlParams) {
        Write-Information "Adding the rest of the vaules"
        $sqlParams.Add("ServerInstance", $ServerInstance)
        $sqlParams.Add("Database", $Database)
        $sqlParams.Add("QueryTimeout", $QueryTimeout)
        $sqlParams.Add("Verbose", $true)
        $sqlParams.Add("OutputSqlErrors", $true)

        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-5.1#redirectable-output-streams
        # This is using parameter splatting and redirection, twice, to capture all output for evaluation
        return Invoke-SQLCMD @sqlParams 4>&1 2>&1
    }
    else {
        Write-Error "You must provide a query or an input file!"
    }
}
