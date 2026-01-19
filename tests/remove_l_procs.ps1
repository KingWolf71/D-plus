$filePath = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-pointers-v05.pbi'
$content = Get-Content $filePath -Raw

# Remove C2PLFETCH procedure
$old1 = 'Procedure               C2PLFETCH()
   ; V1.31.0: Pointer-only local FETCH - gLocal[] to gEvalStack[]
   vm_DebugFunctionName()

   gStorage(sp)\i = gStorage(gFrameBase + _AR()\i)\i
   gStorage(sp)\ptr = gStorage(gFrameBase + _AR()\i)\ptr
   gStorage(sp)\ptrtype = gStorage(gFrameBase + _AR()\i)\ptrtype

   sp + 1
   pc + 1
EndProcedure

'
$content = $content.Replace($old1, '; V1.034.21: Removed C2PLFETCH - now using unified C2PFETCH with j=1

')

# Remove C2PLSTORE procedure
$old2 = 'Procedure               C2PLSTORE()
   ; V1.31.0: Pointer-only local STORE - gEvalStack[] to gLocal[]
   vm_DebugFunctionName()
   sp - 1

   gStorage(gFrameBase + _AR()\i)\i = gStorage(sp)\i
   gStorage(gFrameBase + _AR()\i)\ptr = gStorage(sp)\ptr
   gStorage(gFrameBase + _AR()\i)\ptrtype = gStorage(sp)\ptrtype

   pc + 1
EndProcedure

'
$content = $content.Replace($old2, '; V1.034.21: Removed C2PLSTORE - now using unified C2PSTORE with j=1

')

# Remove C2PLMOV procedure
$old3 = 'Procedure               C2PLMOV()
   ; V1.31.0: Pointer-only local MOV (GL) - gVar[] to gLocal[]
   vm_DebugFunctionName()

   gStorage(gFrameBase + _AR()\i)\i = gVar( _AR()\j )\i
   gStorage(gFrameBase + _AR()\i)\ptr = gVar( _AR()\j )\ptr
   gStorage(gFrameBase + _AR()\i)\ptrtype = gVar( _AR()\j )\ptrtype

   pc + 1
EndProcedure

;- End Pointer-Only Opcodes'
$content = $content.Replace($old3, '; V1.034.21: Removed C2PLMOV - now using unified C2PMOV with n-field

;- End Pointer-Only Opcodes')

Set-Content $filePath -Value $content -NoNewline
Write-Output 'Done'
