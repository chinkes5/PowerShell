##############################################################################
# Script to manage JAVA keystores and certificates, especially for Wildfly.  #
# This script scans for JAVA keystores, lists their aliases, and allows      #
# the user to delete, import, or manage certificates within those keystores. #
##############################################################################

# We want to ignore the generic CA aliases, so here's a list of common ones, or at least the first 5 characters of them.
# This is to avoid deleting or managing generic CA entries that are not user-specific.
$genericCAAliases = @(
    'actal', 'addtr', 'affir', 'aolro', 'balti', 'buypa',
    'camer', 'certp', 'certu', 'chung', 'comod', 'deuts',
    'digic', 'dtrus', 'entru', 'equif', 'geotr', 'globa',
    'godad', 'gtecy', 'ident', 'keyne', 'letse', 'luxtr',
    'quova', 'secom', 'secur', 'soner', 'starf', 'swiss',
    'thawt', 'ttele', 'usert', 'utnus', 'veris', 'xramp'
)

function Unprotect-RSISecret {
    <#
    .SYNOPSIS
    Reverse XOR operation to reveal original text from a protected RSI secret.
    .DESCRIPTION
    This function takes the protected text string and a key as input, and performs a reverse XOR operation to return the original text.
    .PARAMETER ProtectedText
    The base64 encoded string from the protected RSI secret.
    .PARAMETER Key
    The key used to protect the secret.
    .EXAMPLE
    Unprotect-RSISecret -ProtectedText "bXlzdHJpbmc=" -Key "mykey"
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string]$ProtectedText,
        [Parameter()][string]$Key
    )

    try {
        # Convert from Base64
        $textBytes = [Convert]::FromBase64String($ProtectedText)
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)

        # Reverse XOR operation
        for ($i = 0; $i -lt $textBytes.Length; $i++) {
            $textBytes[$i] = $textBytes[$i] -bxor $keyBytes[$i % $keyBytes.Length]
        }

        return [System.Text.Encoding]::UTF8.GetString($textBytes)
    }
    catch {
        Write-Error "Failed to unprotect secret: $_"
        return $null
    }
}

function Invoke-LocalCertificateSelectionDialog {
    <#
.SYNOPSIS
    Presents a dialog to select a local certificate from the local machine store.

.DESCRIPTION
    This function lists all valid certificates in the local machine's "My" store that match a specified subject filter and have not expired.
    The user can select a certificate from the list, and the selected certificate is returned.

.PARAMETER SubjectFilter
    The subject filter to use when listing certificates. Defaults to include the computer name.

.EXAMPLE
    $cert = Invoke-LocalCertificateSelectionDialog
    $cert = Invoke-LocalCertificateSelectionDialog -SubjectFilter "*example*"

#>
    param (
        [string]$SubjectFilter = "*$($env:COMPUTERNAME)*" # Default filter
    )
    $candidateCerts = Get-ChildItem -Path Cert:\LocalMachine\My |
    Where-Object {
        $_.Subject -like $SubjectFilter -and
        $_.NotAfter -gt (Get-Date) # Ensure it's not expired
    } |
    Sort-Object -Property NotAfter -Descending

    if (-not $candidateCerts) {
        Write-Warning "No valid certificates found matching filter '$SubjectFilter'."
        return $null
    }

    Write-Host "Select a local certificate to use:"
    for ($i = 0; $i -lt $candidateCerts.Count; $i++) {
        $cert = $candidateCerts[$i]
        Write-Host ("[{0}] Subject: {1}`n     Expires: {2}`n     Thumbprint: {3}" -f ($i + 1), $cert.Subject, $cert.NotAfter.ToString("yyyy-MM-dd"), $cert.Thumbprint)
    }

    $choice = Read-Host "`nEnter the number of the certificate"
    if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $candidateCerts.Count) {
        Write-Error "Invalid selection. No certificate chosen."
        return $null
    }
    $selected = $candidateCerts[[int]$choice - 1]
    Write-Host "You selected: $($selected.Subject) (Expires: $($selected.NotAfter.ToString("yyyy-MM-dd")))"
    return $selected
}

function Export-LocalCertToTempPfx {
    <#
    .SYNOPSIS
    Exports a local certificate to a temporary PFX file.

    .DESCRIPTION
    This function exports a given X509Certificate2 object, which includes a private key, to a temporary PFX file in the system's temporary directory.
    The password for the PFX file is provided as a plain text string for compatibility with keytool.

    .PARAMETER Certificate
    The X509Certificate2 object representing the certificate to be exported.

    .PARAMETER Password
    The plain text password to secure the exported PFX file.

    .OUTPUTS
    System.String - The file path to the temporary PFX file.

    .EXAMPLE
    $cert = Get-Item Cert:\LocalMachine\My\1234567890ABCDEF1234567890ABCDEF12345678
    $tempPfxPath = Export-LocalCertToTempPfx -Certificate $cert -Password "yourPassword"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    if (-not $Certificate.HasPrivateKey) {
        Write-Error "Selected certificate '$($Certificate.Subject)' does not have a private key. Cannot export to PFX."
        return $null
    }
    $tempPfxFileName = "$([System.IO.Path]::GetRandomFileName()).pfx"
    $tempPfxPath = Join-Path $env:TEMP $tempPfxFileName
    try {
        Export-PfxCertificate -Cert $Certificate -FilePath $tempPfxPath -Password $securePassword -Force
        Write-Verbose "Exported local certificate to temporary PFX: $tempPfxPath"
        return $tempPfxPath
    }
    catch {
        Write-Error "Failed to export certificate '$($Certificate.Subject)' to PFX: $($_.Exception.Message)"
        if (Test-Path $tempPfxPath) { Remove-Item $tempPfxPath -Force -ErrorAction SilentlyContinue }
        return $null
    }
}

function Import-PfxIntoKeystore {
    <#
    .SYNOPSIS
    Imports a certificate entry from a PFX file into a Java KeyStore.

    .DESCRIPTION
    This function imports a certificate entry from a PFX file into a Java KeyStore.
    The PFX file is expected to contain a single private key and associated certificates.
    The alias name for the new entry in the destination KeyStore is prompted for, if not provided.
    The destination KeyStore type is determined by the extension of the destination path.
    If the destination KeyStore does not exist, it will be created.

    .PARAMETER SourcePfxPath
    The path to the PFX file containing the certificate to be imported.

    .PARAMETER SourcePfxPassword
    The plain text password to use for the source PFX file.

    .PARAMETER TargetKeystorePath
    The path to the Java KeyStore to add the certificate to.

    .PARAMETER TargetKeystorePassword
    The plain text password to use for the destination KeyStore.

    .PARAMETER TargetKeystoreType
    The type of destination KeyStore. Valid values are 'JKS' or 'PKCS12'.

    .OUTPUTS
    System.Boolean - True if the import was successful, False otherwise.

    .EXAMPLE
    Import-PfxIntoKeystore -SourcePfxPath "C:\Path\To\cert.pfx" -SourcePfxPassword "yourPassword" -TargetKeystorePath "C:\Path\To\keystore.jks" -TargetKeystorePassword "yourPassword" -TargetKeystoreType "JKS"
    #>
    param (
        [Parameter(Mandatory = $true)][string]$SourcePfxPath,
        [Parameter(Mandatory = $true)][string]$SourcePfxPassword,
        [Parameter(Mandatory = $true)][string]$TargetKeystorePath,
        [Parameter(Mandatory = $true)][string]$TargetKeystorePassword,
        [Parameter(Mandatory = $true)][ValidateSet('JKS', 'PKCS12')][string]$TargetKeystoreType
    )

    Write-Host "Attempting to import from PFX: '$SourcePfxPath' into Keystore: '$TargetKeystorePath'"
    Write-Host "Listing aliases in PFX '$SourcePfxPath'..."
    # Ensure $SourcePfxPassword is used for the source PFX
    $pfxAliasesRaw = keytool -list -v -keystore $SourcePfxPath -storepass $SourcePfxPassword -storetype PKCS12

    if ($LASTEXITCODE -ne 0 -or ($pfxAliasesRaw -join "`n") -like "*error*") {
        Write-Error "Failed to list aliases from PFX '$SourcePfxPath'. Keytool output:`n$($pfxAliasesRaw -join "`n")"
        return $false # Indicate failure
    }

    $pfxAliasNames = $pfxAliasesRaw | Where-Object { $_ -match 'Alias name:\s*(.+)' } | ForEach-Object { $Matches[1].Trim() }

    if (-not $pfxAliasNames) {
        Write-Error "No aliases found in PFX '$SourcePfxPath'."
        return $false
    }

    $sourceAliasForImport = $null
    if ($pfxAliasNames.Count -eq 1) {
        $sourceAliasForImport = $pfxAliasNames
        Write-Host "Found single alias in PFX: '$sourceAliasForImport'"
    }
    else {
        Write-Host "Multiple aliases found in PFX. Please select one to import:"
        for ($j = 0; $j -lt $pfxAliasNames.Count; $j++) {
            Write-Host "[$j] $($pfxAliasNames[$j])"
        }
        $pfxSelection = Read-Host "`nEnter the number of the PFX alias to import"
        if ($pfxSelection -match '^\d+$' -and [int]$pfxSelection -ge 0 -and [int]$pfxSelection -lt $pfxAliasNames.Count) {
            $sourceAliasForImport = $pfxAliasNames[[int]$pfxSelection]
        }
        else {
            Write-Error "Invalid PFX alias selection. Aborting add."
            return $false
        }
    }

    if ($sourceAliasForImport) {
        Write-Output "`nEnter the alias name for the new entry in '$TargetKeystorePath' (default: '$sourceAliasForImport')"
        $destinationAliasForImport = Read-Host "This should be the FDQN of the server"
        if ([string]::IsNullOrWhiteSpace($destinationAliasForImport)) {
            $destinationAliasForImport = $sourceAliasForImport
        }

        Write-Host "Importing alias '$sourceAliasForImport' from '$SourcePfxPath' as '$destinationAliasForImport' into '$TargetKeystorePath'..."
        Write-Verbose "Using destination store type: $TargetKeystoreType for $TargetKeystorePath"
        keytool -importkeystore -srckeystore $SourcePfxPath -srcstoretype PKCS12 -srcstorepass $SourcePfxPassword -srcalias $sourceAliasForImport -destkeystore $TargetKeystorePath -deststoretype $TargetKeystoreType -deststorepass $TargetKeystorePassword -destalias $destinationAliasForImport -noprompt
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully imported certificate." -ForegroundColor Green
            return $true # Indicate success
        }
        else {
            Write-Error "Failed to import certificate. Keytool exit code: $LASTEXITCODE. Check for error messages above from keytool."
            return $false
        }
    }
    return $false # Should not be reached if $sourceAliasForImport was valid
}


function Import-CerIntoKeystore {
    <#
    .SYNOPSIS
    Imports a CER file into a Java KeyStore.

    .DESCRIPTION
    This function imports a CER file into a Java KeyStore.
    The destination KeyStore type is determined by the extension of the destination path.
    If the destination KeyStore does not exist, it will be created.

    .PARAMETER SourceCerPath
    The path to the CER file containing the certificate to be imported.

    .PARAMETER TargetKeystorePath
    The path to the Java KeyStore to add the certificate to.

    .PARAMETER TargetKeystorePassword
    The plain text password to use for the destination KeyStore.

    .PARAMETER TargetKeystoreType
    The type of destination KeyStore. Valid values are 'JKS' or 'PKCS12'.

    .OUTPUTS
    System.Boolean - True if the import was successful, False otherwise.

    .EXAMPLE
    Import-CerIntoKeystore -SourceCerPath "C:\Path\To\cert.cer" -TargetKeystorePath "C:\Path\To\keystore.jks" -TargetKeystorePassword "yourPassword" -TargetKeystoreType "JKS"
    #>
    param (
        [Parameter(Mandatory = $true)][string]$SourceCerPath,
        [Parameter(Mandatory = $true)][string]$TargetKeystorePath,
        [Parameter(Mandatory = $true)][string]$TargetKeystorePassword,
        [Parameter(Mandatory = $true)][ValidateSet('JKS', 'PKCS12')][string]$TargetKeystoreType
    )

    if (-not (Test-Path $SourceCerPath)) {
        Write-Error "CER file not found: '$SourceCerPath'"
        return $false
    }

    # Prompt for alias
    Write-Output "`nEnter the alias name for the new entry in '$TargetKeystorePath'"
    $destinationAlias = Read-Host "This should be the FDQN of the server"

    if ([string]::IsNullOrWhiteSpace($destinationAlias)) {
        Write-Error "No alias provided. Aborting import."
        return $false
    }

    Write-Host "Importing CER file '$SourceCerPath' as alias '$destinationAlias' into '$TargetKeystorePath'..."
    Write-Verbose "Using destination store type: $TargetKeystoreType for $TargetKeystorePath"

    # Import the certificate
    keytool -importcert -file $SourceCerPath -alias $destinationAlias -keystore $TargetKeystorePath -storepass $TargetKeystorePassword -storetype $TargetKeystoreType -noprompt

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully imported CER file as alias '$destinationAlias'." -ForegroundColor Green
        return $true
    }
    else {
        Write-Error "Failed to import CER file. Keytool exit code: $LASTEXITCODE. Check for error messages above from keytool."
        return $false
    }
}

# Decrypt the keystore password using a user-provided key.
# This allows secure storage of the password and avoids hardcoding sensitive values in the script.
$certPwdSecret = Read-Host "Enter the encrypted keystore password"
$certPwdKey = Read-Host "Enter the password key to decrypt the keystore password (e.g., 'Pass phrase for keystore')"
$certPwd = Unprotect-RSISecret -ProtectedText $certPwdSecret -Key $certPwdKey
if (-not $certPwd) {
    Write-Error "Failed to decrypt password. Aborting."
    exit 1
}

Write-Output "Getting a list of existing drive letters..."
$existingDrives = Get-PSDrive | Where-Object { $_.Provider.Name -eq 'FileSystem' } | Select-Object -ExpandProperty Name
Write-Output "Getting the list of drives..."
do {
    Write-Host "Drives found:`n$($existingDrives -join ', ')"

    $driveLetter = Read-Host "`nEnter the drive letter to scan"
    if ($existingDrives -contains $driveLetter.ToUpper()) {
        Write-Output "Using drive: $driveLetter"
        break
    }
    else {
        Write-Warning "Drive letter '$driveLetter' does not exist. Please enter a valid drive letter."
    }
} while ($existingDrives -notcontains $driveLetter.ToUpper())

# We scan both known locations (JAVA_HOME, JBOSS_HOME, Wildfly default) and the entire drive in the background.
# This ensures we quickly list likely keystores, while still finding any others that may exist elsewhere.
# Results from both are merged for the user to select from.
Write-Output "Starting background scan for keystores on drive $driveLetter..."
$scanJob = Start-Job -ScriptBlock {
    param($driveLetter)
    $cacerts = Get-ChildItem -Path "$driveLetter`:\" -Filter 'cacer*' -Recurse -File -ErrorAction SilentlyContinue
    $keystores = Get-ChildItem -Path "$driveLetter`:\" -Filter '*.jks' -Recurse -File -ErrorAction SilentlyContinue
    return @($cacerts + $keystores) | Select-Object FullName -Unique
} -ArgumentList $driveLetter

Write-Output "Checking known locations..."
$knownPaths = @()
if ($env:JAVA_HOME) { $knownPaths += Get-ChildItem -Path "$env:JAVA_HOME" -Filter '*.jks' -Recurse -File -ErrorAction SilentlyContinue }
if ($env:JBOSS_HOME) { $knownPaths += Get-ChildItem -Path "$env:JBOSS_HOME" -Filter '*.jks' -Recurse -File -ErrorAction SilentlyContinue }
$knownPaths += Get-ChildItem -Path "$driveLetter`:\Wildfly" -Filter '*.jks' -Recurse -File -ErrorAction SilentlyContinue

$wildflypath = $knownPaths | Select-Object FullName -Unique
if ($wildflypath.Count -eq 0) {
    Write-Host "No keystores found on drive $driveLetter." -ForegroundColor Red
    #exit 0 #not exiting in case user wants to create a new keystore
}

do {
    # Check if the background job is still running, notify the user either way
    if (Get-Job -Id $scanJob.Id | Where-Object { $_.State -eq 'Completed' }) {
        $jobResults = Receive-Job -Id $scanJob.Id
        $wildflypath = @($wildflypath + $jobResults) | Select-Object FullName -Unique
        Remove-Job -Id $scanJob.Id
        Write-Host "Full scan complete. Additional keystores have been added to the list." -ForegroundColor DarkGreen
    }
    else {
        Write-Host "Background scan is still running. More keystores may appear soon..." -ForegroundColor DarkYellow
    }

    Write-Host "Files found:"
    for ($i = 0; $i -lt $wildflypath.Count; $i++) {
        #TODO: Add a check for JAVA_HOME and JBOSS_HOME in case those variables are not set?
        switch -Wildcard ($wildflypath[$i].FullName) {
            "$env:JAVA_HOME*" { $status = "<-- JAVA Home***" }
            "$env:JBOSS_HOME\*" { $status = "<-- Wildfly Home***" }
            "$driveLetter`:\Wildfly\*" { $status = "<-- Wildfly Default Path***" }
            Default { $status = "" }
        }
        Write-Host ("[{0}] {1} " -f ($i + 1), $wildflypath[$i].FullName, $status) -NoNewline
        if ($status -ne '') { Write-Host ("$status") -ForegroundColor Cyan }
        else { Write-Host "" }
    }

    $isValid = $false
    $selection = Read-Host "`nEnter the number of the file to work on (1-$($wildflypath.Count)), 'new' to create a new keystore, 'refresh' to get revised file list, or 'exit' to quit"
    switch -Regex ($selection) {
        '^\d+$' {
            # Selection of a file, process it-
            if (($selection -notin 0..($wildflypath.Count)) -or ($wildflypath.Count -le 0)) {
                Write-Warning "No files found. Going back to menu."
                break
            }
            $path = $wildflypath[$selection - 1]
            $keepEditingThisKeystore = $true
            while ($keepEditingThisKeystore) {
                Write-Host "Currently managing keystore: $($path.FullName)" -ForegroundColor Cyan
                Write-Host "Fetching current aliases..."
                $aliasRawList = keytool -list -keystore $path.FullName -storepass $certPwd -noprompt

                if ($LASTEXITCODE -ne 0 -or ($aliasRawList -join "`n") -like "*error*") {
                    Write-Error "Error reading aliases from $($path.FullName). Keytool output:`n$($aliasRawList -join "`n")"
                    $keepEditingThisKeystore = $false # Can't proceed with this keystore
                    continue
                }

                $currentKeystoreAliases = $aliasRawList | ForEach-Object {
                    # Match the alias, date, and entry type and filter out generic CA aliases
                    if (($_ -match '^(.+?),\s+(\w+ \d{1,2}, \d{4}),\s+(.+?),?$') -and ($Matches[1].Substring(0, [System.Math]::Min(5, $Matches[1].Length)) -notin $genericCAAliases)) {
                        [PSCustomObject]@{
                            Alias     = $Matches[1].Trim()
                            Date      = $Matches[2]
                            EntryType = if ($Matches[3].Trim() -eq 'trustedCertEntry') { 'CER' } else { 'PFX' }
                        }
                    }
                } | Where-Object { $_ }

                if ($currentKeystoreAliases) {
                    if ($currentKeystoreAliases.Count) {
                        $aliasCount = $currentKeystoreAliases.Count
                    }
                    else {
                        $aliasCount = 1 # To avoid errors in the loop below if only one (non-generic) alias is present
                    }
                    Write-Host "Available aliases to manage/delete:"
                    for ($i = 0; $i -lt $aliasCount; $i++) {
                        $aliasEntry = $currentKeystoreAliases[$i]
                        Write-Output ("[{0}] Alias: {1}, Date: {2}, Type: {3}" -f ($i + 1), $aliasEntry.Alias, $aliasEntry.Date, $aliasEntry.EntryType)
                    }
                }
                else {
                    Write-Host "No non-generic aliases found in this keystore, or keystore is empty/new."
                }

                Write-Host "`nEnter # to delete, 'import' (PFX from path), 'local' (from this server's cert store), 'done' to finish working on keystore, or 'help' for more information." -ForegroundColor Yellow
                $action = Read-Host "Enter a command for this keystore"
                # Determine target keystore type once per interaction loop for the current keystore
                # This is based on the file extension or name and will be used when calling keytool so the right type is specified.
                $destStoreType = if ($path.Name -eq 'cacerts' -and $path.Extension -eq '') { 'JKS' } elseif ($path.Extension -eq '.jks') { 'JKS' } else { 'PKCS12' }

                switch -Regex ($action) {
                    '^\d+$' {
                        $selectedIndex = [int]$action - 1 # Convert to zero-based index
                        if (($selectedIndex -ge 0) -and ($selectedIndex -le $aliasCount)) {
                            $aliasToDelete = $currentKeystoreAliases[$selectedIndex]
                            Write-Host "Attempting to delete alias '$($aliasToDelete.Alias)' from '$($path.FullName)'..." -ForegroundColor Yellow
                            keytool -delete -alias $aliasToDelete.Alias -keystore $path.FullName -storepass $certPwd -noprompt
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "Successfully deleted alias '$($aliasToDelete.Alias)'." -ForegroundColor Green
                            }
                            else {
                                Write-Error "Failed to delete alias '$($aliasToDelete.Alias)'. Keytool exit code: $LASTEXITCODE. Check for error messages above from keytool."
                            }
                        }
                        else {
                            Write-Warning "Invalid selection number: $action. No alias deleted."
                        }
                        break
                    }
                    'import' {
                        Write-Host "Adding a new entry by importing a PFX or CER file..."
                        $pfxFilePath = Read-Host "Enter the full path to the certificate file to import"
                        if (Test-Path $pfxFilePath) {
                            if ($pfxFilePath -match '\.pfx$') {
                                Import-PfxIntoKeystore -SourcePfxPath $pfxFilePath -SourcePfxPassword $certPwd -TargetKeystorePath $path.FullName -TargetKeystorePassword $certPwd -TargetKeystoreType $destStoreType
                            }
                            elseif ($pfxFilePath -match '\.cer$') {
                                Import-CerIntoKeystore -SourceCerPath $pfxFilePath -TargetKeystorePath $path.FullName -TargetKeystorePassword $certPwd -TargetKeystoreType $destStoreType
                            }
                            else {
                                Write-Warning "Unsupported file type. Please provide a .pfx or .cer file."
                            }
                        }
                        else {
                            Write-Warning "PFX file not found: '$pfxFilePath'. No certificate added."
                        }
                        break
                    }
                    'local' {
                        Write-Host "Adding a new entry from a local certificate..."
                        $tempPfxToCleanup = $null
                        $localCert = Invoke-LocalCertificateSelectionDialog # This function will prompt for selection

                        if ($localCert) {
                            Write-Host "Using selected local certificate: $($localCert.Subject)"
                            # Export the selected local certificate to a temporary PFX file.
                            # This is necessary because keytool can only import from PFX files, not directly from the Windows certificate store.
                            # The temporary file is deleted after import to avoid leaving sensitive material on disk.
                            $tempPfxToCleanup = Export-LocalCertToTempPfx -Certificate $localCert -Password $certPwd
                            if ($tempPfxToCleanup -and (Test-Path $tempPfxToCleanup)) {
                                # Use the helper function to import the temporary PFX
                                Import-PfxIntoKeystore -SourcePfxPath $tempPfxToCleanup.FullName -SourcePfxPassword $certPwd -TargetKeystorePath $path.FullName -TargetKeystorePassword $certPwd -TargetKeystoreType $destStoreType
                            }
                            else {
                                Write-Warning "Failed to export local certificate to a temporary PFX. No certificate added."
                            }
                            # Cleanup temp PFX
                            if ($tempPfxToCleanup -and (Test-Path $tempPfxToCleanup)) {
                                Write-Verbose "Cleaning up temporary PFX: $tempPfxToCleanup"
                                Remove-Item $tempPfxToCleanup -Force -ErrorAction SilentlyContinue
                            }
                        }
                        break
                    }
                    'help' {
                        Write-Host "Actions:" -ForegroundColor Cyan
                        Write-Host "  # - Delete an alias by number. Enter the number of the alias you want to delete." -ForegroundColor Cyan
                        Write-Host "  import - Add a new entry by importing a PFX file. You will be prompted for the path to the PFX or CER file. The default password for the keystore will be used." -ForegroundColor Cyan
                        Write-Host "  local  - Add a new entry from a local certificate. You will be prompted to select a certificate from the local machine's certificate store." -ForegroundColor Cyan
                        Write-Host "  [Enter] - Finish editing this keystore" -ForegroundColor Cyan
                        break
                    }
                    'done' {
                        Write-Host "Finished editing '$($path.FullName)'."
                        $keepEditingThisKeystore = $false
                    }
                    Default {
                        Write-Warning "Invalid input: '$action'. No action taken. Please enter a number, 'import', 'local', or press Enter to finish."
                    }
                } # end switch
            } # end while ($keepEditingThisKeystore)
            break
        }
        '^new$' {
            Write-Host "Creating a new keystore..."
            $newKeystorePath = Read-Host "Enter the full path for the new keystore (e.g., C:\path\to\newkeystore.jks)"
            if (Test-Path $newKeystorePath) {
                Write-Host "A file already exists at $newKeystorePath. Please choose a different path." -ForegroundColor Red
                $isValid = $false
            }
            else {
                $newKeystoreDir = [System.IO.Path]::GetDirectoryName($newKeystorePath)
                if (-not (Test-Path $newKeystoreDir)) {
                    Write-Host "Creating directory: $newKeystoreDir"
                    New-Item -ItemType Directory -Path $newKeystoreDir -Force | Out-Null
                }
                Write-Host "Creating new keystore: $newKeystorePath"
                $localCert = Invoke-LocalCertificateSelectionDialog
                $tempPfxToCleanup = Export-LocalCertToTempPfx -Certificate $localCert -Password $certPwd

                # Set the type of store based on the name provided
                $destStoreType = if ($newKeystorePath.Name -eq 'cacerts' -and $newKeystorePath.Extension -eq '') { 'JKS' } elseif ($newKeystorePath.Extension -eq '.jks') { 'JKS' } else { 'PKCS12' }

                Write-Output "Creating a new keystore using the active certificate..."
                if ($tempPfxToCleanup -and (Test-Path $tempPfxToCleanup)) {
                    # Use the helper function to import the temporary PFX
                    Import-PfxIntoKeystore -SourcePfxPath $tempPfxToCleanup.FullName -SourcePfxPassword $certPwd -TargetKeystorePath $newKeystorePath -TargetKeystorePassword $certPwd -TargetKeystoreType $destStoreType
                }
                else {
                    Write-Warning "Failed to export local certificate to a temporary PFX. No certificate added."
                }

                # Cleanup temp PFX
                if ($tempPfxToCleanup -and (Test-Path $tempPfxToCleanup)) {
                    Write-Verbose "Cleaning up temporary PFX: $tempPfxToCleanup"
                    Remove-Item $tempPfxToCleanup -Force -ErrorAction SilentlyContinue
                }
            }
            break
        }
        '^exit$' {
            Write-Host "Exiting script." -ForegroundColor Red
            $isValid = $true
        }
        '^refresh$' {
            Write-Output "Checking background file scan..."
        }
        Default {
            Write-Host "Invalid selection. Try again." -ForegroundColor Yellow
        }
    }
} until ($isValid)

Write-Output "Script finished."
