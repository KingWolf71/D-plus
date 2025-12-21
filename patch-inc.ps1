$file = "d:\OneDrive\WIP\Sources\Intense.2020\lj2\c2-inc-v17.pbi"
$content = Get-Content $file -Raw

$old = @"
Global Dim           gLocalNames.s(512, 64)  ; (funcId, paramOffset) -> local variable name

;- Macros
Macro          _ASMLineHelper1(view, uvar)
"@

$new = @"
Global Dim           gLocalNames.s(512, 64)  ; (funcId, paramOffset) -> local variable name

; V1.033.50: Dynamic function array capacity tracking
Global               gnFuncArrayCapacity.i = 512  ; Current capacity of function-indexed arrays

;- Macros
; V1.033.50: Ensure function-indexed arrays can hold funcId
Macro                EnsureFuncArrayCapacity(_funcId_)
   If _funcId_ >= gnFuncArrayCapacity
      gnFuncArrayCapacity = _funcId_ + 256  ; Grow by 256
      ReDim gFuncLocalArraySlots.i(gnFuncArrayCapacity, 15)
      ReDim gFuncNames.s(gnFuncArrayCapacity)
      ReDim gLocalNames.s(gnFuncArrayCapacity, 64)
   EndIf
EndMacro

Macro          _ASMLineHelper1(view, uvar)
"@

$content = $content -replace [regex]::Escape($old), $new
Set-Content $file -Value $content -NoNewline
Write-Host "Patched c2-inc-v17.pbi"
