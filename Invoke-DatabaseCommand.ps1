function Invoke-DatabaseCommand {
    <#
    .SYNOPSIS
    Single function to run a SQL command against a database, covering files or queries and some defaults
    .DESCRIPTION
    Nearly the same as the underlying invoke-sqlcmd function, but with some defaults and accommodations for files or queries. The real addition is capturing the output of the command with the redirected output stream from both verbose and error streams. You will want to put the output .ToString() as those streams return objects with different properties.
    .PARAMETER ServerInstance
    The SQL server to use
    .PARAMETER Database
    The database to use
    .PARAMETER QueryTimeout
    Number of seconds before the queries time out, default is 1200 seconds
    .PARAMETER Query
    A query to run directly, can't be used with InputFile
    .PARAMETER InputFile
    The full path to a SQL file to run, can't be used with Query    
    .EXAMPLE
    Invoke-DatabaseCommand -ServerInstance 'MyServer' -Database 'MyDB' -Query "SELECT * FROM MyTable"
    .EXAMPLE
    Invoke-DatabaseCommand -ServerInstance 'MyServer' -Database 'MyDB' -InputFile 'C:\MyFile.sql'
    .LINK
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-5.1#redirectable-output-streams
    #>

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

        return Invoke-SQLCMD @sqlParams 4>&1 2>&1
    }
    else {
        Write-Error "You must provide a query or an input file!"
    }
}
