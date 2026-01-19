# Patch D+AI for unified stack system
# V1.034.12: gLocal eliminated - locals stored in gEvalStack
# Run with: powershell -ExecutionPolicy Bypass -File patch-unified-stack.ps1

Write-Host "=== D+AI Unified Stack Patch v1.034.12 ===" -ForegroundColor Cyan

# ============================================================================
# PATCH c2-vm-V16.pb
# ============================================================================
Write-Host "Patching c2-vm-V16.pb..." -ForegroundColor Yellow

$file = "d:/OneDrive/WIP/Sources/Intense.2020/D+AI/c2-vm-V16.pb"
$content = Get-Content $file -Raw

# 1. Update stStack structure comments
$content = $content -replace 'localBase\.l\s+; V1\.31\.0: Base index in gLocal\[\] for this frame', 'frameBase.l              ; V1.034.12: Base index in gEvalStack[] for frame locals'
$content = $content -replace 'localCount\.l\s+; V1\.31\.0: Number of local slots in gLocal\[\] \(params \+ locals\)', 'localCount.l             ; V1.034.12: Number of local slots (params + locals)'
$content = $content -replace '; V1\.31\.0: ISOLATED VARIABLE SYSTEM', '; V1.034.12: UNIFIED STACK SYSTEM'
$content = $content -replace '; Locals stored in gLocal\[localBase to localBase\+localCount-1\]', '; Locals stored in gEvalStack[frameBase to frameBase+localCount-1]'
$content = $content -replace '; Evaluation stack in gEvalStack\[sp\] \(completely separate\)', '; Expression stack grows above locals at gEvalStack[sp]'

# 2. Remove gLocal array declaration - comment it out
$content = $content -replace '(Global Dim\s+gLocal\.stVT\(gLocalStack\)\s+; Local variables ONLY \(per-function frame\))', '; V1.034.12: REMOVED - $1'

# 3. Replace gLocalBase with gFrameBase in globals
$content = $content -replace 'Global\s+gLocalBase\.i\s+=\s+0\s+; Base index in gLocal\[\] for current frame', 'Global               gFrameBase.i     = 0                 ; V1.034.12: Base index in gEvalStack[] for frame locals'

# 4. Replace gLocalTop with gFrameTop
$content = $content -replace 'Global\s+gLocalTop\.i\s+=\s+0\s+; Current top of gLocal\[\] allocation', 'Global               gFrameTop.i      = 0                 ; V1.034.12: Top of allocated frames in gEvalStack[]'

# 5. Replace gLocalBase with gFrameBase everywhere (variable names)
$content = $content -replace '\bgLocalBase\b', 'gFrameBase'

# 6. Replace gLocalTop with gFrameTop everywhere
$content = $content -replace '\bgLocalTop\b', 'gFrameTop'

# 7. Replace gLocal( with gEvalStack( for accessing locals
$content = $content -replace '\bgLocal\(', 'gEvalStack('

# 8. Update stStack field access .localBase to .frameBase
$content = $content -replace '\\localBase\b', '\frameBase'

# 9. Update gLocalStack references to gMaxEvalStack for bounds
$content = $content -replace '\bgLocalStack\b', 'gMaxEvalStack'

Set-Content $file $content -NoNewline
Write-Host "  c2-vm-V16.pb patched" -ForegroundColor Green

# ============================================================================
# PATCH c2-vm-commands-v14.pb
# ============================================================================
Write-Host "Patching c2-vm-commands-v14.pb..." -ForegroundColor Yellow

$file = "d:/OneDrive/WIP/Sources/Intense.2020/D+AI/c2-vm-commands-v14.pb"
$content = Get-Content $file -Raw

# 1. Update _LOCAL macros to use gEvalStack
$content = $content -replace 'Macro _LOCALI\(offset\) : gLocal\(gLocalBase \+ \(offset\)\)\\i : EndMacro', 'Macro _LOCALI(offset) : gEvalStack(gFrameBase + (offset))\i : EndMacro'
$content = $content -replace 'Macro _LOCALF\(offset\) : gLocal\(gLocalBase \+ \(offset\)\)\\f : EndMacro', 'Macro _LOCALF(offset) : gEvalStack(gFrameBase + (offset))\f : EndMacro'
$content = $content -replace 'Macro _LOCALS\(offset\) : gLocal\(gLocalBase \+ \(offset\)\)\\ss : EndMacro', 'Macro _LOCALS(offset) : gEvalStack(gFrameBase + (offset))\ss : EndMacro'

# 2. Replace gLocalBase with gFrameBase
$content = $content -replace '\bgLocalBase\b', 'gFrameBase'

# 3. Replace gLocalTop with gFrameTop
$content = $content -replace '\bgLocalTop\b', 'gFrameTop'

# 4. Replace gLocal( with gEvalStack(
$content = $content -replace '\bgLocal\(', 'gEvalStack('

# 5. Replace gLocalStack with gMaxEvalStack
$content = $content -replace '\bgLocalStack\b', 'gMaxEvalStack'

# 6. Update stStack .localBase to .frameBase
$content = $content -replace '\\localBase\b', '\frameBase'

Set-Content $file $content -NoNewline
Write-Host "  c2-vm-commands-v14.pb patched" -ForegroundColor Green

# ============================================================================
# PATCH c2-arrays-v06.pbi
# ============================================================================
Write-Host "Patching c2-arrays-v06.pbi..." -ForegroundColor Yellow

$file = "d:/OneDrive/WIP/Sources/Intense.2020/D+AI/c2-arrays-v06.pbi"
$content = Get-Content $file -Raw

# 1. Update _LARR macros
$content = $content -replace 'Macro _LARR\(offset\) : gLocal\(gLocalBase \+ \(offset\)\)\\dta\\ar : EndMacro', 'Macro _LARR(offset) : gEvalStack(gFrameBase + (offset))\dta\ar : EndMacro'
$content = $content -replace 'Macro _LARRSIZE\(offset\) : gLocal\(gLocalBase \+ \(offset\)\)\\dta\\size : EndMacro', 'Macro _LARRSIZE(offset) : gEvalStack(gFrameBase + (offset))\dta\size : EndMacro'

# 2. Update _LARRAY macro comment
$content = $content -replace '_LARRAY\(offset\) - Local slot calculation: gLocalBase \+ offset', '_LARRAY(offset) - Local slot calculation: gFrameBase + offset'
$content = $content -replace '_LARR\(offset\) - Local array at offset: gLocal\(gLocalBase\+offset\)\\dta\\ar', '_LARR(offset) - Local array at offset: gEvalStack(gFrameBase+offset)\dta\ar'

# 3. Replace gLocalBase with gFrameBase
$content = $content -replace '\bgLocalBase\b', 'gFrameBase'

# 4. Replace gLocal( with gEvalStack(
$content = $content -replace '\bgLocal\(', 'gEvalStack('

# 5. Replace gLocalStack with gMaxEvalStack
$content = $content -replace '\bgLocalStack\b', 'gMaxEvalStack'

Set-Content $file $content -NoNewline
Write-Host "  c2-arrays-v06.pbi patched" -ForegroundColor Green

# ============================================================================
# Update version
# ============================================================================
Write-Host "Updating version..." -ForegroundColor Yellow
Set-Content "d:/OneDrive/WIP/Sources/Intense.2020/D+AI/_D+AI.ver" "1.034.12`n" -NoNewline
Write-Host "  Version updated to 1.034.12" -ForegroundColor Green

Write-Host ""
Write-Host "=== Patch Complete ===" -ForegroundColor Cyan
Write-Host "Run: pbcompiler c2-modules-V22.pb -e D+AI_test.exe" -ForegroundColor White
