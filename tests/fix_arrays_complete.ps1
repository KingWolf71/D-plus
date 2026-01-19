# Complete fix for c2-arrays-v06.pbi to use POINTER ARRAY ARCHITECTURE
# V1.035.0: *gVar(slot)\var(0) for globals, _LVAR(offset) for locals

$file = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi'
$content = Get-Content $file -Raw

# ============================================================================
# STEP 1: Update header comments and macros
# ============================================================================

# Update macro comments
$content = $content -replace ';   _GARR\(slot\)   - Global array at slot: gVar\(slot\)\\dta\\ar', ';   _GARR(slot)   - Global array at slot: *gVar(slot)\var(0)\dta\ar'
$content = $content -replace ';   _GARRSIZE\(slot\) - Global array size: gVar\(slot\)\\dta\\size', ';   _GARRSIZE(slot) - Global array size: *gVar(slot)\var(0)\dta\size'
$content = $content -replace ';   _LARR\(offset\) - Local array at offset: gLocal\(gLocalBase\+offset\)\\dta\\ar', ';   _LARR(offset) - Local array at offset: *gVar(gCurrentFuncSlot)\var(offset)\dta\ar'
$content = $content -replace ';   _LARRAY\(offset\) - Local slot calculation: gLocalBase \+ offset', ';   _LVAR(offset) - Local variable access: *gVar(gCurrentFuncSlot)\var(offset)'

# Update macros themselves
$content = $content -replace 'Macro _GARR\(slot\) : gVar\(slot\)\\dta\\ar : EndMacro', 'Macro _GARR(slot) : *gVar(slot)\var(0)\dta\ar : EndMacro'
$content = $content -replace 'Macro _GARRSIZE\(slot\) : gVar\(slot\)\\dta\\size : EndMacro', 'Macro _GARRSIZE(slot) : *gVar(slot)\var(0)\dta\size : EndMacro'
$content = $content -replace 'Macro _LARR\(offset\) : gLocal\(gLocalBase \+ \(offset\)\)\\dta\\ar : EndMacro', 'Macro _LARR(offset) : *gVar(gCurrentFuncSlot)\var(offset)\dta\ar : EndMacro'
$content = $content -replace 'Macro _LARRSIZE\(offset\) : gLocal\(gLocalBase \+ \(offset\)\)\\dta\\size : EndMacro', 'Macro _LARRSIZE(offset) : *gVar(gCurrentFuncSlot)\var(offset)\dta\size : EndMacro'

# ============================================================================
# STEP 2: Update bounds checking macros
# ============================================================================

$content = $content -replace 'If index < 0 Or index >= gVar\(arrIdx\)\\dta\\size', 'If index < 0 Or index >= *gVar(arrIdx)\var(0)\dta\size'
$content = $content -replace 'Debug "Array index out of bounds: " \+ Str\(index\) \+ " \(size: " \+ Str\(gVar\(arrIdx\)\\dta\\size\)', 'Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(*gVar(arrIdx)\var(0)\dta\size)'

$content = $content -replace 'If gLocal\(localSlot\)\\dta\\size = 0', 'If *gVar(gCurrentFuncSlot)\var(localSlot)\dta\size = 0'
$content = $content -replace 'Debug "Local array at slot " \+ Str\(localSlot\) \+ " not allocated', 'Debug "Local array at offset " + Str(localSlot) + " not allocated'
$content = $content -replace 'If index < 0 Or index >= gLocal\(localSlot\)\\dta\\size', 'If index < 0 Or index >= *gVar(gCurrentFuncSlot)\var(localSlot)\dta\size'
$content = $content -replace 'Debug "Local array index out of bounds: " \+ Str\(index\) \+ " \(size: " \+ Str\(gLocal\(localSlot\)\\dta\\size\)', 'Debug "Local array index out of bounds: " + Str(index) + " (size: " + Str(*gVar(gCurrentFuncSlot)\var(localSlot)\dta\size)'

# ============================================================================
# STEP 3: Update ptrtype macros
# ============================================================================

# _CopyPtrTypeFromGlobalArray
$content = $content -replace 'If gVar\(arrIdx\)\\dta\\ar\(index\)\\ptrtype', 'If *gVar(arrIdx)\var(0)\dta\ar(index)\ptrtype'
$content = $content -replace 'gEvalStack\(sp\)\\ptr = gVar\(arrIdx\)\\dta\\ar\(index\)\\ptr', 'gEvalStack(sp)\ptr = *gVar(arrIdx)\var(0)\dta\ar(index)\ptr'
$content = $content -replace 'gEvalStack\(sp\)\\ptrtype = gVar\(arrIdx\)\\dta\\ar\(index\)\\ptrtype', 'gEvalStack(sp)\ptrtype = *gVar(arrIdx)\var(0)\dta\ar(index)\ptrtype'

# _CopyPtrTypeFromLocalArray
$content = $content -replace 'If gLocal\(localSlot\)\\dta\\ar\(index\)\\ptrtype', 'If *gVar(gCurrentFuncSlot)\var(localSlot)\dta\ar(index)\ptrtype'
$content = $content -replace 'gEvalStack\(sp\)\\ptr = gLocal\(localSlot\)\\dta\\ar\(index\)\\ptr', 'gEvalStack(sp)\ptr = *gVar(gCurrentFuncSlot)\var(localSlot)\dta\ar(index)\ptr'
$content = $content -replace 'gEvalStack\(sp\)\\ptrtype = gLocal\(localSlot\)\\dta\\ar\(index\)\\ptrtype', 'gEvalStack(sp)\ptrtype = *gVar(gCurrentFuncSlot)\var(localSlot)\dta\ar(index)\ptrtype'

# _CopyPtrTypeToGlobalArray - local source
$content = $content -replace 'If gLocal\(srcSlot\)\\ptrtype', 'If *gVar(gCurrentFuncSlot)\var(srcSlot)\ptrtype'
$content = $content -replace 'gVar\(arrIdx\)\\dta\\ar\(index\)\\ptr = gLocal\(srcSlot\)\\ptr', '*gVar(arrIdx)\var(0)\dta\ar(index)\ptr = *gVar(gCurrentFuncSlot)\var(srcSlot)\ptr'
$content = $content -replace 'gVar\(arrIdx\)\\dta\\ar\(index\)\\ptrtype = gLocal\(srcSlot\)\\ptrtype', '*gVar(arrIdx)\var(0)\dta\ar(index)\ptrtype = *gVar(gCurrentFuncSlot)\var(srcSlot)\ptrtype'

# _CopyPtrTypeToGlobalArray - global source
$content = $content -replace 'If gVar\(srcSlot\)\\ptrtype', 'If *gVar(srcSlot)\var(0)\ptrtype'
$content = $content -replace 'gVar\(arrIdx\)\\dta\\ar\(index\)\\ptr = gVar\(srcSlot\)\\ptr', '*gVar(arrIdx)\var(0)\dta\ar(index)\ptr = *gVar(srcSlot)\var(0)\ptr'
$content = $content -replace 'gVar\(arrIdx\)\\dta\\ar\(index\)\\ptrtype = gVar\(srcSlot\)\\ptrtype', '*gVar(arrIdx)\var(0)\dta\ar(index)\ptrtype = *gVar(srcSlot)\var(0)\ptrtype'

# _CopyPtrTypeFromStack
$content = $content -replace 'gVar\(arrIdx\)\\dta\\ar\(index\)\\ptr = gEvalStack\(sp\)\\ptr', '*gVar(arrIdx)\var(0)\dta\ar(index)\ptr = gEvalStack(sp)\ptr'
$content = $content -replace 'gVar\(arrIdx\)\\dta\\ar\(index\)\\ptrtype = gEvalStack\(sp\)\\ptrtype', '*gVar(arrIdx)\var(0)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype'

# ============================================================================
# STEP 4: Replace all gLocal(...) with _LVAR(...)
# This handles: gLocal(slot)\field -> _LVAR(slot)\field
# ============================================================================

$content = $content -replace 'gLocal\(([^)]+)\)', '_LVAR($1)'

# ============================================================================
# STEP 5: Replace gVar(slot)\field patterns for simple variable access
# Pattern: gVar(something)\i or \f or \s or \ss or \ptr or \ptrtype
# ============================================================================

# Simple patterns first - gVar(varname)\field
$content = $content -replace 'gVar\(arrIdx\)\\dta', '*gVar(arrIdx)\var(0)\dta'
$content = $content -replace 'gVar\(valSlot\)\\([isfb])\b', '*gVar(valSlot)\var(0)\$1'
$content = $content -replace 'gVar\(valSlot\)\\ss', '*gVar(valSlot)\var(0)\ss'
$content = $content -replace 'gVar\(valSlot\)\\ptrtype', '*gVar(valSlot)\var(0)\ptrtype'
$content = $content -replace 'gVar\(valSlot\)\\ptr\b', '*gVar(valSlot)\var(0)\ptr'
$content = $content -replace 'gVar\(targetSlot\)\\([isfb])\b', '*gVar(targetSlot)\var(0)\$1'
$content = $content -replace 'gVar\(targetSlot\)\\ss', '*gVar(targetSlot)\var(0)\ss'
$content = $content -replace 'gVar\(actualSlot\)\\dta', '*gVar(actualSlot)\var(0)\dta'

# Patterns with _AR() - these have nested parentheses
# gVar(_AR()\ndx)\i -> *gVar(_AR()\ndx)\var(0)\i
$content = $content -replace 'gVar\(_AR\(\)\\ndx\)\\i', '*gVar(_AR()\ndx)\var(0)\i'
$content = $content -replace 'gVar\(_AR\(\)\\i\)\\dta', '*gVar(_AR()\i)\var(0)\dta'
$content = $content -replace 'gVar\(_AR\(\)\\i\)\\ptr', '*gVar(_AR()\i)\var(0)\ptr'
$content = $content -replace 'gVar\(_AR\(\)\\funcid\)\\([isfb])\b', '*gVar(_AR()\funcid)\var(0)\$1'
$content = $content -replace 'gVar\(_AR\(\)\\funcid\)\\ss', '*gVar(_AR()\funcid)\var(0)\ss'

# ============================================================================
# STEP 6: Fix ReDim and other special cases
# ============================================================================

$content = $content -replace 'ReDim gVar\(actualSlot\)\\dta\\ar', 'ReDim *gVar(actualSlot)\var(0)\dta\ar'

# ============================================================================
# STEP 7: Add architecture comment at top
# ============================================================================

$archComment = @"
; V1.035.0: POINTER ARRAY ARCHITECTURE
; - Globals: *gVar(slot)\var(0)\field
; - Locals: *gVar(gCurrentFuncSlot)\var(offset)\field (via _LVAR macro)
; - _LARRAY(offset) returns offset unchanged for backwards compat

"@

# Insert after the first comment block
$content = $content -replace '(; Array Operations Module\r?\n; Version: 06\r?\n)', "`$1`r`n$archComment"

Set-Content $file -Value $content -NoNewline -Encoding UTF8

Write-Host "Fix complete. Verifying..."

# Verify no bare gVar( or gLocal( remain (except in comments)
$remaining = Select-String -Path $file -Pattern '^\s*[^;].*[^*]gVar\(' | Measure-Object
Write-Host "Remaining bare gVar( in code: $($remaining.Count)"

$remainingLocal = Select-String -Path $file -Pattern '^\s*[^;].*gLocal\(' | Measure-Object
Write-Host "Remaining gLocal( in code: $($remainingLocal.Count)"
