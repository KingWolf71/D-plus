# PowerShell script to convert llStack linked list to gStack array
$file = "c2-vm-commands-v05.pb"
$content = Get-Content $file -Raw

# Replace llStack() with gStack(gStackDepth)
$content = $content -replace 'llStack\(\)', 'gStack(gStackDepth)'

# Fix specific patterns that need special handling
# AddElement(llStack()) -> gStackDepth increment with bounds check
$content = $content -replace 'AddElement\(\s*gStack\(gStackDepth\)\s*\)', 'ADDELEMENT_PLACEHOLDER'

# DeleteElement(llStack()) -> gStackDepth decrement
$content = $content -replace 'DeleteElement\(\s*gStack\(gStackDepth\)\s*\)', 'DELETEELEMENT_PLACEHOLDER'

# ListIndex(llStack()) -> gStackDepth
$content = $content -replace 'ListIndex\(gStack\(gStackDepth\)\)', 'gStackDepth'

# Write back
$content | Set-Content $file -NoNewline
Write-Host "Phase 1 complete - basic replacements done"
Write-Host "Manual fixes needed for ADDELEMENT_PLACEHOLDER and DELETEELEMENT_PLACEHOLDER"
