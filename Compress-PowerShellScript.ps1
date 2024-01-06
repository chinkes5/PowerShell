function Compress-PowerShellScript {
    <#
.SYNOPSIS
Compresses PowerShell scripts by swapping the variable names for alphabetic characters as well as the shortest cmdlet aliases
.DESCRIPTION
You can input one or more files to compress. If no files are specified, all files in the current directory will be compressed and saved to the output path. At the end of each file a small report of the variable changes and the number of characters will be written to the console.
There is a limit of 26 variables in the script, as I'm replacing with a to z. After that, the file is skipped.
.EXAMPLE
$files = Get-ChildItem -Path "C:\Scripts\*.ps1"
$files | Compress-PowerShellScript -OutputPath "C:\MinifiedScripts"

This will minify all the PowerShell scripts in the C:\Scripts folder and save them in the C:\MinifiedScripts folder

.LINK
https://github.com/StartAutomating/PSMinifier
.LINK
https://github.com/ikarstein/minifyPS/tree/master
#>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'The path to save the minified PowerShell scripts to')][ValidateNotNullOrEmpty()][string]$OutputPath,
        [Parameter(Mandatory = $true, HelpMessage = 'Array of PowerShell script files to minify')][System.IO.FileInfo[]]$ScriptFiles
    )

    begin {
        function private:Get-ShortestAlias {
            param ([string]$cmdletName)
            $aliases = Get-Alias | Where-Object { $_.Definition -eq $cmdletName }
            if (-not $aliases) {
                return $cmdletName
            }
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $shortestAlias = $aliases | Sort-Object Name.Length | Select-Object -First 1
            }
            else {
                $shortestAlias = $aliases | Sort-Object Name.Length -Top 1
            }
            return $shortestAlias.Name
        }

        if (-Not (Test-Path -Path $OutputPath -PathType Container)) {
            throw "Output path does not exist!"
        }

        # Regex to match PowerShell variables
        $VARregex = '(?<!`)\$([a-zA-Z0-9]+)'
        # Regext to match parameter declarations
        $PARAMregex = '^\s*(?<parameter>\[Parameter\s*\().*\$(?<variable>[a-zA-Z0-9]+)'
        # Regex to match PowerShell cmdlets
        $CMDregex = '[a-zA-Z0-9_]+-[a-zA-Z0-9_]+'
        # Regex to match comments
        $COMregex = '^(?<!<)#(?!>)'
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
        Write-Verbose "Given $($ScriptFiles.Count) files..."
        :fileLoop foreach ($file in $ScriptFiles) {
            if ($file.Extension -ne ".ps1") {
                Write-Verbose "Not a PowerShell script, skipping $($file.Name)..."
                continue
            }
            Write-Verbose "Reading $($file.Name)..."
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
                    $PARAMregex {
                        Write-Verbose "Found parameter declaration to alias..."
                        $line = $line.Replace("[Parameter(", "[Alias('$($matches.variable)')][Parameter(")
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
                                        Write-Error "Too many variables to swap out! We're at $([char]$ascii) in $($file.Name). Skipping this file..."
                                        continue fileLoop
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
 
            $minContent | Out-File -FilePath (Join-Path $OutputPath -ChildPath "$($file.BaseName).min.ps1") -Encoding utf8 -Force

            # Report of savings and variable swaps
            Write-Output "New File: $($file.BaseName).min.ps1"
            Write-Output "Dictionary of variable swaps:"
            $varDict.GetEnumerator() | Sort-Object Value

            $originalCharCount = ($scriptContent | Measure-Object -Character).Characters
            $compressedCharCount = ($minContent | Measure-Object -Character).Characters
            $percentageSaved = [math]::Round((($originalCharCount - $compressedCharCount) / $originalCharCount) * 100)
            Write-Output "Old file char: $originalCharCount"
            Write-Output "New file char: $compressedCharCount"
            Write-Output "Percentage saved: $percentageSaved%"
        }
    }
}