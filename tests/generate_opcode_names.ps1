# Generate InitOpcodeNames macro from enum definitions
# This parses the opcode Enumeration (starting with #ljUNUSED) in c2-inc-v17.pbi
# Uses Macro instead of Procedure to work inside DeclareModule

$incFile = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v17.pbi'
$content = Get-Content $incFile

$inEnum = $false
$enumCount = 0
$opcodes = @()

foreach ($line in $content) {
    # Count Enumeration blocks - we want the second one (opcodes, not holes)
    if ($line -match '^Enumeration') {
        $enumCount++
        if ($enumCount -eq 2) {
            $inEnum = $true
        }
        continue
    }

    # End of opcode enum
    if ($inEnum -and $line -match '^EndEnumeration') {
        break
    }

    # Parse enum entry - match #lj at start of line (with optional leading whitespace)
    if ($inEnum -and $line -match '^\s*#lj(\w+)') {
        $name = $Matches[1]
        $opcodes += [PSCustomObject]@{
            EnumName = "#lj$name"
            DisplayName = $name.ToUpper()
        }
    }
}

Write-Output "; V1.034.21: Inline opcode names - eliminates DataSection sync issues"
Write-Output "; This macro REPLACES the DataSection reading loop"
Write-Output "; Generated from enum - to add opcode, just add to Enumeration"
Write-Output "Macro _INIT_OPCODE_NAMES"
Write-Output "   ; Initialize opcode display names using enum constants directly"
Write-Output "   ; Names stay perfectly in sync with enum - no manual sync required"

foreach ($op in $opcodes) {
    Write-Output "   gszATR($($op.EnumName))\s = `"$($op.DisplayName)`""
}

Write-Output "EndMacro"
Write-Output ""
Write-Output "; Total opcodes: $($opcodes.Count)"
