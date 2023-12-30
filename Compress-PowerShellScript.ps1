function Compress-PowerShellScript {
<#
.SYNOPSIS
Compresses PowerShell scripts by swapping the variable names for alphabetic characters as well as the shortest cmdlet aliases
.DESCRIPTION
You can input one or more files to compress. If no files are specified, all files in the current directory will be compressed and saved to the output path. At the end of each file a small report of the variable changes and the number of characters will be written to the console.
.EXAMPLE
$files = Get-ChildItem -Path "C:\Scripts\*.ps1"
$files | Compress-PowerShellScript -OutputPath "C:\MinifiedScripts"

This will minify all the PowerShell scripts in the C:\Scripts folder and save them in the C:\MinifiedScripts folder
#>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'The path to save the minified PowerShell scripts')]
        [ValidateNotNullOrEmpty()][System.IO.Path]$OutputPath,
        [Parameter(Mandatory = $true, HelpMessage = 'The PowerShell scripts to minify')][System.IO.FileInfo[]]$ScriptFiles
    )

    begin {
        function private:Get-ShortestAlias {
            param ([string]$cmdletName)
            $aliases = Get-Alias | Where-Object { $_.Definition -eq $cmdletName }
            if (-not $aliases) {
                return $cmdletName
            }
            $shortestAlias = $aliases | Sort-Object Name.Length -First 1
            return $shortestAlias.Name
        }

        # Regex to match PowerShell variables
        $VARregex = '\$([a-zA-Z0-9_]+)'
        # Regex to match PowerShell cmdlets
        $CMDregex = '[a-zA-Z0-9_]+-[a-zA-Z0-9_]+'
        # Regex to match comments
        $COMregex = '#.*$'
        # Regex to match blank or whitespace
        $BLANKregex = '^\s*$'
        # Array of variable name to ignore 'cause they are default or built-in
        $VARtoAllow = @(
            "true"
            "false"
            "error"
            "matches"
            "psitem"
            "args"
        )
    }

    process {
        foreach ($file in $ScriptFiles) {
            # Read the PowerShell file
            $scriptContent = Get-Content -Path $file.FullName

            # Dictionary to store the new names
            $varDict = @{}

            # The new variable names will start from ASCII value of 'a'
            $ascii = 97
 
            # Process each line of the script
            $minContent = New-Object System.Collections.ArrayList
            ForEach ($line in $scriptContent) {
                switch -Regex ($line) {
                    $CMDregex {
                        Write-Verbose "Found a cmdlet to swap out..."
                        $matches = [regex]::Matches($line, $CMDregex)
                        foreach ($match in $matches) {
                            $cmdletName = $match.Value
                            $shortestAlias = Get-ShortestAlias $cmdletName
                            Write-Verbose "Swapping '$cmdletName' for '$shortestAlias'..."
                            $line = $line.Replace($cmdletName, $shortestAlias)
                        }
                    }
                    $VARregex {
                        Write-Verbose "Found variable to swap out..."
                        $matches = [regex]::Matches($line, $VARregex)
                        foreach ($match in $matches) {
                            $varName = $match.Groups[1].Value
                            if ($VARtoAllow -notcontains $varName) {
                                if (-not $varDict.ContainsKey($varName)) {
                                    $varDict[$varName] = "`$" + [char]$ascii
                                    $ascii++
                                    if ($ascii -gt (97 + 26)) {
                                        throw "Too many variables to swap out! We're at $([char]$ascii)."
                                    }
                                }
                                Write-Verbose "Swapping `$$varName for $($varDict[$varName])..."
                                $line = $line.Replace("`$$varName", $varDict[$varName])
                            }
                        }
                    }
                    $COMregex {
                        $line = $null
                    }
                    $BLANKregex {
                        $line = $null
                    }
                    default {
                        # what would the default be? What else would I care about?
                    }
                }
                if ($null -ne $line) {
                    $minContent.Add($line.Trim()) | Out-Null
                }
            }
 
            $minContent | Out-File -FilePath (Join-Path $OutputPath -ChildPath "$($file.BaseName).min.ps1") -Encoding utf8

            # Report of savings and variable swaps
            Write-Output "Dictionary of variable swaps:"
            $varDict.GetEnumerator() | Sort-Object Value

            $originalCharCount = ($scriptContent | Measure-Object -Character).Characters
            $compressedCharCount = ($minContent | Measure-Object -Character).Characters
            $percentageSaved = (($originalCharCount - $compressedCharCount) / $originalCharCount) * 100
            Write-Output "Old file char: $originalCharCount"
            Write-Output "New file char: $compressedCharCount"
            Write-Output "Percentage saved: $percentageSaved%"
        }
    }
}