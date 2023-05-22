function new-passwordAPI() {
    #api is at https://developer.wordnik.com/docs#!/words/getRandomWord with explaination of the options
    # could also use https://github.com/nightblade9/simple-english-dictionary to get own dictionary

    <#
.SYNOPSIS
    Makes passwords with two random words, a number, and a symbol in a random order
.DESCRIPTION
    Uses Wordnik API to get words between 4 and 8 letters. Use -LongWords switch if you want longer words. 
.EXAMPLE
    New-Password -Verbose
.EXAMPLE
    New-Password -longWords
#>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = 'Normally the words are 4-6 letters, using this flag gets you 6-8 letter words')][switch]$longWords,
        [Parameter(HelpMessage = 'Using this flag gets you three words instead of two')][switch]$extraLongWords,
        [Parameter(HelpMessage = 'Wordnik API key', Mandatory = $true)][string]$apiKey
    )
    Process {
        
        if ($longWords) {
            $minLength = 6
            $maxLength = 8
        }
        else {
            $minLength = 4
            $maxLength = 6
        }
        $wordURL = "https://api.wordnik.com/v4/words.json/randomWord?hasDictionaryDef=true&maxCorpusCount=-1&minDictionaryCount=1&maxDictionaryCount=-1&minLength=$minLength&maxLength=$maxLength&api_key=$apiKey"
        $symbols = @("!", "@", "#", "$", "%", "^", "&", "_", "-")
        $number = get-random -minimum 11 -maximum 99
        try {
            Write-Verbose "Getting random word from Wordnik..."
            $letter1 = (Invoke-RestMethod -Uri $wordURL -Method GET).word
            Write-Verbose "Word 1- $letter1"
            $letter2 = (Invoke-RestMethod -Uri $wordURL -Method GET).word
            Write-Verbose "Word 2- $letter2"
            if ($extraLongWords) {
                $letter3 = (Invoke-RestMethod -Uri $wordURL -Method GET).word
                Write-Verbose "Word 3- $letter3"
                $passwordArray = @($number.ToString(), $letter1, $letter2, $letter3, $symbols[(Get-Random -Maximum ($symbols.Count))])
            }
            else {
                $passwordArray = @($number.ToString(), $letter1, $letter2, $symbols[(Get-Random -Maximum ($symbols.Count))])
            }

            $password = $passwordArray | Sort-Object { Get-Random }
            return $password -join ""
        }
        catch {
            Write-Error "Can't make a password - $($Error[0].Exception.Message)"
        }
    }
}
