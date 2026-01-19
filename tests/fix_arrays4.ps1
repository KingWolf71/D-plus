# Read file
$lines = Get-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi'
$newLines = @()

foreach ($line in $lines) {
    # Skip if line already has \var(0) after *gVar
    if ($line -notmatch '\*gVar.*\\var\(0\)') {
        # Match *gVar(...)\field pattern and insert \var(0)
        # This handles nested parentheses by finding balanced parens
        $newLine = $line

        # Pattern for *gVar followed by opening paren, we need to find matching close and what comes after
        if ($line -match '\*gVar\(') {
            # Find the position after *gVar(
            $match = [regex]::Match($line, '\*gVar\(')
            if ($match.Success) {
                $startPos = $match.Index + $match.Length
                $parenCount = 1
                $endPos = $startPos

                # Find matching closing paren
                while ($endPos -lt $line.Length -and $parenCount -gt 0) {
                    if ($line[$endPos] -eq '(') { $parenCount++ }
                    if ($line[$endPos] -eq ')') { $parenCount-- }
                    $endPos++
                }

                # Now check what comes after the closing paren
                if ($endPos -lt $line.Length) {
                    $afterParen = $line.Substring($endPos)
                    # If it starts with \i, \s, \f, \b, \dta, \ptrtype, \ptr - insert \var(0)
                    if ($afterParen -match '^\\([isfb]|dta|ptrtype|ptr\b)') {
                        $before = $line.Substring(0, $endPos)
                        $after = $afterParen
                        $newLine = $before + '\var(0)' + $after
                    }
                }
            }
        }
        $newLines += $newLine
    } else {
        $newLines += $line
    }
}

$newLines -join "`r`n" | Set-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi' -NoNewline

Write-Host "Done"
