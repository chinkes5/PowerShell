Import-Module Pester

Describe 'New-Password' {
    It 'Makes passwords with two random words, a number, and a symbol in a random order' {
        $password = new-passwordAPI -apiKey "xxxYYYaaa" -Verbose #<-- how to keep this secret?
        $password | Should -Be "1234" #<-- this isn't the best test for a password from this function. What would be better?
    }
}

Invoke-Pester