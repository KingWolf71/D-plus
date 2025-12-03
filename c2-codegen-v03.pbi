; -- lexical parser to VM for a simplified C Language
; -- lexical parser to VM for a simplified C Language
; Tested in UTF8
; PBx64 v6.20
;
; Based on  https://rosettacode.org/wiki/Compiler/lexical_analyzer
; And
; https://rosettacode.org/wiki/Compiler/syntax_analyzer
; Distribute and use freely
;
; Kingwolf71 May/2025
;
;
; Code Generator
;- Procedures for generating VM bytecode from AST

   Declare              CodeGenerator( *x.stTree, *link.stTree = 0 )

   Procedure            hole()
      gHoles + 1

      AddElement( llHoles() )
      llHoles()\location   = llObjects()
      llHoles()\mode       = #C2HOLE_START
      llHoles()\id         = gHoles
      
      ProcedureReturn gHoles
   EndProcedure
   
   Procedure            fix( id, dst = -1 )

      AddElement( llHoles() )

      If dst = -1
         llHoles()\mode = #C2HOLE_DEFAULT
         llHoles()\id = id
         llHoles()\location = llObjects()
      Else                                   ; Used by blind JMP
         llHoles()\mode = #C2HOLE_BLIND
         LastElement( llObjects() )              ; Move to last element (JMP instruction)
         llHoles()\location = llObjects()        ; Save pointer to current element
         llHoles()\src = dst
      EndIf

   EndProcedure
    
   ; Helper: Check if variable should use local opcodes (LocalVars array)
   ; Returns true for both parameters and local variables in functions
   Procedure.b          IsLocalVar(varIndex.i)
      If varIndex < 0 Or varIndex >= gnLastVariable
         ProcedureReturn #False
      EndIf

      ; Parameters use LocalVars array
      If gVarMeta(varIndex)\flags & #C2FLAG_PARAM
         ProcedureReturn #True
      EndIf

      ; Non-parameter locals: check if name is mangled with function name OR synthetic ($temp)
      If gCurrentFunctionName <> ""
         If LCase(Left(gVarMeta(varIndex)\name, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
            ProcedureReturn #True
         EndIf
         ; Synthetic temporaries (starting with $) are also local when inside a function
         ; V1.022.28: UNLESS paramOffset = -1 (forced global for slot-only optimization)
         If Left(gVarMeta(varIndex)\name, 1) = "$"
            If gVarMeta(varIndex)\paramOffset >= 0
               ProcedureReturn #True
            EndIf
         EndIf
      EndIf

      ProcedureReturn #False
   EndProcedure

   ; V1.023.0: Helper to mark variable for preloading when assigned from constant
   ; This copies constant values to the destination's gVarMeta for template building
   Procedure            MarkPreloadable(srcSlot.i, dstSlot.i)
      ; Only mark if source is a constant and destination not already marked
      If (gVarMeta(srcSlot)\flags & #C2FLAG_CONST) And Not (gVarMeta(dstSlot)\flags & #C2FLAG_PRELOAD)
         ; Copy constant value to destination's gVarMeta
         If gVarMeta(srcSlot)\flags & #C2FLAG_INT
            gVarMeta(dstSlot)\valueInt = gVarMeta(srcSlot)\valueInt
         ElseIf gVarMeta(srcSlot)\flags & #C2FLAG_FLOAT
            gVarMeta(dstSlot)\valueFloat = gVarMeta(srcSlot)\valueFloat
         ElseIf gVarMeta(srcSlot)\flags & #C2FLAG_STR
            gVarMeta(dstSlot)\valueString = gVarMeta(srcSlot)\valueString
         EndIf
         ; Mark as preloadable
         gVarMeta(dstSlot)\flags = gVarMeta(dstSlot)\flags | #C2FLAG_PRELOAD
         CompilerIf #DEBUG
            Debug "V1.023.0: Marked slot " + Str(dstSlot) + " (" + gVarMeta(dstSlot)\name + ") for preload from const slot " + Str(srcSlot)
         CompilerEndIf
      EndIf
   EndProcedure

   Procedure            EmitInt( op.i, nVar.i = -1 )
      Protected         sourceFlags.w, destFlags.w
      Protected         isSourceLocal.b, isDestLocal.b
      Protected         sourceFlags2.w, destFlags2.w
      Protected         localOffset.i, localOffset2.i, localOffset3.i, localOffset4.i
      Protected         savedSource.i, savedSrc2.i
      Protected         inTernary2.b
      Protected         currentCode.i

      If gEmitIntCmd = #ljpush And op = #ljStore
         ; PUSH+STORE optimization
         ; Don't optimize inside ternary expressions - both branches need stack values
         ; Check if PUSH instruction is marked as part of ternary
         Protected inTernary.b = (llObjects()\flags & #INST_FLAG_TERNARY)

         sourceFlags = gVarMeta( llObjects()\i )\flags
         destFlags = gVarMeta( nVar )\flags
         isSourceLocal = IsLocalVar(llObjects()\i)
         isDestLocal = IsLocalVar(nVar)

         ; Only optimize to MOV if BOTH are not local (globals can use MOV)
         ; Or if destination is local (use LMOV)
         If Not inTernary And Not ((sourceFlags & #C2FLAG_PARAM) Or (destFlags & #C2FLAG_PARAM))
            ; Neither is parameter - can optimize to MOV
            If isDestLocal
               ; Destination is local - use LMOV
               ; For LMOV: i = paramOffset (destination), j = source varIndex
               savedSource = llObjects()\i  ; Save source BEFORE overwriting
               localOffset = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               ; If paramOffset looks invalid (too large - likely a slot number), fall back to PUSH+STORE
               If localOffset < 0 Or localOffset >= 20
                  ; paramOffset not set or suspiciously large - fall back to PUSH+STORE
                  gEmitIntLastOp = AddElement( llObjects() )
                  If destFlags & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  ElseIf destFlags & #C2FLAG_POINTER
                     ; V1.023.16: Use PSTORE for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPSTORE
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               Else
                  If sourceFlags & #C2FLAG_STR
                     llObjects()\code = #ljLMOVS
                  ElseIf sourceFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljLMOVF
                  ElseIf destFlags & #C2FLAG_POINTER
                     ; V1.023.16: Use PLMOV for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPLMOV
                  Else
                     llObjects()\code = #ljLMOV
                  EndIf
                  llObjects()\j = savedSource  ; j = source varIndex
                  llObjects()\i = localOffset  ; i = destination paramOffset
                  ; V1.023.0: Mark for preloading if assigning from constant
                  MarkPreloadable(savedSource, nVar)
               EndIf
            Else
               ; Global destination - use regular MOV
               ; V1.022.18: Preserve #C2FLAG_STRUCT when updating type flags for struct base slots
               If sourceFlags & #C2FLAG_STR
                  llObjects()\code = #ljMOVS
                  gVarMeta( nVar )\flags = (gVarMeta( nVar )\flags & #C2FLAG_STRUCT) | #C2FLAG_IDENT | #C2FLAG_STR
               ElseIf sourceFlags & #C2FLAG_FLOAT
                  llObjects()\code = #ljMOVF
                  gVarMeta( nVar )\flags = (gVarMeta( nVar )\flags & #C2FLAG_STRUCT) | #C2FLAG_IDENT | #C2FLAG_FLOAT
               ElseIf destFlags & #C2FLAG_POINTER
                  ; V1.023.16: Use PMOV for pointer types to preserve ptr/ptrtype metadata
                  llObjects()\code = #ljPMOV
               Else
                  llObjects()\code = #ljMOV
                  gVarMeta( nVar )\flags = (gVarMeta( nVar )\flags & #C2FLAG_STRUCT) | #C2FLAG_IDENT | #C2FLAG_INT
               EndIf
               llObjects()\j = llObjects()\i  ; j = source slot
               llObjects()\i = nVar           ; i = destination slot (V1.023.3: was missing!)
               ; V1.023.0: Mark for preloading if assigning from constant
               MarkPreloadable(llObjects()\j, nVar)
            EndIf
         Else
            ; One is a parameter - keep as PUSH+STORE but use local version if dest is local
            gEmitIntLastOp = AddElement( llObjects() )
            If isDestLocal
               localOffset3 = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               If localOffset3 >= 0 And localOffset3 < 20
                  If destFlags & #C2FLAG_STR
                     llObjects()\code = #ljLSTORES
                  ElseIf destFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljLSTOREF
                  ElseIf destFlags & #C2FLAG_POINTER
                     ; V1.023.16: Use PLSTORE for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPLSTORE
                  Else
                     llObjects()\code = #ljLSTORE
                  EndIf
                  ; Set the local variable index (paramOffset)
                  llObjects()\i = localOffset3
               Else
                  ; paramOffset not set - use global STORE
                  If destFlags & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  ElseIf destFlags & #C2FLAG_POINTER
                     ; V1.023.16: Use PSTORE for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPSTORE
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               EndIf
            Else
               llObjects()\code = op
            EndIf
         EndIf
      ElseIf gEmitIntCmd = #ljfetch And op = #ljstore
         ; FETCH+STORE optimization
         ; Don't optimize inside ternary expressions - both branches need stack values
         ; Check if FETCH instruction is marked as part of ternary
         inTernary2 = (llObjects()\flags & #INST_FLAG_TERNARY)

         sourceFlags2 = gVarMeta( llObjects()\i )\flags
         destFlags2 = gVarMeta( nVar )\flags
         isSourceLocal = IsLocalVar(llObjects()\i)
         isDestLocal = IsLocalVar(nVar)

         If Not inTernary2 And Not ((sourceFlags2 & #C2FLAG_PARAM) Or (destFlags2 & #C2FLAG_PARAM))
            ; Can optimize to MOV or LMOV
            If isDestLocal
               ; Use LMOV for local destination
               localOffset2 = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               If localOffset2 < 0 Or localOffset2 >= 20
                  ; paramOffset not set - fall back to FETCH+STORE
                  gEmitIntLastOp = AddElement( llObjects() )
                  If destFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  ElseIf destFlags2 & #C2FLAG_POINTER
                     ; V1.023.16: Use PSTORE for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPSTORE
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               Else
                  If sourceFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljLMOVS
                  ElseIf sourceFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljLMOVF
                  ElseIf destFlags2 & #C2FLAG_POINTER
                     ; V1.023.16: Use PLMOV for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPLMOV
                  Else
                     llObjects()\code = #ljLMOV
                  EndIf
                  savedSrc2 = llObjects()\i
                  llObjects()\i = localOffset2
                  llObjects()\j = savedSrc2
                  ; V1.023.0: Mark for preloading if assigning from constant
                  MarkPreloadable(savedSrc2, nVar)
               EndIf
            Else
               ; Use regular MOV for global destination
               If sourceFlags2 & #C2FLAG_STR
                  llObjects()\code = #ljMOVS
               ElseIf sourceFlags2 & #C2FLAG_FLOAT
                  llObjects()\code = #ljMOVF
               ElseIf destFlags2 & #C2FLAG_POINTER
                  ; V1.023.16: Use PMOV for pointer types to preserve ptr/ptrtype metadata
                  llObjects()\code = #ljPMOV
               Else
                  llObjects()\code = #ljMOV
               EndIf
               llObjects()\j = llObjects()\i
               ; V1.023.0: Mark for preloading if assigning from constant
               MarkPreloadable(llObjects()\j, nVar)
            EndIf
         Else
            ; Keep as FETCH+STORE but use local version if appropriate
            gEmitIntLastOp = AddElement( llObjects() )
            If isDestLocal
               localOffset4 = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               If localOffset4 >= 0 And localOffset4 < 20
                  If destFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljLSTORES
                  ElseIf destFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljLSTOREF
                  ElseIf destFlags2 & #C2FLAG_POINTER
                     ; V1.023.16: Use PLSTORE for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPLSTORE
                  Else
                     llObjects()\code = #ljLSTORE
                  EndIf
                  ; Set the local variable index (paramOffset)
                  llObjects()\i = localOffset4
               Else
                  ; paramOffset not set - use global STORE
                  If destFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  ElseIf destFlags2 & #C2FLAG_POINTER
                     ; V1.023.16: Use PSTORE for pointer types to preserve ptr/ptrtype metadata
                     llObjects()\code = #ljPSTORE
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               EndIf
            Else
               llObjects()\code = op
            EndIf
         EndIf

      ; V1.022.26: PUSHF+STOREF optimization → MOVF (float slot-only)
      ElseIf gEmitIntCmd = #ljPUSHF And op = #ljSTOREF
         Protected inTernaryF.b = (llObjects()\flags & #INST_FLAG_TERNARY)
         Protected sourceFlagsF.w = gVarMeta( llObjects()\i )\flags
         Protected destFlagsF.w = gVarMeta( nVar )\flags
         Protected isSourceLocalF.b = IsLocalVar(llObjects()\i)
         Protected isDestLocalF.b = IsLocalVar(nVar)

         If Not inTernaryF And Not ((sourceFlagsF & #C2FLAG_PARAM) Or (destFlagsF & #C2FLAG_PARAM))
            If isDestLocalF
               ; Local destination - use LMOVF
               Protected localOffsetF.i = gVarMeta(nVar)\paramOffset
               If localOffsetF < 0 Or localOffsetF >= 20
                  ; Fall back to PUSHF+STOREF
                  gEmitIntLastOp = AddElement( llObjects() )
                  llObjects()\code = #ljLSTOREF
                  llObjects()\i = nVar
               Else
                  llObjects()\code = #ljLMOVF
                  Protected savedSourceF.i = llObjects()\i
                  llObjects()\j = savedSourceF
                  llObjects()\i = localOffsetF
                  ; V1.023.0: Mark for preloading if assigning from constant
                  MarkPreloadable(savedSourceF, nVar)
               EndIf
            Else
               ; Global destination - use MOVF
               llObjects()\code = #ljMOVF
               llObjects()\j = llObjects()\i
               ; V1.023.0: Mark for preloading if assigning from constant
               MarkPreloadable(llObjects()\j, nVar)
            EndIf
         Else
            ; Keep as PUSHF+STOREF
            gEmitIntLastOp = AddElement( llObjects() )
            If isDestLocalF
               Protected localOffsetF2.i = gVarMeta(nVar)\paramOffset
               If localOffsetF2 >= 0 And localOffsetF2 < 20
                  llObjects()\code = #ljLSTOREF
                  llObjects()\i = localOffsetF2
               Else
                  llObjects()\code = #ljSTOREF
                  llObjects()\i = nVar
               EndIf
            Else
               llObjects()\code = #ljSTOREF
               llObjects()\i = nVar
            EndIf
         EndIf

      ; V1.022.26: PUSHS+STORES optimization → MOVS (string slot-only)
      ElseIf gEmitIntCmd = #ljPUSHS And op = #ljSTORES
         Protected inTernaryS.b = (llObjects()\flags & #INST_FLAG_TERNARY)
         Protected sourceFlagsS.w = gVarMeta( llObjects()\i )\flags
         Protected destFlagsS.w = gVarMeta( nVar )\flags
         Protected isSourceLocalS.b = IsLocalVar(llObjects()\i)
         Protected isDestLocalS.b = IsLocalVar(nVar)

         If Not inTernaryS And Not ((sourceFlagsS & #C2FLAG_PARAM) Or (destFlagsS & #C2FLAG_PARAM))
            If isDestLocalS
               ; Local destination - use LMOVS
               Protected localOffsetS.i = gVarMeta(nVar)\paramOffset
               If localOffsetS < 0 Or localOffsetS >= 20
                  ; Fall back to PUSHS+STORES
                  gEmitIntLastOp = AddElement( llObjects() )
                  llObjects()\code = #ljLSTORES
                  llObjects()\i = nVar
               Else
                  llObjects()\code = #ljLMOVS
                  Protected savedSourceS.i = llObjects()\i
                  llObjects()\j = savedSourceS
                  llObjects()\i = localOffsetS
                  ; V1.023.0: Mark for preloading if assigning from constant
                  MarkPreloadable(savedSourceS, nVar)
               EndIf
            Else
               ; Global destination - use MOVS
               llObjects()\code = #ljMOVS
               llObjects()\j = llObjects()\i
               ; V1.023.0: Mark for preloading if assigning from constant
               MarkPreloadable(llObjects()\j, nVar)
            EndIf
         Else
            ; Keep as PUSHS+STORES
            gEmitIntLastOp = AddElement( llObjects() )
            If isDestLocalS
               Protected localOffsetS2.i = gVarMeta(nVar)\paramOffset
               If localOffsetS2 >= 0 And localOffsetS2 < 20
                  llObjects()\code = #ljLSTORES
                  llObjects()\i = localOffsetS2
               Else
                  llObjects()\code = #ljSTORES
                  llObjects()\i = nVar
               EndIf
            Else
               llObjects()\code = #ljSTORES
               llObjects()\i = nVar
            EndIf
         EndIf

      Else
         ; Standard emission - check if we should use local opcode
         gEmitIntLastOp = AddElement( llObjects() )

         If nVar >= 0 And IsLocalVar(nVar)
            ; This is a local variable - convert to local opcode and translate index
            Select op
               Case #ljFetch
                  llObjects()\code = #ljLFETCH
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljFETCHS
                  llObjects()\code = #ljLFETCHS
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljFETCHF
                  llObjects()\code = #ljLFETCHF
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljStore
                  ; V1.023.21: Check if source is a pointer (previous opcode produces pointer)
                  ; or destination has pointer flag - use PLSTORE to preserve ptr/ptrtype metadata
                  If gEmitIntCmd = #ljGETSTRUCTADDR Or gEmitIntCmd = #ljGETADDR Or gEmitIntCmd = #ljGETADDRF Or gEmitIntCmd = #ljGETADDRS Or gEmitIntCmd = #ljGETARRAYADDR Or gEmitIntCmd = #ljGETARRAYADDRF Or gEmitIntCmd = #ljGETARRAYADDRS Or gVarMeta(nVar)\flags & #C2FLAG_POINTER
                     llObjects()\code = #ljPLSTORE
                  Else
                     llObjects()\code = #ljLSTORE
                  EndIf
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljSTORES
                  llObjects()\code = #ljLSTORES
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljSTOREF
                  llObjects()\code = #ljLSTOREF
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Default
                  llObjects()\code = op
            EndSelect
         Else
            llObjects()\code = op
         EndIf
      EndIf

      ; Only set llObjects()\i for variable-related opcodes
      ; Skip this for opcodes that don't operate on variables (CALL uses funcId, not varSlot)
      ; Note: For local opcodes (LFETCH, LSTORE, etc.), \i was already set in optimization paths above
      ; V1.023.15: Changed from nVar > -1 to nVar <> -1 to allow negative encoded local pointers (e.g., -4 for PTRSTRUCTSTORE)
      If nVar <> -1
         ; Check if this is an opcode that operates on variables
         currentCode = llObjects()\code
         Select currentCode
            ; Local opcodes - \i already set to paramOffset in optimization code above, don't touch
            ; V1.023.23: Added pointer-preserving local opcodes (PLSTORE, PLMOV, PLFETCH) - also use paramOffset
            Case #ljLFETCH, #ljLFETCHS, #ljLFETCHF, #ljLSTORE, #ljLSTORES, #ljLSTOREF, #ljLMOV, #ljLMOVS, #ljLMOVF, #ljPLSTORE, #ljPLMOV, #ljPLFETCH
               ; Do nothing - \i already contains correct paramOffset from optimization paths

            ; Global opcodes - need to set \i to variable slot
            Case #ljFetch, #ljFETCHS, #ljFETCHF, #ljStore, #ljSTORES, #ljSTOREF,
                 #ljPush, #ljPUSHS, #ljPUSHF, #ljPOP, #ljPOPS, #ljPOPF
               llObjects()\i = nVar

            Default
               ; Non-variable opcode (CALL, JMP, etc.) - store nVar as-is
               llObjects()\i = nVar
         EndSelect
      EndIf

      ; Mark instruction if inside ternary expression
      If gInTernary
         llObjects()\flags = llObjects()\flags | #INST_FLAG_TERNARY
      EndIf

      gEmitIntCmd = llObjects()\code
   EndProcedure
   
   Procedure            FetchVarOffset(text.s, *assignmentTree.stTree = 0, syntheticType.i = 0, forceLocal.i = #False)
      ; All Protected declarations at procedure start per CLAUDE.md rule #3
      Protected         i, j
      Protected         temp.s
      Protected         inferredType.w
      Protected         savedIndex
      Protected         tokenFound.i = #False
      Protected         searchName.s
      Protected         mangledName.s
      Protected         isLocal.i
      ; V1.022.16: Struct field handling variables
      Protected         structFieldPos.i
      Protected         structName.s
      Protected         fieldName.s
      Protected         structSlot.i
      Protected         fieldOffset.i
      Protected         fieldFound.i
      Protected         mangledStructName.s
      ; V1.022.99: Store found token's properties for type detection
      Protected         foundTokenTypeHint.i
      Protected         foundTokenType.i
      Protected         structTypeName.s

      j = -1
      structFieldPos = 0
      structSlot = -1
      fieldOffset = 0
      fieldFound = #False

      ; V1.022.21: Check pre-allocated constant maps first (fast path)
      ; Constants were extracted during ExtractConstants() pass
      If syntheticType = #ljINT
         If FindMapElement(mapConstInt(), text)
            ProcedureReturn mapConstInt()
         EndIf
      ElseIf syntheticType = #ljFLOAT
         If FindMapElement(mapConstFloat(), text)
            ProcedureReturn mapConstFloat()
         EndIf
      ElseIf syntheticType = #ljSTRING
         ; V1.023.27: Debug - trace string constant lookup
         Debug "FetchVarOffset: Looking up string '" + text + "' in mapConstStr"
         If FindMapElement(mapConstStr(), text)
            Debug "  -> Found in mapConstStr, slot=" + Str(mapConstStr())
            ProcedureReturn mapConstStr()
         Else
            Debug "  -> NOT FOUND in mapConstStr!"
         EndIf
      EndIf

      ; V1.022.17: Handle struct field names (e.g., "c1\id" -> find "c1" struct + field offset)
      structFieldPos = FindString(text, "\")
      If structFieldPos > 0
         structName = Trim(Left(text, structFieldPos - 1))
         fieldName = Trim(Mid(text, structFieldPos + 1))

         ; Apply name mangling for local struct variables
         If gCurrentFunctionName <> ""
            ; Try mangled name first for local structs
            mangledStructName = gCurrentFunctionName + "_" + structName
            For i = 0 To gnLastVariable - 1
               If LCase(Trim(gVarMeta(i)\name)) = LCase(mangledStructName) And (gVarMeta(i)\flags & #C2FLAG_STRUCT)
                  structSlot = i
                  Break
               EndIf
            Next
         EndIf

         ; If not found as local, try global
         If structSlot < 0
            For i = 0 To gnLastVariable - 1
               If LCase(Trim(gVarMeta(i)\name)) = LCase(structName) And (gVarMeta(i)\flags & #C2FLAG_STRUCT)
                  structSlot = i
                  Break
               EndIf
            Next
         EndIf

         ; If struct found, look up field offset
         If structSlot >= 0
            structTypeName = gVarMeta(structSlot)\structType
            If FindMapElement(mapStructDefs(), structTypeName)
               ResetList(mapStructDefs()\fields())
               ForEach mapStructDefs()\fields()
                  If LCase(Trim(mapStructDefs()\fields()\name)) = LCase(fieldName)
                     fieldOffset = mapStructDefs()\fields()\offset
                     fieldFound = #True
                     Break
                  EndIf
               Next
            EndIf

            If fieldFound
               ; Return structSlot + fieldOffset (works for offset 0 too)
               ProcedureReturn structSlot + fieldOffset
            EndIf
         EndIf
         ; If struct/field not found, fall through to normal handling (create new variable)
      EndIf

      ; Apply name mangling for local variables inside functions
      ; Synthetic variables (starting with $) and constants are never mangled
      If gCurrentFunctionName <> "" And Left(text, 1) <> "$" And syntheticType = 0
         ; Inside a function - first try to find as local variable (mangled)
         mangledName = gCurrentFunctionName + "_" + text
         searchName = mangledName
         CompilerIf #DEBUG
            Debug "FetchVarOffset: In function, mangling '" + text + "' -> '" + mangledName + "' (gCurrentFunctionName='" + gCurrentFunctionName + "')"
         CompilerEndIf

         ; Check if mangled (local) version exists
         ; V1.022.30: Use case-insensitive comparison to handle any case variations
         For i = 0 To gnLastVariable - 1
            If LCase(gVarMeta(i)\name) = LCase(searchName)
               CompilerIf #DEBUG
                  Debug "FetchVarOffset: Found existing local '" + searchName + "' at slot " + Str(i)
               CompilerEndIf
               ProcedureReturn i  ; Found local variable
            EndIf
         Next

         ; Not found as local - check if global exists (unless forceLocal is set)
         ; V1.022.71: forceLocal=true when type annotation present (.i/.f/.s)
         ; var = expr (no type) --> uses global if exists
         ; var.type = expr (with type) --> creates local (shadows global)

         If gCodeGenParamIndex < 0 And forceLocal = #False
            ; No type annotation - check if global exists and use it
            For i = 0 To gnLastVariable - 1
               If LCase(gVarMeta(i)\name) = LCase(text) And gVarMeta(i)\paramOffset = -1
                  ; Found as global - use it (intended behavior for var = expr)
                  CompilerIf #DEBUG
                     Debug "FetchVarOffset: Found global '" + text + "' at slot " + Str(i)
                  CompilerEndIf
                  ProcedureReturn i
               EndIf
            Next
         ElseIf forceLocal
            ; V1.022.71: Type annotation present - create local (shadow global if exists)
            CompilerIf #DEBUG
               Debug "V1.022.71: Type annotation - creating local '" + text + "' (shadows global if exists)"
            CompilerEndIf
         EndIf

         ; Global not found (or assigning) - create as local
         CompilerIf #DEBUG
            Debug "FetchVarOffset: Creating new local '" + mangledName + "'"
         CompilerEndIf
         text = mangledName
      Else
         CompilerIf #DEBUG
            Debug "FetchVarOffset: Global scope or synthetic, text='" + text + "' gCurrentFunctionName='" + gCurrentFunctionName + "'"
         CompilerEndIf
      EndIf

      ; Check if variable already exists (with final name after mangling)
      ; V1.022.30: Use case-insensitive comparison
      ; V1.023.27: CRITICAL FIX - Skip variable lookup when looking for constants
      ; Constants (syntheticType=#ljINT/#ljFLOAT/#ljSTRING) should never match variables
      ; via case-insensitive lookup. String constant "A" must NOT match variable "a"!
      If syntheticType <> #ljINT And syntheticType <> #ljFLOAT And syntheticType <> #ljSTRING
      For i = 0 To gnLastVariable - 1
         ; V1.023.27: Skip constants when looking for variables (syntheticType=0)
         ; This prevents variable "x" from matching string constant "X" via case-insensitive lookup
         If (gVarMeta(i)\flags & #C2FLAG_CONST) And syntheticType = 0
            Continue
         EndIf
         If LCase(gVarMeta(i)\name) = LCase(text)
            ; Variable exists - check if it's a local variable that needs an offset assigned
            If gCurrentFunctionName <> "" And gCodeGenParamIndex < 0 And gCodeGenFunction > 0
               If gVarMeta(i)\paramOffset < 0
                  ; This is a local variable without an offset - assign one
                  ; V1.022.31: Don't assign local offsets to $ synthetic temps - they're forced global
                  ; by GetExprSlotOrTemp. Including them here caused gaps in local slot numbering.
                  If LCase(Left(text, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
                     gVarMeta(i)\paramOffset = gCodeGenLocalIndex
                     gCodeGenLocalIndex + 1

                     ; Update nLocals in mapModules immediately
                     ForEach mapModules()
                        If mapModules()\function = gCodeGenFunction
                           mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                           Break
                        EndIf
                     Next
                  EndIf
               EndIf
            EndIf
            ProcedureReturn i
         EndIf
      Next
      EndIf  ; V1.023.27: End of syntheticType check

      ; New variable - find token (unless it's a synthetic $ variable)
      i = -1
      savedIndex = ListIndex(TOKEN())
      foundTokenTypeHint = 0  ; V1.022.99: Store found token's typeHint
      foundTokenType = 0      ; V1.022.99: Store found token's type

      ; Don't look up synthetic variables (starting with $) in token list
      If Left(text, 1) <> "$"
         ; V1.022.100: CRITICAL FIX - Extract original name from mangled name for token search
         ; Mangled names like "partition_temp" need to search for "temp" in token list
         ; because TOKEN()\value has the original name, not the mangled name
         Protected tokenSearchName.s = text
         If gCurrentFunctionName <> ""
            Protected prefixLen.i = Len(gCurrentFunctionName) + 1  ; "functionname_"
            If LCase(Left(text, prefixLen)) = LCase(gCurrentFunctionName + "_")
               ; Extract original name after the function prefix
               tokenSearchName = Mid(text, prefixLen + 1)
               CompilerIf #DEBUG
                  Debug "V1.022.100: Searching for original '" + tokenSearchName + "' (mangled: '" + text + "')"
               CompilerEndIf
            EndIf
         EndIf

         ForEach TOKEN()
            If TOKEN()\value = tokenSearchName
               i = ListIndex( TOKEN() )
               ; V1.022.99: CRITICAL FIX - Save the found token's properties BEFORE restoring position
               ; Previously we restored position THEN checked TOKEN()\typeHint which was WRONG token!
               foundTokenTypeHint = TOKEN()\typeHint
               foundTokenType = TOKEN()\TokenType
               CompilerIf #DEBUG
                  Debug "V1.022.100: Found token '" + tokenSearchName + "' typeHint=" + Str(foundTokenTypeHint) + " tokenType=" + Str(foundTokenType)
               CompilerEndIf
               Break
            EndIf
         Next

         If savedIndex >= 0
            SelectElement(TOKEN(), savedIndex)
         EndIf
      EndIf

      gVarMeta(gnLastVariable)\name  = text
      CompilerIf #DEBUG
         Debug "FetchVarOffset: Registered new variable '" + text + "' at slot " + Str(gnLastVariable)
      CompilerEndIf
      ; V1.022.29: Initialize paramOffset to -1 (global/not-yet-assigned)
      ; This prevents confusion with paramOffset=0 which is a valid local offset
      gVarMeta(gnLastVariable)\paramOffset = -1

      ; Check if this is a synthetic temporary variable (starts with $)
      If Left(text, 1) = "$"
         ; Synthetic variable - determine type from suffix or syntheticType parameter
         If syntheticType & #C2FLAG_FLOAT Or Right(text, 1) = "f"
            ;gVarFloat(gnLastVariable) = 0.0
            gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
         ElseIf syntheticType & #C2FLAG_STR Or Right(text, 1) = "s"
            ;gVarString(gnLastVariable) = ""
            gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_STR
         Else
            ;gVarInt(gnLastVariable) = 0
            gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_INT
         EndIf
      ; Check if this is a synthetic constant (syntheticType passed in)
      ElseIf syntheticType = #ljINT
         gVarMeta(gnLastVariable)\valueInt = Val(text)
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_INT
      ElseIf syntheticType = #ljFLOAT
         gVarMeta(gnLastVariable)\valueFloat = ValF(text)
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
      ElseIf syntheticType = #ljSTRING
         gVarMeta(gnLastVariable)\valueString = text
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_STR
      Else
         ; V1.022.99: Use saved token properties (foundTokenType, foundTokenTypeHint)
         ; instead of TOKEN() which points to wrong position after restore
         ; Set type for constants (literals)
         If foundTokenType = #ljINT
            gVarMeta(gnLastVariable)\valueInt = Val(text)
            gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_INT
         ElseIf foundTokenType = #ljSTRING
            gVarMeta(gnLastVariable)\valueString = text
            gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_STR
         ElseIf foundTokenType = #ljFLOAT
            gVarMeta(gnLastVariable)\valueFloat = ValF(text)
            gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
         ElseIf foundTokenType = #ljIDENT
            ; V1.022.99/100: Check saved typeHint from correct token (found via original name search)
            If foundTokenTypeHint = #ljFLOAT
               gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
               CompilerIf #DEBUG
                  Debug "V1.022.100: Set FLOAT type for '" + text + "' from token typeHint"
               CompilerEndIf
            ElseIf foundTokenTypeHint = #ljSTRING
               gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_STR
               CompilerIf #DEBUG
                  Debug "V1.022.100: Set STR type for '" + text + "' from token typeHint"
               CompilerEndIf
            Else
               ; No suffix - default to INT (no type inference from assignment)
               ; Type conversion will be handled during code generation
               gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_INT
            EndIf
            ;gVarInt(gnLastVariable) = gnLastVariable

         Else
            ;Debug ": " + text + " Not found"
            ;ProcedureReturn -1
         EndIf
      EndIf

      ; If we're creating a local variable (inside a function, not a parameter),
      ; assign it an offset and update nLocals count
      ; V1.022.31: Only mangled variables, NOT $ synthetic temps (forced global by GetExprSlotOrTemp)
      isLocal = #False
      If gCurrentFunctionName <> "" And gCodeGenParamIndex < 0 And gCodeGenFunction > 0
         If LCase(Left(text, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
            ; This is a new local variable (mangled name)
            gVarMeta(gnLastVariable)\paramOffset = gCodeGenLocalIndex
            gCodeGenLocalIndex + 1
            isLocal = #True

            ; Update nLocals in mapModules immediately
            ForEach mapModules()
               If mapModules()\function = gCodeGenFunction
                  mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                  Break
               EndIf
            Next
         EndIf
      EndIf

      gnLastVariable + 1

      ; V1.020.059: Increment gnGlobalVariables ONLY for global-scope variables
      ; MUST be at global scope (gCodeGenFunction = 0)
      ; AND not a parameter (gCodeGenParamIndex < 0)
      ; AND not a local variable (Not isLocal)
      ; V1.023.16: AND not a synthetic constant (syntheticType = 0) - constants go in separate section
      If gCodeGenFunction = 0 And gCodeGenParamIndex < 0 And Not isLocal And syntheticType = 0
         gnGlobalVariables + 1
         CompilerIf #DEBUG
         Debug "[gnGlobalVariables=" + Str(gnGlobalVariables) + "] Counted: '" + text + "' (slot " + Str(gnLastVariable - 1) + ", gCodeGenFunction=" + Str(gCodeGenFunction) + ", gCodeGenParamIndex=" + Str(gCodeGenParamIndex) + ", isLocal=" + Str(isLocal) + ")"
         CompilerEndIf
      Else
         CompilerIf #DEBUG
         Debug "[SKIPPED] Not counted: '" + text + "' (slot " + Str(gnLastVariable - 1) + ", gCodeGenFunction=" + Str(gCodeGenFunction) + ", gCodeGenParamIndex=" + Str(gCodeGenParamIndex) + ", isLocal=" + Str(isLocal) + ")"
         CompilerEndIf
      EndIf

      ProcedureReturn gnLastVariable - 1
   EndProcedure

   ; Helper: Get type name string from type flags
   Procedure.s          GetTypeNameFromFlags( typeFlags.w )
      If typeFlags & #C2FLAG_FLOAT
         ProcedureReturn "float"
      ElseIf typeFlags & #C2FLAG_STR
         ProcedureReturn "string"
      ElseIf typeFlags & #C2FLAG_INT
         ProcedureReturn "int"
      Else
         ProcedureReturn "unknown"
      EndIf
   EndProcedure

   ; Helper: Determine the result type of an expression
   Procedure.w          GetExprResultType( *x.stTree, depth.i = 0 )
      Protected         n
      Protected         funcId
      Protected         leftType.w, rightType.w
      Protected         pointerBaseType.w
      Protected         *funcNode.stTree
      
      ; Prevent infinite recursion / stack overflow
      If depth > 100
         ProcedureReturn #C2FLAG_INT
      EndIf

      ; Check if pointer is valid
      If Not *x
         ProcedureReturn #C2FLAG_INT
      EndIf

      ; Additional safety: check if pointer looks obviously invalid
      ; (very small addresses are typically invalid)
      If *x < 4096  ; First page is typically unmapped
         ProcedureReturn #C2FLAG_INT
      EndIf

      Select *x\NodeType
         ; UNUSED/0 will fall through to default case
         Case #ljUNUSED
            ProcedureReturn #C2FLAG_INT
         Case #ljSTRING
            ProcedureReturn #C2FLAG_STR

         Case #ljFLOAT
            ProcedureReturn #C2FLAG_FLOAT

         Case #ljINT
            ProcedureReturn #C2FLAG_INT

         Case #ljIDENT
            ; V1.023.35: Handle struct field access (e.g., "v1\x")
            ; Need to look up field type from struct definition
            Protected structFieldPos.i = FindString(*x\value, "\")
            If structFieldPos > 0
               Protected structVarName.s = Left(*x\value, structFieldPos - 1)
               Protected fieldName.s = Mid(*x\value, structFieldPos + 1)
               Protected structSlot.i = -1
               Protected structTypeName.s = ""

               ; Find the struct variable (try mangled name first for locals)
               If gCurrentFunctionName <> ""
                  Protected mangledStructName.s = gCurrentFunctionName + "_" + structVarName
                  For n = 0 To gnLastVariable - 1
                     If LCase(gVarMeta(n)\name) = LCase(mangledStructName) And (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        structSlot = n
                        structTypeName = gVarMeta(n)\structType
                        Break
                     EndIf
                  Next
               EndIf

               ; Try global struct if not found as local
               If structSlot < 0
                  For n = 0 To gnLastVariable - 1
                     If LCase(gVarMeta(n)\name) = LCase(structVarName) And (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        structSlot = n
                        structTypeName = gVarMeta(n)\structType
                        Break
                     EndIf
                  Next
               EndIf

               ; Look up field type from struct definition
               If structTypeName <> "" And FindMapElement(mapStructDefs(), structTypeName)
                  ForEach mapStructDefs()\fields()
                     If LCase(mapStructDefs()\fields()\name) = LCase(fieldName)
                        ProcedureReturn mapStructDefs()\fields()\fieldType
                     EndIf
                  Next
               EndIf
            EndIf

            ; Check variable type - search existing variables
            ; Apply name mangling for local variables (same logic as FetchVarOffset)
            Protected searchName.s = *x\value
            If gCurrentFunctionName <> "" And Left(*x\value, 1) <> "$"
               ; Try mangled name first (local variable)
               searchName = gCurrentFunctionName + "_" + *x\value
            EndIf

            For n = 0 To gnLastVariable - 1
               If gVarMeta(n)\name = searchName
                  ; Found the variable - return its type flags
                  ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
               EndIf
            Next

            ; If mangled name not found and we tried mangling, try global name
            If searchName <> *x\value
               For n = 0 To gnLastVariable - 1
                  If gVarMeta(n)\name = *x\value
                     ; Found the global variable - return its type flags
                     ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
                  EndIf
               Next
            EndIf

            ; Variable not found in gVarMeta - might be a parameter during parsing
            ; Check current function's parameter types in mapModules
            If gCurrentFunctionName <> ""
               ForEach mapModules()
                  If MapKey(mapModules()) = gCurrentFunctionName
                     ; Parse the parameter string to find this parameter's type
                     Protected paramStr.s = mapModules()\params
                     Protected closeParenPos.i = FindString(paramStr, ")", 1)
                     If closeParenPos > 0
                        paramStr = Mid(paramStr, 2, closeParenPos - 2)
                     Else
                        paramStr = Mid(paramStr, 2)
                     EndIf
                     paramStr = Trim(paramStr)

                     If paramStr <> ""
                        Protected paramIdx.i
                        For paramIdx = 1 To CountString(paramStr, ",") + 1
                           Protected param.s = Trim(StringField(paramStr, paramIdx, ","))
                           ; Extract parameter name (before type suffix)
                           Protected paramName.s = param
                           If FindString(param, ".f", 1, #PB_String_NoCase)
                              paramName = Left(param, FindString(param, ".f", 1, #PB_String_NoCase) - 1)
                           ElseIf FindString(param, ".d", 1, #PB_String_NoCase)
                              paramName = Left(param, FindString(param, ".d", 1, #PB_String_NoCase) - 1)
                           ElseIf FindString(param, ".s", 1, #PB_String_NoCase)
                              paramName = Left(param, FindString(param, ".s", 1, #PB_String_NoCase) - 1)
                           EndIf

                           If LCase(paramName) = LCase(*x\value)
                              ; Found the parameter - return its type from paramTypes list
                              If SelectElement(mapModules()\paramTypes(), paramIdx - 1)
                                 ProcedureReturn mapModules()\paramTypes()
                              EndIf
                           EndIf
                        Next
                     EndIf
                     Break
                  EndIf
               Next
            EndIf

            ; Variable not found in gVarMeta or parameters
            ; Check mapVariableTypes (populated during parsing from typeHints)
            If FindMapElement(mapVariableTypes(), searchName)
               ProcedureReturn mapVariableTypes()
            EndIf

            ; If mangled name not found, try global name
            If searchName <> *x\value And FindMapElement(mapVariableTypes(), *x\value)
               ProcedureReturn mapVariableTypes()
            EndIf

            ; Variable not found anywhere - default to INT
            ProcedureReturn #C2FLAG_INT

         Case #ljAdd, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE
            ; Arithmetic operations: result is string if any operand is string,
            ; else float if any operand is float, else int
            ; V1.20.28: Preserve POINTER flag for pointer arithmetic (ptr+int, ptr-int)
            leftType = #C2FLAG_INT
            rightType = #C2FLAG_INT

            If *x\left
               leftType = GetExprResultType(*x\left, depth + 1)
            EndIf

            If *x\right
               rightType = GetExprResultType(*x\right, depth + 1)
            EndIf

            ; V1.20.28: For ADD/SUBTRACT, preserve POINTER flag (pointer arithmetic)
            ; ptr + int, ptr - int, int + ptr all preserve pointer type
            If *x\NodeType = #ljAdd Or *x\NodeType = #ljSUBTRACT
               If leftType & #C2FLAG_POINTER Or rightType & #C2FLAG_POINTER
                  ; One operand is a pointer - result is also a pointer
                  ; Preserve the base type (INT/FLOAT/STR) from the pointer operand
                  pointerBaseType = #C2FLAG_INT
                  If leftType & #C2FLAG_POINTER
                     pointerBaseType = leftType & #C2FLAG_TYPE
                  ElseIf rightType & #C2FLAG_POINTER
                     pointerBaseType = rightType & #C2FLAG_TYPE
                  EndIf
                  ProcedureReturn #C2FLAG_POINTER | pointerBaseType
               EndIf
            EndIf

            If leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR
               ProcedureReturn #C2FLAG_STR
            ElseIf leftType & #C2FLAG_FLOAT Or rightType & #C2FLAG_FLOAT
               ProcedureReturn #C2FLAG_FLOAT
            Else
               ProcedureReturn #C2FLAG_INT
            EndIf

         Case #ljNEGATE
            ; Negation preserves type
            If *x\left
               ProcedureReturn GetExprResultType(*x\left, depth + 1)
            EndIf
            ProcedureReturn #C2FLAG_INT

         Case #ljPRE_INC, #ljPRE_DEC, #ljPOST_INC, #ljPOST_DEC
            ; Increment/decrement operators preserve the variable's type
            If *x\left
               ProcedureReturn GetExprResultType(*x\left, depth + 1)
            EndIf
            ProcedureReturn #C2FLAG_INT

         ; Type conversion operators - return the target type
         Case #ljITOF, #ljSTOF
            ProcedureReturn #C2FLAG_FLOAT
         Case #ljFTOI, #ljSTOI
            ProcedureReturn #C2FLAG_INT
         Case #ljITOS, #ljFTOS
            ProcedureReturn #C2FLAG_STR

         ; Cast operators (V1.18.63) - return the target type
         Case #ljCAST_INT
            ProcedureReturn #C2FLAG_INT
         Case #ljCAST_FLOAT
            ProcedureReturn #C2FLAG_FLOAT
         Case #ljCAST_STRING
            ProcedureReturn #C2FLAG_STR

         ; Pointer operations (V1.19.3) - return type based on pointer's declared type
         Case #ljPTRFETCH
            ; V1.021.12: Determine result type from the pointer variable's declared type
            ; *x\left is the pointer variable being dereferenced (e.g., 'ptr' in '*ptr')
            If *x\left And *x\left\NodeType = #ljIDENT
               ; Look up the pointer variable's type in gVarMeta
               Protected ptrName.s = *x\left\value
               Protected mangledPtrName.s = ptrName
               If gCurrentFunctionName <> "" And Left(ptrName, 1) <> "$"
                  mangledPtrName = gCurrentFunctionName + "_" + ptrName
               EndIf

               For n = 0 To gnLastVariable - 1
                  If gVarMeta(n)\name = mangledPtrName Or gVarMeta(n)\name = ptrName
                     ; Found the variable - return its declared type (INT/FLOAT/STR)
                     ; The .i/.f/.s suffix indicates what type the pointer points to
                     ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
                  EndIf
               Next
            EndIf
            ; Default to INT for unresolved cases
            ProcedureReturn #C2FLAG_INT

         ; V1.20.21: Pointer field access - return explicit types
         Case #ljPTRFIELD_I
            ProcedureReturn #C2FLAG_INT
         Case #ljPTRFIELD_F
            ProcedureReturn #C2FLAG_FLOAT
         Case #ljPTRFIELD_S
            ProcedureReturn #C2FLAG_STR

         ; V1.022.44: Struct array field access result types
         Case #nd_StructArrayField_I
            ProcedureReturn #C2FLAG_INT
         Case #nd_StructArrayField_F
            ProcedureReturn #C2FLAG_FLOAT
         Case #nd_StructArrayField_S
            ProcedureReturn #C2FLAG_STR

         Case #ljTERNARY
            ; Ternary operator: result type is determined by true/false branches
            ; *x\right is a COLON node with true_expr in left, false_expr in right
            If *x\right And *x\right\left And *x\right\right
               leftType = GetExprResultType(*x\right\left, depth + 1)    ; true branch
               rightType = GetExprResultType(*x\right\right, depth + 1)  ; false branch

               ; Result type is string if either branch is string
               If leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR
                  ProcedureReturn #C2FLAG_STR
               ; Result type is float if either branch is float
               ElseIf leftType & #C2FLAG_FLOAT Or rightType & #C2FLAG_FLOAT
                  ProcedureReturn #C2FLAG_FLOAT
               Else
                  ProcedureReturn #C2FLAG_INT
               EndIf
            EndIf
            ; Default to INT if structure is invalid
            ProcedureReturn #C2FLAG_INT

         Case #ljCall, #ljSEQ
            ; Function call or SEQ node containing a call - look up function's return type
            
            ; For SEQ nodes, check if right child is a Call
            If *x\NodeType = #ljSEQ And *x\right And *x\right\NodeType = #ljCall
               *funcNode = *x\right
            ElseIf *x\NodeType = #ljCall
               *funcNode = *x
            Else
               ; SEQ without call - try to infer from left or right
               If *x\left
                  leftType = GetExprResultType(*x\left, depth + 1)
                  If leftType <> #C2FLAG_INT
                     ProcedureReturn leftType
                  EndIf
               EndIf
               If *x\right
                  ProcedureReturn GetExprResultType(*x\right, depth + 1)
               EndIf
               ProcedureReturn #C2FLAG_INT
            EndIf
            
            ; Look up the function's declared return type
            If *funcNode
               funcId = Val(*funcNode\value)
               
               ; Check if it's a built-in function
               ; V1.023.30: Check for type conversion opcodes first (str(), strf())
               If funcId = #ljITOS Or funcId = #ljFTOS
                  ProcedureReturn #C2FLAG_STR
               ElseIf funcId >= #ljBUILTIN_RANDOM
                  ; Built-in functions - look up in mapBuiltins for return type
                  ForEach mapBuiltins()
                     If mapBuiltins()\opcode = funcId
                        ProcedureReturn mapBuiltins()\returnType
                     EndIf
                  Next
                  ; Default for unknown built-ins
                  ProcedureReturn #C2FLAG_INT
               Else
                  ; User-defined function - look up in mapModules
                  ForEach mapModules()
                     If mapModules()\function = funcId
                        ProcedureReturn mapModules()\returnType
                     EndIf
                  Next
               EndIf
            EndIf
            
            ProcedureReturn #C2FLAG_INT

         Case #ljLeftBracket
            ; Array element access - return the array's element type
            If *x\left And *x\left\NodeType = #ljIDENT
               ; Use FetchVarOffset to find the array variable (handles name mangling)
               n = FetchVarOffset(*x\left\value, 0, 0)
               If n >= 0
                  ; Found the array - return its element type
                  ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
               EndIf
            EndIf
            ; Array not found - default to INT
            ProcedureReturn #C2FLAG_INT

         ; V1.20.25: Address-of operations return pointer types
         Case #ljGETADDR
            ; &variable or &arr[index] returns integer pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_INT
         Case #ljGETADDRF
            ; &variable.f returns float pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_FLOAT
         Case #ljGETADDRS
            ; &variable.s returns string pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_STR
         Case #ljGETARRAYADDR
            ; &arr[index] returns integer array element pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_INT
         Case #ljGETARRAYADDRF
            ; &arr.f[index] returns float array element pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_FLOAT
         Case #ljGETARRAYADDRS
            ; &arr.s[index] returns string array element pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_STR

         ; V1.023.21: Struct address returns pointer type
         Case #ljGETSTRUCTADDR
            ; &structVar returns struct pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_INT

         Default
            ; Comparisons and other operations return INT
            ProcedureReturn #C2FLAG_INT
      EndSelect
   EndProcedure

   ; V1.022.20: Helper to get slot for expression (slot-only optimization)
   ; V1.022.31: Rewritten for recursion safety - no global temp slots
   ; For simple GLOBAL idents/constants: returns slot directly (no code emitted)
   ; For LOCAL variables: emits LFETCH (push to stack), returns -1
   ; For complex expressions: emits code (result on stack), returns -1
   ; Return value -1 signals array opcodes to use _STACK variants
   Procedure.i          GetExprSlotOrTemp(*expr.stTree)
      ; V1.022.31: Returns slot index for simple globals/constants
      ; V1.022.50: Always returns valid slot - never -1. Complex/local values stored in temp slot.
      ; V1.022.86: When inside function, use LOCAL temps for recursion safety
      ;            Return value encoding:
      ;            - positive or 0 = global slot → use _OPT opcodes
      ;            - -1 = reserved for STACK (not used by this function anymore)
      ;            - < -1 = local offset encoded as -(localOffset + 2) → use _LOPT opcodes
      ;            So -2 means LOCAL[0], -3 means LOCAL[1], etc.

      If Not *expr
         ProcedureReturn 0  ; Return slot 0 (discard) for null expressions
      EndIf

      Select *expr\NodeType
         Case #ljIDENT
            ; Simple variable - check if local or global
            Protected identSlot.i = FetchVarOffset(*expr\value)

            ; V1.022.50: Local variables - copy to temp slot
            If gVarMeta(identSlot)\paramOffset >= 0
               ; Local variable - emit LFETCH to push value, then LSTORE to local temp
               Protected localExprType.w = gVarMeta(identSlot)\flags

               ; V1.022.86: When inside a function, allocate LOCAL temp for recursion safety
               If gCodeGenFunction > 0
                  ; Allocate local temp offset
                  Protected localTempOffset.i = gCodeGenLocalIndex
                  gCodeGenLocalIndex + 1
                  ; Update nLocals in mapModules
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                        Break
                     EndIf
                  Next

                  ; Emit LFETCH to push local variable value to stack
                  AddElement(llObjects())
                  If localExprType & #C2FLAG_FLOAT
                     llObjects()\code = #ljLFETCHF
                  ElseIf localExprType & #C2FLAG_STR
                     llObjects()\code = #ljLFETCHS
                  Else
                     llObjects()\code = #ljLFETCH
                  EndIf
                  llObjects()\i = gVarMeta(identSlot)\paramOffset

                  ; Emit LSTORE to store to local temp
                  AddElement(llObjects())
                  If localExprType & #C2FLAG_FLOAT
                     llObjects()\code = #ljLSTOREF
                  ElseIf localExprType & #C2FLAG_STR
                     llObjects()\code = #ljLSTORES
                  Else
                     llObjects()\code = #ljLSTORE
                  EndIf
                  llObjects()\i = localTempOffset

                  ; Return negative value to signal local offset (< -1 to avoid conflict with STACK=-1)
                  ProcedureReturn -(localTempOffset + 2)
               EndIf

               ; V1.022.72: Global scope - use global temp (original behavior)
               Protected tempSlotType.i, tempPopOpcode.i
               If localExprType & #C2FLAG_FLOAT
                  tempSlotType = #ljFLOAT
                  tempPopOpcode = #ljPOPF
               ElseIf localExprType & #C2FLAG_STR
                  tempSlotType = #ljSTRING
                  tempPopOpcode = #ljPOPS
               Else
                  tempSlotType = #ljINT
                  tempPopOpcode = #ljPop
               EndIf
               Protected tempSlot.i = FetchVarOffset("$_idx_temp_" + Str(gnLastVariable), 0, tempSlotType)

               ; Emit appropriate LFETCH variant based on type
               AddElement(llObjects())
               If localExprType & #C2FLAG_FLOAT
                  llObjects()\code = #ljLFETCHF
               ElseIf localExprType & #C2FLAG_STR
                  llObjects()\code = #ljLFETCHS
               Else
                  llObjects()\code = #ljLFETCH
               EndIf
               llObjects()\i = gVarMeta(identSlot)\paramOffset

               ; V1.022.72: Pop to temp slot with type-specific opcode
               AddElement(llObjects())
               llObjects()\code = tempPopOpcode
               llObjects()\i = tempSlot

               ProcedureReturn tempSlot
            EndIf

            ; Global variable - return slot directly
            ProcedureReturn identSlot

         Case #ljINT
            ; Integer constant - get slot directly
            ProcedureReturn FetchVarOffset(*expr\value, 0, #ljINT)

         Case #ljFLOAT
            ; Float constant - get slot directly
            ProcedureReturn FetchVarOffset(*expr\value, 0, #ljFLOAT)

         Case #ljSTRING
            ; String constant - get slot directly
            ProcedureReturn FetchVarOffset(*expr\value, 0, #ljSTRING)

         ; V1.022.76: Removed #ljLeftBracket case - was causing array index corruption
         ; Float array POPF issue needs to be fixed elsewhere (in #ljIDENT case)

         Default
            ; V1.022.50: Complex expression - emit code to stack, then pop/store to temp
            ; V1.022.86: When inside function, use LOCAL temp for recursion safety
            ; V1.022.101: Detect expression result type to use correct store opcode
            Protected exprResultType.w = GetExprResultType(*expr)

            If gCodeGenFunction > 0
               ; Allocate local temp offset
               Protected complexLocalOffset.i = gCodeGenLocalIndex
               gCodeGenLocalIndex + 1
               ; Update nLocals in mapModules
               ForEach mapModules()
                  If mapModules()\function = gCodeGenFunction
                     mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                     Break
                  EndIf
               Next

               CodeGenerator(*expr)
               ; V1.022.101: Store result with type-correct opcode based on expression result type
               AddElement(llObjects())
               If exprResultType & #C2FLAG_FLOAT
                  llObjects()\code = #ljLSTOREF
                  CompilerIf #DEBUG
                     Debug "V1.022.101: Complex expr to LOCAL[" + Str(complexLocalOffset) + "] using LSTOREF (float)"
                  CompilerEndIf
               ElseIf exprResultType & #C2FLAG_STR
                  llObjects()\code = #ljLSTORES
                  CompilerIf #DEBUG
                     Debug "V1.022.101: Complex expr to LOCAL[" + Str(complexLocalOffset) + "] using LSTORES (string)"
                  CompilerEndIf
               Else
                  llObjects()\code = #ljLSTORE
               EndIf
               llObjects()\i = complexLocalOffset

               ; Return negative value to signal local offset (< -1 to avoid conflict with STACK=-1)
               ProcedureReturn -(complexLocalOffset + 2)
            EndIf

            ; Global scope - use global temp (original behavior)
            ; V1.022.101: Use appropriate type for temp slot and pop opcode
            Protected complexTempType.i, complexPopOpcode.i
            If exprResultType & #C2FLAG_FLOAT
               complexTempType = #ljFLOAT
               complexPopOpcode = #ljPOPF
            ElseIf exprResultType & #C2FLAG_STR
               complexTempType = #ljSTRING
               complexPopOpcode = #ljPOPS
            Else
               complexTempType = #ljINT
               complexPopOpcode = #ljPop
            EndIf
            Protected complexTempSlot.i = FetchVarOffset("$_idx_temp_" + Str(gnLastVariable), 0, complexTempType)
            CodeGenerator(*expr)
            ; Pop result to temp slot with type-correct opcode
            AddElement(llObjects())
            llObjects()\code = complexPopOpcode
            llObjects()\i = complexTempSlot
            ProcedureReturn complexTempSlot
      EndSelect
   EndProcedure

   ; Helper function to detect if an expression tree contains a function call
   Procedure.b          ContainsFunctionCall(*node.stTree)
      If Not *node
         ProcedureReturn #False
      EndIf

      If *node\NodeType = #ljCall
         ProcedureReturn #True
      EndIf

      ; Recursively check left and right subtrees
      If ContainsFunctionCall(*node\left)
         ProcedureReturn #True
      EndIf

      If ContainsFunctionCall(*node\right)
         ProcedureReturn #True
      EndIf

      ProcedureReturn #False
   EndProcedure

   ; Helper function to collect all variable references in an expression tree
   Procedure            CollectVariables(*node.stTree, List vars.s())
      If Not *node
         ProcedureReturn
      EndIf

      If *node\NodeType = #ljIDENT
         ; Add variable to list if not already there
         Protected found.b = #False
         ForEach vars()
            If vars() = *node\value
               found = #True
               Break
            EndIf
         Next
         If Not found
            AddElement(vars())
            vars() = *node\value
         EndIf
      EndIf

      CollectVariables(*node\left, vars())
      CollectVariables(*node\right, vars())
   EndProcedure

   Procedure            CodeGenerator( *x.stTree, *link.stTree = 0 )
      Protected         p1, p2, n, i
      Protected         *pJmp                 ; V1.18.54: Pointer to JMP instruction for while loops
      Protected         temp.s
      Protected         leftType.w
      Protected         rightType.w
      Protected         opType.w = #C2FLAG_INT
      Protected         negType.w = #C2FLAG_INT
      Protected         returnType.w
      Protected         funcId.i
      Protected         paramCount.i
      Protected         isReturnSeq.i
      Protected         *returnExpr.stTree
      Protected         isPointerArithmetic.i
      Protected         ptrVarOffset.i
      Protected         s.s, s2.s, existingTypeName.s
      Protected         isLiteral.i, literalValue.s, convertedIntVal.i, convertedFloatVal.d, constIdx.i, decimalPlaces.i
      Protected         hasExplicitTypeSuffix.i, explicitTypeFlag.w, varNameLower.s  ; V1.20.3: For PTRFETCH explicit typing
      Protected         explicitType.w  ; V1.20.6: Explicit type from variable suffix
      Protected         hasReturnType.b, callReturnType.w  ; V1.020.053: For unused return value handling
      Protected         funcPtrSlot.i = -1
      Protected         searchName.s = *x\value
      Protected         searchFuncId.i
      Protected         foundFunc.i = #False
      Protected         srcVarSlot.i               ; V1.022.54: For struct pointer type tracking

      ; Reset state on top-level call
      If gCodeGenRecursionDepth = 0
         gCodeGenParamIndex = -1
         gCodeGenFunction = 0
         gCodeGenLocalIndex = 0
         gCurrentFunctionName = ""
      EndIf
      gCodeGenRecursionDepth + 1

      ; If no node, return immediately
      If Not *x
         gCodeGenRecursionDepth - 1
         ProcedureReturn
      EndIf

      ; V1.023.26: If error already occurred, stop generating code
      If gLastError
         gCodeGenRecursionDepth - 1
         ProcedureReturn 1
      EndIf

      ;Debug gszATR( *x\NodeType )\s + " --> " + *x\value
      
      Select *x\NodeType
         Case #ljEOF
            gCodeGenRecursionDepth - 1
            ProcedureReturn
         Case #ljPOP
            ; Check if this is a direct slot reference (for ?discard? slot 0)
            If *x\value = "0"
               n = 0  ; Use reserved slot 0 directly
               EmitInt( #ljPOP, 0 )  ; Always emit as global INT
            Else
               n = FetchVarOffset(*x\value)

               ; Check if this is a function parameter
               If gCodeGenParamIndex >= 0
                  ; This is a function parameter - mark it and don't emit POP
                  ; IMPORTANT: Clear existing type flags before setting parameter type
                  ; Parameters may have been created by FetchVarOffset with wrong inferred types
                  gVarMeta( n )\flags = (gVarMeta( n )\flags & ~#C2FLAG_TYPE) | #C2FLAG_PARAM

                  ; V1.022.31: Fix parameter offset calculation
                  ; Parameters are pushed in order (arr_slot, left, right) by caller
                  ; AST processes them in reverse (right first, arr_slot last)
                  ; LOCAL[0] = last pushed (right), LOCAL[N-1] = first pushed
                  ; So: first processed (right) needs offset 0, last processed needs offset N-1
                  ; Formula: paramOffset = (nParams - 1) - gCodeGenParamIndex
                  ;        = (gCodeGenLocalIndex - 1) - gCodeGenParamIndex
                  gVarMeta( n )\paramOffset = (gCodeGenLocalIndex - 1) - gCodeGenParamIndex

                  ; Set type flags (type bits already cleared above)
                  If *x\typeHint = #ljFLOAT
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_FLOAT
                  ElseIf *x\typeHint = #ljSTRING
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_STR
                  Else
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_INT
                  EndIf

                  ; Decrement parameter index (parameters processed in reverse, last to first)
                  gCodeGenParamIndex - 1

                  ; Note: We DON'T emit POP - parameters stay on stack
               ElseIf gCurrentFunctionName <> ""
                  ; Local variable inside a function - assign offset and emit POP
                  gVarMeta( n )\paramOffset = gCodeGenLocalIndex
                  gCodeGenLocalIndex + 1  ; Increment for next local

                  ; Update nLocals in mapModules immediately
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                        Break
                     EndIf
                  Next

                  ; Set type flags
                  If *x\typeHint = #ljFLOAT
                     EmitInt( #ljPOPF, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
                  ElseIf *x\typeHint = #ljSTRING
                     EmitInt( #ljPOPS, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_STR
                  Else
                     EmitInt( #ljPOP, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_INT
                  EndIf
               Else
                  ; Global variable - emit POP as usual
                  If *x\typeHint = #ljFLOAT
                     EmitInt( #ljPOPF, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
                  ElseIf *x\typeHint = #ljSTRING
                     EmitInt( #ljPOPS, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_STR
                  Else
                     EmitInt( #ljPOP, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_INT
                  EndIf
               EndIf
            EndIf
         
         Case #ljIDENT
            n = FetchVarOffset(*x\value)
            ; Emit appropriate FETCH variant based on variable type
            If gVarMeta(n)\flags & #C2FLAG_STR
               EmitInt( #ljFETCHS, n )
            ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
               EmitInt( #ljFETCHF, n )
            Else
               EmitInt( #ljFetch, n )
            EndIf
            gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT

         ; V1.20.21: Pointer field access (ptr\i, ptr\f, ptr\s)
         ; V1.20.22: Can be either simple variable (leaf) or array element (node with left child)
         Case #ljPTRFIELD_I
            If *x\left
               ; Array element pointer field: arr[i]\i
               CodeGenerator( *x\left )  ; Generate array access (leaves pointer on stack)
            Else
               ; Simple variable pointer field: ptr\i
               n = FetchVarOffset(*x\value)
               EmitInt( #ljFetch, n )    ; Fetch pointer variable
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT
            EndIf
            EmitInt( #ljPTRFETCH_INT )   ; Dereference as integer

         Case #ljPTRFIELD_F
            If *x\left
               ; Array element pointer field: arr[i]\f
               CodeGenerator( *x\left )  ; Generate array access (leaves pointer on stack)
            Else
               ; Simple variable pointer field: ptr\f
               n = FetchVarOffset(*x\value)
               EmitInt( #ljFetch, n )    ; Fetch pointer variable
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT
            EndIf
            EmitInt( #ljPTRFETCH_FLOAT ) ; Dereference as float

         Case #ljPTRFIELD_S
            If *x\left
               ; Array element pointer field: arr[i]\s
               CodeGenerator( *x\left )  ; Generate array access (leaves pointer on stack)
            Else
               ; Simple variable pointer field: ptr\s
               n = FetchVarOffset(*x\value)
               EmitInt( #ljFetch, n )    ; Fetch pointer variable
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT
            EndIf
            EmitInt( #ljPTRFETCH_STR )   ; Dereference as string

         ; V1.022.45: Struct array field access (arr[i]\field)
         ; *x\left = array access node (#ljLeftBracket)
         ; *x\value = "elementSize|fieldOffset" (encoded as pipe-delimited string)
         Case #nd_StructArrayField_I, #nd_StructArrayField_F, #nd_StructArrayField_S
            If *x\left And *x\left\NodeType = #ljLeftBracket And *x\left\left
               ; Get array base slot
               Protected aosArraySlot.i = FetchVarOffset(*x\left\left\value)
               Protected aosIsLocal.i = 0
               If gVarMeta(aosArraySlot)\paramOffset >= 0
                  aosIsLocal = 1
               EndIf

               ; V1.022.45: Parse elementSize|fieldOffset from value field
               Protected aosElementSize.i = Val(StringField(*x\value, 1, "|"))
               Protected aosFieldOffset.i = Val(StringField(*x\value, 2, "|"))

               ; Get index expression slot
               Protected aosIndexSlot.i = GetExprSlotOrTemp(*x\left\right)

               ; Select opcode based on field type
               Protected aosOpcode.i
               Select *x\NodeType
                  Case #nd_StructArrayField_I
                     aosOpcode = #ljARRAYOFSTRUCT_FETCH_INT
                  Case #nd_StructArrayField_F
                     aosOpcode = #ljARRAYOFSTRUCT_FETCH_FLOAT
                  Case #nd_StructArrayField_S
                     aosOpcode = #ljARRAYOFSTRUCT_FETCH_STR
               EndSelect

               ; Emit opcode with: i=arraySlot, j=elementSize, n=fieldOffset, ndx=indexSlot
               EmitInt(aosOpcode, aosArraySlot)
               llObjects()\j = aosElementSize
               llObjects()\n = aosFieldOffset
               llObjects()\ndx = aosIndexSlot
               If aosIsLocal
                  llObjects()\funcid = 1  ; Use funcid as local flag
               EndIf

            EndIf

         Case #ljINT, #ljFLOAT, #ljSTRING
            n = FetchVarOffset( *x\value, 0, *x\NodeType )
            EmitInt( #ljPush, n )

         Case #ljLeftBracket
            ; Array indexing: arr[index]
            ; *x\left = array variable (ljIDENT)
            ; *x\right = index expression
            ; V1.022.21: Slot-only optimization - no stack ops for simple index expressions

            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; V1.022.21: Get slot for index (may emit code for complex expressions)
               Protected arrayFetchIndexSlot.i
               arrayFetchIndexSlot = GetExprSlotOrTemp(*x\right)

               ; Determine if array is local or global at compile time
               Protected isLocal.i, arrayIndex.i
               isLocal = 0
               arrayIndex = n  ; Default to global varSlot

               If gVarMeta(n)\paramOffset >= 0
                  ; V1.18.0: Local array - use paramOffset for unified gVar[] slot calculation
                  isLocal = 1
                  arrayIndex = gVarMeta(n)\paramOffset
               EndIf

               ; V1.022.22: Emit typed ARRAYFETCH directly (skip postprocessor typing)
               ; Determine type from array metadata
               Protected arrayFetchOpcode.i
               If gVarMeta(n)\flags & #C2FLAG_STR
                  arrayFetchOpcode = #ljARRAYFETCH_STR
               ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                  arrayFetchOpcode = #ljARRAYFETCH_FLOAT
               Else
                  arrayFetchOpcode = #ljARRAYFETCH_INT
               EndIf

               EmitInt( arrayFetchOpcode, arrayIndex )
               ; Encode local/global in j field: 0=global, 1=local
               llObjects()\j = isLocal
               ; ndx = index slot (direct slot ref, no stack)
               llObjects()\ndx = arrayFetchIndexSlot
            EndIf

         Case #ljSTRUCTARRAY_FETCH_INT, #ljSTRUCTARRAY_FETCH_FLOAT, #ljSTRUCTARRAY_FETCH_STR
            ; V1.022.0: Struct array field fetch - gVar[baseSlot + index]
            ; V1.022.2: Support local and global structs
            ; V1.022.20: Slot-only optimization
            ; *x\left = index expression
            ; *x\value = "structVarSlot|fieldOffset|fieldName"

            ; Parse value to get struct info
            Protected sarParts.s = *x\value
            Protected sarStructSlot.i = Val(StringField(sarParts, 1, "|"))
            Protected sarFieldOffset.i = Val(StringField(sarParts, 2, "|"))
            Protected sarIsLocal.i = 0
            Protected sarBaseSlot.i
            Protected sarIndexSlot.i

            ; Check if struct is local (has paramOffset >= 0)
            If gVarMeta(sarStructSlot)\paramOffset >= 0
               sarIsLocal = 1
               ; For local: base is paramOffset + fieldOffset
               sarBaseSlot = gVarMeta(sarStructSlot)\paramOffset + sarFieldOffset
            Else
               ; For global: base is structVarSlot + fieldOffset
               sarBaseSlot = sarStructSlot + sarFieldOffset
            EndIf

            ; V1.022.20: Get slot for index (may emit code for complex expressions)
            sarIndexSlot = GetExprSlotOrTemp(*x\left)

            ; Emit struct array fetch opcode with direct slot reference
            EmitInt( *x\NodeType, sarBaseSlot )
            ; j = 0 for global, 1 for local
            llObjects()\j = sarIsLocal
            ; ndx = index slot (direct slot ref, no stack)
            llObjects()\ndx = sarIndexSlot

         Case #ljSTRUCTARRAY_STORE_INT, #ljSTRUCTARRAY_STORE_FLOAT, #ljSTRUCTARRAY_STORE_STR
            ; V1.022.4: Direct struct array field store (standalone statement)
            ; V1.022.20: Slot-only optimization - no stack ops for simple expressions
            ; *x\left = index expression
            ; *x\right = value expression
            ; *x\value = "structVarSlot|fieldOffset|fieldName"

            ; Parse value to get struct info
            Protected sasDirectParts.s = *x\value
            Protected sasDirectStructSlot.i = Val(StringField(sasDirectParts, 1, "|"))
            Protected sasDirectFieldOffset.i = Val(StringField(sasDirectParts, 2, "|"))
            Protected sasDirectIsLocal.i = 0
            Protected sasDirectBaseSlot.i
            Protected sasDirectValueSlot.i
            Protected sasDirectIndexSlot.i

            ; Check if struct is local (has paramOffset >= 0)
            If gVarMeta(sasDirectStructSlot)\paramOffset >= 0
               sasDirectIsLocal = 1
               ; For local: base is paramOffset + fieldOffset
               sasDirectBaseSlot = gVarMeta(sasDirectStructSlot)\paramOffset + sasDirectFieldOffset
            Else
               ; For global: base is structVarSlot + fieldOffset
               sasDirectBaseSlot = sasDirectStructSlot + sasDirectFieldOffset
            EndIf

            ; V1.022.20: Get slots for value and index (may emit code for complex expressions)
            ; Value first, then index (preserves evaluation order)
            sasDirectValueSlot = GetExprSlotOrTemp(*x\right)
            sasDirectIndexSlot = GetExprSlotOrTemp(*x\left)

            ; Emit struct array store opcode with direct slot references
            EmitInt( *x\NodeType, sasDirectBaseSlot )
            ; j = 0 for global, 1 for local
            llObjects()\j = sasDirectIsLocal
            ; ndx = index slot, n = value slot (direct slot refs, no stack)
            llObjects()\ndx = sasDirectIndexSlot
            llObjects()\n = sasDirectValueSlot

         Case #ljPTRSTRUCTFETCH_INT, #ljPTRSTRUCTFETCH_FLOAT, #ljPTRSTRUCTFETCH_STR
            ; V1.022.54: Struct pointer field fetch - ptr\field
            ; V1.022.55: Handle both resolved ("ptrVarSlot|fieldOffset") and deferred ("identName|fieldName") formats
            Protected psfParts.s = *x\value
            Protected psfField1.s = StringField(psfParts, 1, "|")
            Protected psfField2.s = StringField(psfParts, 2, "|")
            Protected psfPtrSlot.i
            Protected psfFieldOffset.i
            Protected psfActualNodeType.i = *x\NodeType

            ; Check if first field is numeric (resolved) or identifier (deferred)
            ; V1.023.13: Changed condition - slot "0" should use deferred path since slot 0 is reserved
            If Val(psfField1) > 0
               ; Resolved format: "ptrVarSlot|fieldOffset"
               psfPtrSlot = Val(psfField1)
               psfFieldOffset = Val(psfField2)
            Else
               ; Deferred format: "identName|fieldName" - resolve now
               Protected psfIdentName.s = psfField1
               Protected psfFieldName.s = psfField2
               Protected psfVarIdx.i

               ; V1.022.120: Find the variable - search LOCAL (mangled) name FIRST, then global
               ; This matches FetchVarOffset behavior and ensures local variables are found
               psfPtrSlot = -1
               Protected psfIsLocalPtr.i = #False
               Protected psfMetaSlot.i = -1
               Protected psfMangledName.s = ""
               Protected psfFuncName.s = gCurrentFunctionName

               ; V1.023.11: Recover function context if gCurrentFunctionName is empty but we're in a function
               If psfFuncName = "" And gCodeGenFunction >= #C2FUNCSTART
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        psfFuncName = MapKey(mapModules())
                        Break
                     EndIf
                  Next
               EndIf

               ; V1.022.123: First search for local (mangled) variable if inside a function
               ; Skip slot 0 (reserved for ?discard?)
               If psfFuncName <> ""
                  psfMangledName = psfFuncName + "_" + psfIdentName
                  For psfVarIdx = 1 To gnLastVariable - 1
                     If LCase(gVarMeta(psfVarIdx)\name) = LCase(psfMangledName)
                        psfPtrSlot = psfVarIdx
                        psfMetaSlot = psfVarIdx
                        psfIsLocalPtr = #True
                        Break
                     EndIf
                  Next
               EndIf

               ; V1.022.123: If not found as local, search for global variable (skip slot 0)
               If psfPtrSlot < 0
                  For psfVarIdx = 1 To gnLastVariable - 1
                     If LCase(gVarMeta(psfVarIdx)\name) = LCase(psfIdentName)
                        psfPtrSlot = psfVarIdx
                        psfMetaSlot = psfVarIdx
                        ; psfIsLocalPtr stays FALSE for global variables
                        Break
                     EndIf
                  Next
               EndIf

               If psfPtrSlot < 0
                  SetError("Variable '" + psfIdentName + "' not found for struct pointer access", #C2ERR_CODEGEN_FAILED)
                  ProcedureReturn
               EndIf

               ; V1.022.123: Encode local pointer as < -1 for postprocessor
               ; Must do AFTER error check but BEFORE using for opcode emission
               If psfIsLocalPtr
                  ; V1.022.123: Validate paramOffset before encoding
                  If gVarMeta(psfMetaSlot)\paramOffset < 0
                     ; paramOffset not set - assign a local slot
                     gVarMeta(psfMetaSlot)\paramOffset = gCodeGenLocalIndex
                     gCodeGenLocalIndex + 1
                     ForEach mapModules()
                        If mapModules()\function = gCodeGenFunction
                           mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                           Break
                        EndIf
                     Next
                  EndIf
                  psfPtrSlot = -(gVarMeta(psfMetaSlot)\paramOffset + 2)
               EndIf

               ; Get struct type from pointer (use saved metaSlot, not encoded psfPtrSlot)
               Protected psfStructType.s = gVarMeta(psfMetaSlot)\pointsToStructType
               If psfStructType = ""
                  SetError("Variable '" + psfIdentName + "' is not a struct pointer", #C2ERR_CODEGEN_FAILED)
                  ProcedureReturn
               EndIf

               ; Look up field in struct type
               psfFieldOffset = -1
               If FindMapElement(mapStructDefs(), psfStructType)
                  ForEach mapStructDefs()\fields()
                     If LCase(mapStructDefs()\fields()\name) = LCase(psfFieldName)
                        psfFieldOffset = mapStructDefs()\fields()\offset
                        ; Determine correct node type based on field type
                        If mapStructDefs()\fields()\fieldType & #C2FLAG_FLOAT
                           psfActualNodeType = #ljPTRSTRUCTFETCH_FLOAT
                        ElseIf mapStructDefs()\fields()\fieldType & #C2FLAG_STR
                           psfActualNodeType = #ljPTRSTRUCTFETCH_STR
                        Else
                           psfActualNodeType = #ljPTRSTRUCTFETCH_INT
                        EndIf
                        Break
                     EndIf
                  Next
               EndIf

               If psfFieldOffset < 0
                  SetError("Field '" + psfFieldName + "' not found in struct '" + psfStructType + "'", #C2ERR_CODEGEN_FAILED)
                  ProcedureReturn
               EndIf
            EndIf

            ; Emit opcode: i=ptrVarSlot, n=fieldOffset
            EmitInt(psfActualNodeType, psfPtrSlot)
            llObjects()\n = psfFieldOffset


         Case #ljASSIGN
            ; V1.20.21: Check if left side is pointer field access (ptr\i, ptr\f, ptr\s)
            ; V1.20.22: Can be simple variable or array element
            If *x\left And (*x\left\NodeType = #ljPTRFIELD_I Or *x\left\NodeType = #ljPTRFIELD_F Or *x\left\NodeType = #ljPTRFIELD_S)
               ; Pointer field store: ptr\i = value, arr[i]\f = value, etc.
               ; *x\left\left = array access node (if array element) OR null (if simple var)
               ; *x\left\value = pointer variable name (if simple var)
               ; *x\right = value expression
               ; Emit value first, then pointer expression, then typed PTRSTORE

               CodeGenerator( *x\right )  ; Push value to stack

               If *x\left\left
                  ; Array element pointer field: arr[i]\i = value
                  CodeGenerator( *x\left\left )  ; Generate array access (leaves pointer on stack)
               Else
                  ; Simple variable pointer field: ptr\i = value
                  n = FetchVarOffset(*x\left\value)
                  EmitInt( #ljFetch, n )         ; Fetch pointer variable
               EndIf

               ; Emit typed PTRSTORE based on field type
               Select *x\left\NodeType
                  Case #ljPTRFIELD_I
                     EmitInt( #ljPTRSTORE_INT )    ; Store integer through pointer
                  Case #ljPTRFIELD_F
                     EmitInt( #ljPTRSTORE_FLOAT )  ; Store float through pointer
                  Case #ljPTRFIELD_S
                     EmitInt( #ljPTRSTORE_STR )    ; Store string through pointer
               EndSelect

            ; V1.022.54: Check if left side is struct pointer field (ptr\fieldName)
            ElseIf *x\left And (*x\left\NodeType = #ljPTRSTRUCTFETCH_INT Or *x\left\NodeType = #ljPTRSTRUCTFETCH_FLOAT Or *x\left\NodeType = #ljPTRSTRUCTFETCH_STR)
               ; Struct pointer field store: ptr\field = value
               ; V1.022.55: Handle both resolved ("ptrVarSlot|fieldOffset") and deferred ("identName|fieldName") formats
               ; *x\left\value = "ptrVarSlot|fieldOffset" or "identName|fieldName"
               ; *x\right = value expression
               Protected pssaParts.s = *x\left\value
               Protected pssaField1.s = StringField(pssaParts, 1, "|")
               Protected pssaField2.s = StringField(pssaParts, 2, "|")
               Protected pssaPtrSlot.i
               Protected pssaFieldOffset.i
               Protected pssaValueSlot.i
               Protected pssaStoreOp.i

               ; Check if first field is numeric (resolved) or identifier (deferred)
               ; V1.023.13: Changed condition - slot "0" should use deferred path since slot 0 is reserved
               If Val(pssaField1) > 0
                  ; Resolved format: "ptrVarSlot|fieldOffset"
                  pssaPtrSlot = Val(pssaField1)
                  pssaFieldOffset = Val(pssaField2)
                  ; Use node type from AST
                  Select *x\left\NodeType
                     Case #ljPTRSTRUCTFETCH_INT
                        pssaStoreOp = #ljPTRSTRUCTSTORE_INT
                     Case #ljPTRSTRUCTFETCH_FLOAT
                        pssaStoreOp = #ljPTRSTRUCTSTORE_FLOAT
                     Case #ljPTRSTRUCTFETCH_STR
                        pssaStoreOp = #ljPTRSTRUCTSTORE_STR
                  EndSelect
               Else
                  ; Deferred format: "identName|fieldName" - resolve now
                  Protected pssaIdentName.s = pssaField1
                  Protected pssaFieldName.s = pssaField2
                  Protected pssaVarIdx.i

                  ; V1.022.120: Find the variable - search LOCAL (mangled) name FIRST, then global
                  ; This matches FetchVarOffset behavior and ensures local variables are found
                  pssaPtrSlot = -1
                  Protected pssaIsLocalPtr.i = #False
                  Protected pssaMetaSlot.i = -1
                  Protected pssaMangledName.s = ""
                  Protected pssaFuncName.s = gCurrentFunctionName

                  ; V1.023.11: Recover function context if gCurrentFunctionName is empty but we're in a function
                  ; This can happen when function context wasn't properly propagated during codegen
                  If pssaFuncName = "" And gCodeGenFunction >= #C2FUNCSTART
                     ForEach mapModules()
                        If mapModules()\function = gCodeGenFunction
                           pssaFuncName = MapKey(mapModules())
                           Break
                        EndIf
                     Next
                  EndIf

                  ; V1.022.123: First search for local (mangled) variable if inside a function
                  ; Skip slot 0 (reserved for ?discard?)
                  If pssaFuncName <> ""
                     pssaMangledName = pssaFuncName + "_" + pssaIdentName
                     For pssaVarIdx = 1 To gnLastVariable - 1
                        If LCase(gVarMeta(pssaVarIdx)\name) = LCase(pssaMangledName)
                           pssaPtrSlot = pssaVarIdx
                           pssaMetaSlot = pssaVarIdx
                           pssaIsLocalPtr = #True
                           Break
                        EndIf
                     Next
                  EndIf

                  ; V1.022.123: If not found as local, search for global variable (skip slot 0)
                  If pssaPtrSlot < 0
                     For pssaVarIdx = 1 To gnLastVariable - 1
                        If LCase(gVarMeta(pssaVarIdx)\name) = LCase(pssaIdentName)
                           pssaPtrSlot = pssaVarIdx
                           pssaMetaSlot = pssaVarIdx
                           ; pssaIsLocalPtr stays FALSE for global variables
                           Break
                        EndIf
                     Next
                  EndIf

                  If pssaPtrSlot < 0
                     SetError("Variable '" + pssaIdentName + "' not found for struct pointer store", #C2ERR_CODEGEN_FAILED)
                     ProcedureReturn
                  EndIf

                  ; V1.022.123: Encode local pointer as < -1 for postprocessor
                  ; Must do AFTER error check but BEFORE using for opcode emission
                  If pssaIsLocalPtr
                     ; V1.022.123: Validate paramOffset before encoding
                     ; paramOffset must be >= 0 for local variables (set by FetchVarOffset)
                     ; If it's -1 (default/uninitialized), the encoding would produce -1 (STACK)
                     ; which is incorrect. Force a proper local offset by checking and fixing.
                     If gVarMeta(pssaMetaSlot)\paramOffset < 0
                        ; paramOffset not set - this local variable needs an offset assigned
                        ; This can happen if the variable was registered but not yet assigned a local slot
                        gVarMeta(pssaMetaSlot)\paramOffset = gCodeGenLocalIndex
                        gCodeGenLocalIndex + 1
                        ; Update nLocals in mapModules
                        ForEach mapModules()
                           If mapModules()\function = gCodeGenFunction
                              mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                              Break
                           EndIf
                        Next
                     EndIf
                     pssaPtrSlot = -(gVarMeta(pssaMetaSlot)\paramOffset + 2)
                  EndIf

                  ; Get struct type from pointer (use saved metaSlot, not encoded pssaPtrSlot)
                  Protected pssaStructType.s = gVarMeta(pssaMetaSlot)\pointsToStructType
                  If pssaStructType = ""
                     SetError("Variable '" + pssaIdentName + "' is not a struct pointer", #C2ERR_CODEGEN_FAILED)
                     ProcedureReturn
                  EndIf

                  ; Look up field in struct type
                  pssaFieldOffset = -1
                  If FindMapElement(mapStructDefs(), pssaStructType)
                     ForEach mapStructDefs()\fields()
                        If LCase(mapStructDefs()\fields()\name) = LCase(pssaFieldName)
                           pssaFieldOffset = mapStructDefs()\fields()\offset
                           ; Determine correct store opcode based on field type
                           If mapStructDefs()\fields()\fieldType & #C2FLAG_FLOAT
                              pssaStoreOp = #ljPTRSTRUCTSTORE_FLOAT
                           ElseIf mapStructDefs()\fields()\fieldType & #C2FLAG_STR
                              pssaStoreOp = #ljPTRSTRUCTSTORE_STR
                           Else
                              pssaStoreOp = #ljPTRSTRUCTSTORE_INT
                           EndIf
                           Break
                        EndIf
                     Next
                  EndIf

                  If pssaFieldOffset < 0
                     SetError("Field '" + pssaFieldName + "' not found in struct '" + pssaStructType + "'", #C2ERR_CODEGEN_FAILED)
                     ProcedureReturn
                  EndIf
               EndIf

               ; Get value slot (may emit code for complex expressions)
               pssaValueSlot = GetExprSlotOrTemp(*x\right)

               ; Emit opcode: i=ptrVarSlot, n=fieldOffset, ndx=valueSlot
               Debug "PTRSTRUCTSTORE EMIT: pssaStoreOp=" + Str(pssaStoreOp) + " pssaPtrSlot=" + Str(pssaPtrSlot) + " pssaFieldOffset=" + Str(pssaFieldOffset) + " pssaValueSlot=" + Str(pssaValueSlot)
               EmitInt(pssaStoreOp, pssaPtrSlot)
               llObjects()\n = pssaFieldOffset
               llObjects()\ndx = pssaValueSlot


            ; Check if left side is pointer dereference
            ElseIf *x\left And *x\left\NodeType = #ljPTRFETCH
               ; V1.022.61: Check if this is NEW pointer variable definition vs existing dereference
               ; *ptr = &something where ptr is NEW -> pointer definition, use STORE
               ; *ptr = value where ptr EXISTS -> dereference assignment, use PTRSTORE
               Protected ptrDefVarName.s, ptrDefIsNew.i, ptrDefSlot.i
               ptrDefVarName = ""
               ptrDefIsNew = #True

               If *x\left\left And *x\left\left\NodeType = #ljIDENT
                  ptrDefVarName = *x\left\left\value

                  ; Check if variable already exists in symbol table
                  ; Must account for function scope name mangling (same logic as FetchVarOffset)
                  Protected ptrDefMangledName.s

                  ; First check for local variable (mangled name) if inside a function
                  If gCurrentFunctionName <> ""
                     ptrDefMangledName = gCurrentFunctionName + "_" + ptrDefVarName
                     For i = 0 To gnLastVariable - 1
                        If LCase(gVarMeta(i)\name) = LCase(ptrDefMangledName)
                           ptrDefIsNew = #False
                           ptrDefSlot = i
                           Break
                        EndIf
                     Next
                  EndIf

                  ; If not found as local, check for global with raw name
                  If ptrDefIsNew
                     For i = 0 To gnLastVariable - 1
                        If LCase(gVarMeta(i)\name) = LCase(ptrDefVarName)
                           ptrDefIsNew = #False
                           ptrDefSlot = i
                           Break
                        EndIf
                     Next
                  EndIf
               EndIf

               If ptrDefIsNew And ptrDefVarName <> ""
                  ; NEW pointer variable definition: *ptr = &something
                  ; Create variable and store directly (not through dereference)

                  ; Create the pointer variable
                  ptrDefSlot = FetchVarOffset(ptrDefVarName)

                  ; Mark as pointer type
                  gVarMeta(ptrDefSlot)\flags = gVarMeta(ptrDefSlot)\flags | #C2FLAG_POINTER | #C2FLAG_INT

                  ; V1.022.63: Check if RHS is address-of a struct, propagate struct type
                  ; This enables ptr\field syntax to work
                  If *x\right And *x\right\NodeType = #ljGETADDR
                     If *x\right\left And *x\right\left\NodeType = #ljIDENT
                        Protected ptrDefSrcSlot.i = FetchVarOffset(*x\right\left\value)
                        If ptrDefSrcSlot >= 0 And ptrDefSrcSlot < ArraySize(gVarMeta())
                           If gVarMeta(ptrDefSrcSlot)\structType <> ""
                              ; Source is a struct - copy struct type to pointer metadata
                              gVarMeta(ptrDefSlot)\pointsToStructType = gVarMeta(ptrDefSrcSlot)\structType
                           EndIf
                        EndIf
                     EndIf
                  EndIf

                  ; Generate RHS (the address/value)
                  CodeGenerator( *x\right )

                  ; Emit STORE - postprocessor will upgrade to PSTORE if needed
                  EmitInt( #ljStore, ptrDefSlot )
               Else
                  ; EXISTING pointer variable: *ptr = value (dereference and store)
                  ; *x\left\left = pointer expression
                  ; *x\right = value expression
                  ; Emit value first, then pointer expression, then PTRSTORE

                  CodeGenerator( *x\right )  ; Push value to stack
                  CodeGenerator( *x\left\left )  ; Push pointer (slot index) to stack
                  EmitInt( #ljPTRSTORE )  ; Generic pointer store
               EndIf

            ; Check if left side is array indexing
            ; V1.022.21: Slot-only optimization - no stack ops for simple expressions
            ElseIf *x\left And *x\left\NodeType = #ljLeftBracket
               ; Array assignment: arr[index] = value
               ; *x\left\left = array variable
               ; *x\left\right = index expression
               ; *x\right = value expression

               n = FetchVarOffset(*x\left\left\value)

               ; V1.022.21: Get slots for value and index (may emit code for complex expressions)
               ; Value first, then index (preserves evaluation order)
               Protected arrayStoreValueSlot.i
               Protected arrayStoreIndexSlot.i
               arrayStoreValueSlot = GetExprSlotOrTemp(*x\right)
               arrayStoreIndexSlot = GetExprSlotOrTemp(*x\left\right)

               ; Determine if array is local or global at compile time
               Protected isLocalStore.i, arrayIndexStore.i
               isLocalStore = 0
               arrayIndexStore = n  ; Default to global varSlot

               If gVarMeta(n)\paramOffset >= 0
                  ; V1.18.0: Local array - use paramOffset for unified gVar[] slot calculation
                  isLocalStore = 1
                  arrayIndexStore = gVarMeta(n)\paramOffset
               EndIf

               ; V1.022.22: Emit typed ARRAYSTORE directly (skip postprocessor typing)
               ; Determine type from array metadata
               Protected arrayStoreOpcode.i
               If gVarMeta(n)\flags & #C2FLAG_STR
                  arrayStoreOpcode = #ljARRAYSTORE_STR
               ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                  arrayStoreOpcode = #ljARRAYSTORE_FLOAT
               Else
                  arrayStoreOpcode = #ljARRAYSTORE_INT
               EndIf

               EmitInt( arrayStoreOpcode, arrayIndexStore )
               ; Encode local/global in j field: 0=global, 1=local
               llObjects()\j = isLocalStore
               ; ndx = index slot (direct slot ref, no stack)
               llObjects()\ndx = arrayStoreIndexSlot
               ; n = value slot (direct slot ref, no stack)
               llObjects()\n = arrayStoreValueSlot

            ; V1.022.0: Check if left side is struct array field access
            ; V1.022.2: Support local and global structs
            ; V1.022.20: Slot-only optimization
            ElseIf *x\left And (*x\left\NodeType = #ljSTRUCTARRAY_FETCH_INT Or *x\left\NodeType = #ljSTRUCTARRAY_FETCH_FLOAT Or *x\left\NodeType = #ljSTRUCTARRAY_FETCH_STR)
               ; Struct array field store: s\arr[i] = value
               ; *x\left\left = index expression
               ; *x\left\value = "structVarSlot|fieldOffset|fieldName"
               ; *x\right = value expression

               ; Parse value to get struct info
               Protected sasPartsStore.s = *x\left\value
               Protected sasStructSlotStore.i = Val(StringField(sasPartsStore, 1, "|"))
               Protected sasFieldOffsetStore.i = Val(StringField(sasPartsStore, 2, "|"))
               Protected sasIsLocalStore.i = 0
               Protected sasBaseSlotStore.i
               Protected sasValueSlotStore.i
               Protected sasIndexSlotStore.i

               ; Check if struct is local (has paramOffset >= 0)
               If gVarMeta(sasStructSlotStore)\paramOffset >= 0
                  sasIsLocalStore = 1
                  ; For local: base is paramOffset + fieldOffset
                  sasBaseSlotStore = gVarMeta(sasStructSlotStore)\paramOffset + sasFieldOffsetStore
               Else
                  ; For global: base is structVarSlot + fieldOffset
                  sasBaseSlotStore = sasStructSlotStore + sasFieldOffsetStore
               EndIf

               ; V1.022.20: Get slots for value and index (may emit code for complex expressions)
               ; Value first, then index (preserves evaluation order)
               sasValueSlotStore = GetExprSlotOrTemp(*x\right)
               sasIndexSlotStore = GetExprSlotOrTemp(*x\left\left)

               ; Choose store opcode based on fetch type
               Protected structStoreOp.i
               Select *x\left\NodeType
                  Case #ljSTRUCTARRAY_FETCH_INT
                     structStoreOp = #ljSTRUCTARRAY_STORE_INT
                  Case #ljSTRUCTARRAY_FETCH_FLOAT
                     structStoreOp = #ljSTRUCTARRAY_STORE_FLOAT
                  Case #ljSTRUCTARRAY_FETCH_STR
                     structStoreOp = #ljSTRUCTARRAY_STORE_STR
               EndSelect

               ; Emit struct array store opcode with direct slot references
               EmitInt( structStoreOp, sasBaseSlotStore )
               ; j = 0 for global, 1 for local
               llObjects()\j = sasIsLocalStore
               ; ndx = index slot, n = value slot (direct slot refs, no stack)
               llObjects()\ndx = sasIndexSlotStore
               llObjects()\n = sasValueSlotStore

            ; V1.022.45: Array of structs field store: points[i]\x = value
            ElseIf *x\left And (*x\left\NodeType = #nd_StructArrayField_I Or *x\left\NodeType = #nd_StructArrayField_F Or *x\left\NodeType = #nd_StructArrayField_S)
               ; Array of structs assignment: points[i]\field = value
               ; *x\left\left = array access node (#ljLeftBracket)
               ; *x\left\left\left = array variable (#ljIDENT)
               ; *x\left\left\right = index expression
               ; *x\left\value = "elementSize|fieldOffset" (encoded)
               ; *x\right = value expression

               If *x\left\left And *x\left\left\NodeType = #ljLeftBracket And *x\left\left\left
                  ; Get array base slot
                  Protected aosStoreArraySlot.i = FetchVarOffset(*x\left\left\left\value)
                  Protected aosStoreIsLocal.i = 0
                  If gVarMeta(aosStoreArraySlot)\paramOffset >= 0
                     aosStoreIsLocal = 1
                  EndIf

                  ; V1.022.45: Parse elementSize|fieldOffset from value field
                  Protected aosStoreElementSize.i = Val(StringField(*x\left\value, 1, "|"))
                  Protected aosStoreFieldOffset.i = Val(StringField(*x\left\value, 2, "|"))

                  ; V1.022.45: Generate code to push value to stack first
                  CodeGenerator(*x\right)

                  ; Get slot for index expression (may emit code for complex expressions)
                  Protected aosStoreIndexSlot.i = GetExprSlotOrTemp(*x\left\left\right)

                  ; Select store opcode based on field type
                  Protected aosStoreOpcode.i
                  Select *x\left\NodeType
                     Case #nd_StructArrayField_I
                        aosStoreOpcode = #ljARRAYOFSTRUCT_STORE_INT
                     Case #nd_StructArrayField_F
                        aosStoreOpcode = #ljARRAYOFSTRUCT_STORE_FLOAT
                     Case #nd_StructArrayField_S
                        aosStoreOpcode = #ljARRAYOFSTRUCT_STORE_STR
                  EndSelect

                  ; Emit opcode with: i=arraySlot, j=elementSize, n=fieldOffset, ndx=indexSlot
                  ; Value is on stack (will be popped by VM)
                  EmitInt(aosStoreOpcode, aosStoreArraySlot)
                  llObjects()\j = aosStoreElementSize
                  llObjects()\n = aosStoreFieldOffset
                  llObjects()\ndx = aosStoreIndexSlot
                  If aosStoreIsLocal
                     llObjects()\funcid = 1  ; Use funcid as local flag
                  EndIf

               EndIf

            Else
               ; Regular variable assignment
               ; V1.022.71: Type annotation (.i, .f, .s) inside function = local variable
               ; var.type = expr creates local; var = expr uses global if exists
               ; TypeHint > 0 means type annotation present = force local
               n = FetchVarOffset( *x\left\value, *x\right, 0, *x\left\TypeHint )

               ; V1.022.65: Check for struct-to-struct copy (same type required)
               ; destStruct = srcStruct
               Protected scStructCopyDone.i = #False
               If gVarMeta(n)\structType <> "" And *x\right And *x\right\NodeType = #ljIDENT
                  Protected scSrcSlot.i = FetchVarOffset(*x\right\value)
                  If scSrcSlot >= 0 And scSrcSlot < ArraySize(gVarMeta())
                     If gVarMeta(scSrcSlot)\structType = gVarMeta(n)\structType
                        ; Both are structs of same type - emit STRUCTCOPY
                        Protected scStructType.s = gVarMeta(n)\structType
                        Protected scSlotCount.i = 0
                        If FindMapElement(mapStructDefs(), scStructType)
                           scSlotCount = mapStructDefs()\totalSize
                        EndIf
                        If scSlotCount > 0
                           ; Emit STRUCTCOPY: i=destSlot, j=srcSlot, n=slotCount
                           EmitInt(#ljSTRUCTCOPY, n)
                           llObjects()\j = scSrcSlot
                           llObjects()\n = scSlotCount
                           scStructCopyDone = #True  ; Skip normal assignment
                        EndIf
                     ElseIf gVarMeta(scSrcSlot)\structType <> ""
                        ; Both are structs but different types - error
                        SetError("Cannot assign struct '" + gVarMeta(scSrcSlot)\structType + "' to '" + gVarMeta(n)\structType + "' (type mismatch)", #C2ERR_CODEGEN_FAILED)
                        ProcedureReturn
                     EndIf
                  EndIf
               EndIf

               ; Skip regular assignment code if struct copy was done
               If Not scStructCopyDone

               ; Check if right-hand side is a pointer expression and propagate pointer flag
               If *x\right
                  If *x\right\NodeType = #ljGETADDR Or
                     *x\right\NodeType = #ljPTRADD Or
                     *x\right\NodeType = #ljPTRSUB
                     ; Right side is a pointer expression - mark destination as pointer
                     gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_POINTER

                     ; V1.022.54: Track struct pointer type for ptr\field access
                     If *x\right\NodeType = #ljGETADDR And *x\right\left And *x\right\left\NodeType = #ljIDENT
                        srcVarSlot = FetchVarOffset(*x\right\left\value)
                        If srcVarSlot >= 0 And srcVarSlot < ArraySize(gVarMeta())
                           If gVarMeta(srcVarSlot)\structType <> ""
                              ; Source is a struct - save struct type in destination metadata
                              gVarMeta(n)\pointsToStructType = gVarMeta(srcVarSlot)\structType
                           EndIf
                        EndIf
                     EndIf
                  ElseIf *x\right\NodeType = #ljIDENT
                     ; Check if source variable is a pointer
                     ptrVarOffset = FetchVarOffset(*x\right\value)
                     If ptrVarOffset >= 0 And ptrVarOffset < ArraySize(gVarMeta())
                        If gVarMeta(ptrVarOffset)\flags & #C2FLAG_POINTER
                           ; Source is a pointer - mark destination as pointer
                           gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_POINTER
                           ; V1.022.54: Propagate struct pointer type
                           If gVarMeta(ptrVarOffset)\pointsToStructType <> ""
                              gVarMeta(n)\pointsToStructType = gVarMeta(ptrVarOffset)\pointsToStructType
                           EndIf
                        EndIf
                     EndIf
                  EndIf
               EndIf

               ; V1.18.42: Get the type of the right-hand expression WITHOUT generating code yet
               ; This allows us to do compile-time conversion optimization for literals
               rightType = GetExprResultType(*x\right)

               ; V1.18.30: Implement proper LJ type system
               ; Variables are type-inferred on first assignment, then locked (static typing)

               If Not (gVarMeta(n)\flags & #C2FLAG_CHG)
                  ; FIRST ASSIGNMENT - Type inference with locking

                  ; V1.20.12: Check if RHS is PTRFETCH (possibly wrapped in type conversion)
                  ; Parser may insert ITOF/FTOI wrapper, so check both direct and wrapped cases
                  Protected *ptrFetchNode.stTree = #Null

                  If *x\right
                     ; Direct PTRFETCH
                     If *x\right\NodeType = #ljPTRFETCH
                        *ptrFetchNode = *x\right
                     ; PTRFETCH wrapped in type conversion (ITOF or FTOI)
                     ElseIf (*x\right\NodeType = #ljITOF Or *x\right\NodeType = #ljFTOI) And *x\right\left
                        If *x\right\left\NodeType = #ljPTRFETCH
                           *ptrFetchNode = *x\right\left
                        EndIf
                     EndIf
                  EndIf

                  ; V1.20.12: If RHS is PTRFETCH (direct or wrapped) with explicit type annotation, bypass conversion
                  If *ptrFetchNode And *x\left And *x\left\TypeHint <> 0
                     ; Convert TypeHint to type flag
                     Select *x\left\TypeHint
                        Case #ljFLOAT
                           explicitTypeFlag = #C2FLAG_FLOAT
                        Case #ljSTRING
                           explicitTypeFlag = #C2FLAG_STR
                        Case #ljINT
                           explicitTypeFlag = #C2FLAG_INT
                        Default
                           explicitTypeFlag = #C2FLAG_INT
                     EndSelect

                     ; Use explicit type from TypeHint
                     gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | explicitTypeFlag

                     ; Emit appropriate warning
                     If explicitTypeFlag = #C2FLAG_FLOAT
                        AddElement(gWarnings())
                        s = "Variable '" + *x\left\value + "' declared as float (PTRFETCH with TypeHint)"
                        gWarnings() = s
                     ElseIf explicitTypeFlag = #C2FLAG_STR
                        AddElement(gWarnings())
                        s = "Variable '" + *x\left\value + "' declared as string (PTRFETCH with TypeHint)"
                        gWarnings() = s
                     EndIf

                     ; Mark variable as assigned (locks the type)
                     gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_CHG

                     ; V1.20.5: Set expected type for PTRFETCH to emit specialized opcode
                     gPtrFetchExpectedType = explicitTypeFlag

                     ; V1.20.12: Generate PTRFETCH directly, bypassing type conversion wrapper
                     ; This ensures we emit FPTRFETCH/IPTRFETCH instead of PTRFETCH+ITOF
                     CodeGenerator( *ptrFetchNode )
                  Else
                     ; Normal type inference path

                     ; Check for explicit type suffix conflict with inferred type
                     If *x\left\TypeHint = #ljFLOAT And Not (rightType & #C2FLAG_FLOAT)
                        s = "Type conflict: variable '" + *x\left\value + "' has explicit suffix .f (float) but is assigned " + #CRLF$
                        s + GetTypeNameFromFlags(rightType)
                        SetError( s, #True )
                     ElseIf *x\left\TypeHint = #ljSTRING And Not (rightType & #C2FLAG_STR)
                        s = "Type conflict: variable '" + *x\left\value + "' has explicit suffix .s (string) but is assigned " + #CRLF$
                        s + GetTypeNameFromFlags(rightType)
                        SetError( s, #True )
                     ElseIf *x\left\TypeHint = #ljINT And Not (rightType & #C2FLAG_INT)
                        s = "Type conflict: variable '" + *x\left\value + "' has explicit suffix (int) but is assigned " + #CRLF$
                        s + GetTypeNameFromFlags(rightType)
                        SetError( s, #True )
                     EndIf

                     ; V1.20.10: Use AST TypeHint field to force explicit type
                     ; The TypeHint is set during parsing and is reliable, unlike TOKEN().typeHint during codegen
                     If *x\left\TypeHint = #ljFLOAT
                        ; Explicit .f suffix - FORCE float type
                        gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_FLOAT
                     ElseIf *x\left\TypeHint = #ljSTRING
                        ; Explicit .s suffix - FORCE string type
                        gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_STR
                     ElseIf *x\left\TypeHint = #ljINT
                        ; Explicit .i suffix - FORCE int type
                        gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_INT
                     Else
                        ; No explicit suffix - infer from right-hand side
                        If rightType & #C2FLAG_FLOAT
                           gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_FLOAT
                        ElseIf rightType & #C2FLAG_STR
                           gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_STR
                        Else
                           ; INT type (default)
                           gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_INT
                        EndIf
                     EndIf

                     ; Mark variable as assigned (locks the type)
                     gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_CHG

                     ; V1.20.5: Set expected type for PTRFETCH to emit specialized opcode
                     If *x\right And *x\right\NodeType = #ljPTRFETCH
                        gPtrFetchExpectedType = gVarMeta(n)\flags & #C2FLAG_TYPE
                     EndIf

                     ; Generate code for right-hand expression (no conversion needed on first assignment)
                     CodeGenerator( *x\right )
                  EndIf

               Else
                  ; SUBSEQUENT ASSIGNMENT - Type checking and conversion

                  ; V1.023.26: Strict type checking - variables cannot change type
                  If *x\left\TypeHint = #ljFLOAT And Not (gVarMeta(n)\flags & #C2FLAG_FLOAT)
                     existingTypeName = "int"
                     If gVarMeta(n)\flags & #C2FLAG_STR
                        existingTypeName = "string"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_POINTER
                        existingTypeName = "pointer"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STRUCT
                        existingTypeName = "struct"
                     EndIf
                     SetError("Variable '" + *x\left\value + "' already declared as " + existingTypeName + ", cannot re-declare as float", 10)
                  ElseIf *x\left\TypeHint = #ljSTRING And Not (gVarMeta(n)\flags & #C2FLAG_STR)
                     existingTypeName = "int"
                     If gVarMeta(n)\flags & #C2FLAG_FLOAT
                        existingTypeName = "float"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_POINTER
                        existingTypeName = "pointer"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STRUCT
                        existingTypeName = "struct"
                     EndIf
                     SetError("Variable '" + *x\left\value + "' already declared as " + existingTypeName + ", cannot re-declare as string", 10)
                  ElseIf *x\left\TypeHint = #ljINT And Not (gVarMeta(n)\flags & #C2FLAG_INT)
                     existingTypeName = "float"
                     If gVarMeta(n)\flags & #C2FLAG_STR
                        existingTypeName = "string"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_POINTER
                        existingTypeName = "pointer"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STRUCT
                        existingTypeName = "struct"
                     EndIf
                     SetError("Variable '" + *x\left\value + "' already declared as " + existingTypeName + ", cannot re-declare as int", 10)
                  EndIf

                  ; V1.18.42: Type conversion optimization - compile-time vs runtime
                  ; Check if RHS is a literal (can do compile-time conversion)
                  isLiteral = #False
                  literalValue = ""

                  ; Get decimal places from pragma settings (default to 2 if not set)
                  decimalPlaces = 2
                  If mapPragmas("decimals") <> ""
                     decimalPlaces = Val(mapPragmas("decimals"))
                  EndIf

                  If *x\right\NodeType = #ljFLOAT Or *x\right\NodeType = #ljINT Or *x\right\NodeType = #ljSTRING
                     isLiteral = #True
                     literalValue = *x\right\value
                  EndIf

                  ; V1.20.5: If RHS is PTRFETCH, set expected type and skip conversion
                  ; PTRFETCH uses specialized opcodes to fetch into correct field
                  If *x\right And *x\right\NodeType = #ljPTRFETCH
                     ; Set expected type for specialized PTRFETCH opcode
                     gPtrFetchExpectedType = gVarMeta(n)\flags & #C2FLAG_TYPE
                     CodeGenerator( *x\right )
                     ; Skip all type conversion logic - specialized PTRFETCH handles it
                  Else
                     ; Check for type mismatch and handle conversion
                  ; INT to FLOAT conversion
                  ; V1.19.4: Skip conversion if RHS is PTRFETCH (it handles typing internally)
                  If ((gVarMeta(n)\flags & #C2FLAG_FLOAT) <> 0) And ((rightType & #C2FLAG_INT) <> 0)
                     If isLiteral
                        convertedFloatVal = ValD(literalValue)
                        constIdx = FetchVarOffset( StrD(convertedFloatVal, decimalPlaces), 0, #ljFLOAT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting int to float (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljITOF, 0 )
                        AddElement(gWarnings())
                        s2 = "Converting int to float (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; FLOAT to INT conversion
                  ; V1.19.5: Skip conversion if RHS is PTRFETCH (it handles typing internally)
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_INT) <> 0) And ((rightType & #C2FLAG_FLOAT) <> 0)
                     If isLiteral
                        convertedFloatVal = ValD(literalValue)
                        ; Apply ftoi pragma setting (truncate or round)
                        If mapPragmas("ftoi") = "truncate"
                           convertedIntVal = Int(convertedFloatVal)
                        Else
                           convertedIntVal = Round(convertedFloatVal, #PB_Round_Nearest)
                        EndIf
                        ; Add to constant pool and emit PUSH
                        constIdx = FetchVarOffset( Str(convertedIntVal), 0, #ljINT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting float to int (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        ; V1.19.5: Check if RHS is PTRFETCH - if so, no conversion needed
                        Define isPtrFetch2.i = #False
                        If *x\right And *x\right\NodeType = #ljPTRFETCH
                           isPtrFetch2 = #True
                        EndIf

                        CodeGenerator( *x\right )

                        If Not isPtrFetch2
                           EmitInt( #ljFTOI, 0 )
                           AddElement(gWarnings())
                           s2 = "Converting float to int (runtime) for variable '" + *x\left\value + "'"
                           gWarnings() = s2
                        EndIf
                     EndIf

                  ; FLOAT to STRING conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_STR) <> 0) And ((rightType & #C2FLAG_FLOAT) <> 0)
                     If isLiteral
                        constIdx = FetchVarOffset( literalValue, 0, #ljSTRING )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting float to string (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljFTOS )
                        AddElement(gWarnings())
                        s2 = "Converting float to string (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; INT to STRING conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_STR) <> 0) And ((rightType & #C2FLAG_INT) <> 0)
                     If isLiteral
                        constIdx = FetchVarOffset( literalValue, 0, #ljSTRING )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting int to string (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljITOS )
                        AddElement(gWarnings())
                        s2 = "Converting int to string (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; STRING to FLOAT conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_FLOAT) <> 0) And ((rightType & #C2FLAG_STR) <> 0)
                     If isLiteral
                        convertedFloatVal = ValD(literalValue)
                        constIdx = FetchVarOffset( StrD(convertedFloatVal, decimalPlaces), 0, #ljFLOAT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting string to float (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljSTOF )
                        AddElement(gWarnings())
                        s2 = "Converting string to float (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; STRING to INT conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_INT) <> 0) And ((rightType & #C2FLAG_STR) <> 0)
                     If isLiteral
                        constIdx = FetchVarOffset( Str(Val(literalValue)), 0, #ljINT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting string to int (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljSTOI )
                        AddElement(gWarnings())
                        s2 = "Converting string to int (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf
                  Else
                     ; No conversion needed - generate RHS code normally
                     CodeGenerator( *x\right )

                     ; V1.19.1: Warn if untyped variable is assigned from PTRFETCH
                     If *x\right And *x\right\NodeType = #ljPTRFETCH
                        ; Check if variable has explicit type annotation
                        Protected hasExplicitType.i = #False
                        If (gVarMeta(n)\flags & #C2FLAG_FLOAT) Or (gVarMeta(n)\flags & #C2FLAG_STR)
                           hasExplicitType = #True
                        ElseIf (gVarMeta(n)\flags & #C2FLAG_INT)
                           ; Check if it was explicitly typed or defaulted to INT
                           ; Variables with explicit .i suffix would have been marked
                           ; For now, we'll warn if RHS is PTRFETCH and var is INT (could be implicit)
                           ; This is conservative - may warn on some explicitly typed vars
                        EndIf

                        If Not hasExplicitType
                           AddElement(gWarnings())
                           s2 = "Warning: Untyped variable '" + *x\left\value + "' assigned from pointer dereference. " +
                                "Consider adding explicit type annotation (e.g., var.f = *ptr)"
                           gWarnings() = s2
                        EndIf
                     EndIf
                  EndIf
                  EndIf  ; End of V1.20.0 PTRFETCH explicit typing check
               EndIf

               ; Emit appropriate STORE variant based on variable type
               If gVarMeta(n)\flags & #C2FLAG_STR
                  EmitInt( #ljSTORES, n )
               ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                  EmitInt( #ljSTOREF, n )
               Else
                  EmitInt( #ljSTORE, n )
               EndIf

               ; Type propagation: If assigning a typed value to an untyped var, update the var
               If llObjects()\code <> #ljMOV And llObjects()\code <> #ljMOVS And llObjects()\code <> #ljMOVF And
                  llObjects()\code <> #ljLMOV And llObjects()\code <> #ljLMOVS And llObjects()\code <> #ljLMOVF
                  ; Keep the variable's declared type (don't change it)
                  ; Type checking could be added here later
               EndIf

               EndIf  ; V1.022.65: End If Not scStructCopyDone
            EndIf

         Case #ljPRE_INC
            ; Pre-increment: ++var (integers only)
            ; Increments variable in place and pushes new value
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local increment
                  EmitInt( #ljLINC_VAR_PRE, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljINC_VAR_PRE, n )
               EndIf
            EndIf

         Case #ljPRE_DEC
            ; Pre-decrement: --var (integers only)
            ; Decrements variable in place and pushes new value
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local decrement
                  EmitInt( #ljLDEC_VAR_PRE, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljDEC_VAR_PRE, n )
               EndIf
            EndIf

         Case #ljPOST_INC
            ; Post-increment: var++ (integers only)
            ; Pushes old value to stack, then increments variable in place
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local increment
                  EmitInt( #ljLINC_VAR_POST, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljINC_VAR_POST, n )
               EndIf
            EndIf

         Case #ljPOST_DEC
            ; Post-decrement: var-- (integers only)
            ; Pushes old value to stack, then decrements variable in place
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local decrement
                  EmitInt( #ljLDEC_VAR_POST, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljDEC_VAR_POST, n )
               EndIf
            EndIf

         Case #ljreturn
            ; Note: The actual return type is determined at the SEQ level
            ; This case should not normally be reached since SEQ handler processes returns
            EmitInt( #ljreturn )

         Case #ljIF
            CodeGenerator( *x\left )
            EmitInt( #ljJZ)
            p1 = hole()
            CodeGenerator( *x\right\left )

            If *x\right\right
               EmitInt( #ljJMP)
               p2 = hole()
            EndIf

            EmitInt( #ljNOOPIF )   ; Marker after if-body for JZ target
            fix( p1 )

            If *x\right\right
               CodeGenerator( *x\right\right )
               EmitInt( #ljNOOPIF )   ; Marker after else-body for JMP target
               fix( p2 )
            EndIf

         Case #ljTERNARY
            ; Ternary operator: condition ? true_expr : false_expr
            ; *x\left = condition
            ; *x\right = COLON node with true_expr in left, false_expr in right
            ; Using dedicated TENIF/TENELSE opcodes for cleaner implementation
            If *x\left And *x\right
               gInTernary = #True                ; Disable PUSH/FETCH→MOV optimization

               CodeGenerator( *x\left )          ; Evaluate condition
               EmitInt( #ljTENIF )               ; Ternary IF: Jump if condition false
               p1 = hole()                       ; Remember jump location for false branch

               If *x\right\left
                  CodeGenerator( *x\right\left )    ; Evaluate true expression
               EndIf

               EmitInt( #ljTENELSE )             ; Ternary ELSE: Jump past false branch
               p2 = hole()

               ; Emit NOOPIF marker at false branch start - makes offset calculation trivial
               EmitInt( #ljNOOPIF )
               fix( p1 )                         ; Fix TENIF to NOOPIF marker position

               If *x\right\right
                  CodeGenerator( *x\right\right )   ; Evaluate false expression
               EndIf

               ; Emit NOOPIF marker after false branch - target for TENELSE jump
               EmitInt( #ljNOOPIF )
               fix( p2 )                         ; Fix TENELSE to NOOPIF marker position

               gInTernary = #False               ; Re-enable optimization
            EndIf

         Case #ljWHILE
            ; V1.18.54: Save JMP pointer explicitly to avoid LastElement() cursor issues in nested loops
            EmitInt( #ljNOOPIF )            ; Emit marker at loop start
            p1 = @llObjects()               ; V1.023.40: Use @ to get actual pointer for NOOP marker
            CodeGenerator( *x\left )        ; Generate condition
            EmitInt( #ljJZ)                 ; Jump if condition false
            p2 = Hole()                     ; Save JZ hole for fixing later
            CodeGenerator( *x\right )       ; Generate loop body
            EmitInt( #ljJMP)                ; Jump back to loop start
            *pJmp = @llObjects()            ; V1.023.40: Use @ to get actual pointer for JMP

            ; Manually create hole entry for backward JMP instead of calling fix()
            ; V1.023.42: Use LOOPBACK mode for while loop backward jumps
            AddElement( llHoles() )
            llHoles()\mode = #C2HOLE_LOOPBACK
            llHoles()\location = *pJmp      ; Use saved pointer instead of LastElement()
            llHoles()\src = p1

            EmitInt( #ljNOOPIF )            ; Emit marker at loop end
            fix( p2 )                       ; Fix JZ hole to point to end marker
            
         Case #ljSEQ
            ; Check if this SEQ eventually leads to a return statement
            ; Patterns: SEQ(?, SEQ(expr, #ljreturn)) or SEQ(?, SEQ(?, SEQ(expr, #ljreturn)))
            isReturnSeq = #False
            *returnExpr = 0

            If *x\right And *x\right\NodeType = #ljSEQ
               ; Check for two-level pattern: SEQ(?, SEQ(expr, #ljreturn))
               If *x\right\right And *x\right\right\NodeType = #ljreturn
                  isReturnSeq = #True
                  *returnExpr = *x\right\left
               ; Check for three-level pattern: SEQ(?, SEQ(?, SEQ(expr, #ljreturn)))
               ElseIf *x\right\right And *x\right\right\NodeType = #ljSEQ
                  If *x\right\right\right And *x\right\right\right\NodeType = #ljreturn
                     isReturnSeq = #True
                     *returnExpr = *x\right\right\left
                  EndIf
               EndIf
            EndIf

            If isReturnSeq
               ; This is a return statement - handle specially
               ; Process left (previous statements) if any
               If *x\left
                  CodeGenerator( *x\left )
               EndIf

               ; Process return expression
               If *returnExpr
                  CodeGenerator( *returnExpr )
               EndIf

               ; Emit appropriate return opcode based on function type
               returnType = #C2FLAG_INT
               If gCodeGenFunction > 0
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        returnType = mapModules()\returnType
                        Break
                     EndIf
                  Next
               EndIf

               If returnType & #C2FLAG_STR
                  EmitInt( #ljreturnS )
               ElseIf returnType & #C2FLAG_FLOAT
                  EmitInt( #ljreturnF )
               Else
                  EmitInt( #ljreturn )
               EndIf
            Else
               ; Normal SEQ processing
               If *x\left
                  CodeGenerator( *x\left )
               EndIf
               If *x\right
                  CodeGenerator( *x\right )

                  ; V1.020.053: Pop unused values from statement-level operations
                  ; POST_INC and POST_DEC push old value, PRE_INC and PRE_DEC push new value
                  ; When used as statements, these values are unused and must be popped
                  If *x\right\NodeType = #ljPOST_INC Or *x\right\NodeType = #ljPOST_DEC Or
                     *x\right\NodeType = #ljPRE_INC Or *x\right\NodeType = #ljPRE_DEC
                     EmitInt( #ljPOP )
                  EndIf
               EndIf
            EndIf

            ; NOTE: Don't reset gCodeGenFunction here!
            ; The AST has nested SEQ nodes, and resetting here happens too early.
            ; Function body may continue in outer SEQ nodes.
            ; Like gCurrentFunctionName, gCodeGenFunction will be overwritten when next function starts.
            ; The nLocals count is updated incrementally in FetchVarOffset as variables are created.
            
         Case #ljFunction
            ; Emit function marker for postprocessor (implicit return insertion)
            EmitInt( #ljfunction )
            ; V1.023.6: Store funcId in instruction for Pass 26 function tracking
            llObjects()\i = Val( *x\value )
            ; V1.022.30: Reset function context before lookup to prevent stale values
            gCurrentFunctionName = ""
            gCodeGenParamIndex = -1
            gCodeGenLocalIndex = 0
            gCodeGenFunction = 0
            ForEach mapModules()
               If mapModules()\function = Val( *x\value )
                  ; Store BOTH index and pointer to list element for post-optimization fixup
                  mapModules()\Index = ListIndex( llObjects() ) + 1
                  mapModules()\NewPos = @llObjects()  ; Store pointer to element
                  ; Initialize parameter tracking
                  ; Parameters processed in reverse, so start from (nParams - 1) and decrement
                  gCodeGenParamIndex = mapModules()\nParams - 1
                  ; V1.022.77: Local variables start after parameters AND local arrays
                  ; Local arrays get paramOffset assigned during AST parsing, so we must
                  ; start counting local variables AFTER them to avoid conflicts
                  gCodeGenLocalIndex = mapModules()\nParams + mapModules()\nLocalArrays
                  ; Set current function name for local variable scoping
                  gCurrentFunctionName = MapKey(mapModules())
                  ; Track current function ID for nLocals counting
                  gCodeGenFunction = mapModules()\function
                  Break
               EndIf
            Next
            
         Case #ljPRTC, #ljPRTI, #ljPRTS, #ljPRTF, #ljprint
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType )

         Case #ljLESS, #ljGREATER, #ljLESSEQUAL, #ljGreaterEqual, #ljEQUAL, #ljNotEqual,
              #ljAdd, #ljSUBTRACT, #ljDIVIDE, #ljMULTIPLY

            leftType    = GetExprResultType(*x\left)
            rightType   = GetExprResultType(*x\right)

            ; With proper stack frames, parameters are stack-local and won't be corrupted
            ; No need for temp variables or special handling
            CodeGenerator( *x\left )
            
            ; For string addition, convert left operand to string if needed
            If *x\NodeType = #ljAdd And (leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR)
               If Not (leftType & #C2FLAG_STR)
                  ; Left is not a string - emit conversion
                  If leftType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOS )
                  Else
                     EmitInt( #ljITOS )
                  EndIf
               EndIf
            ElseIf leftType & #C2FLAG_FLOAT And Not (rightType & #C2FLAG_FLOAT) And rightType & #C2FLAG_INT
               ; Left is float, right will be int - no conversion needed yet (convert right after it's pushed)
            ElseIf leftType & #C2FLAG_INT And rightType & #C2FLAG_FLOAT
               ; Left is int, right will be float - convert left to float now
               EmitInt( #ljITOF )
            EndIf
            
            CodeGenerator( *x\right )

            ; Special handling for ADD with strings - emit type conversions
            If *x\NodeType = #ljAdd And (leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR)
               ; Convert right operand to string if needed
               If Not (rightType & #C2FLAG_STR)
                  If rightType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOS )
                  Else
                     EmitInt( #ljITOS )
                  EndIf
               EndIf
               ; Now both operands are strings - emit STRADD
               EmitInt( #ljSTRADD )
            Else
               ; Standard arithmetic/comparison - determine result type
               opType = #C2FLAG_INT

               ; V1.021.12: Removed PTRFETCH safety override - rely on GetExprResultType
               ; The old code forced FLOAT ops for any PTRFETCH, breaking .i pointer comparisons
               ; GetExprResultType now returns the correct type for typed pointers
               If leftType & #C2FLAG_FLOAT Or rightType & #C2FLAG_FLOAT
                  opType = #C2FLAG_FLOAT
                  ; Convert right operand to float if needed
                  If rightType & #C2FLAG_INT And Not (rightType & #C2FLAG_FLOAT)
                     EmitInt( #ljITOF )
                  EndIf
               EndIf

               ; Check if left operand is a pointer for pointer arithmetic
               isPointerArithmetic = #False
               If (*x\NodeType = #ljAdd Or *x\NodeType = #ljSUBTRACT) And *x\left
                  ; Check if left operand is an identifier with pointer flag
                  If *x\left\NodeType = #ljIDENT
                     ptrVarOffset = FetchVarOffset(*x\left\value)
                     If ptrVarOffset >= 0 And ptrVarOffset < ArraySize(gVarMeta())
                        If gVarMeta(ptrVarOffset)\flags & #C2FLAG_POINTER
                           isPointerArithmetic = #True
                        EndIf
                     EndIf
                  ; Also check if left is a pointer fetch result (*ptr)
                  ElseIf *x\left\NodeType = #ljPTRFETCH
                     isPointerArithmetic = #True
                  ; Or if left is GETADDR (&var or &arr[i])
                  ElseIf *x\left\NodeType = #ljGETADDR
                     isPointerArithmetic = #True
                  ; Or if left is another pointer arithmetic operation
                  ElseIf *x\left\NodeType = #ljPTRADD Or *x\left\NodeType = #ljPTRSUB
                     isPointerArithmetic = #True
                  EndIf
               EndIf

               ; Emit correct opcode
               If isPointerArithmetic
                  ; Emit pointer arithmetic opcodes that preserve metadata
                  If *x\NodeType = #ljAdd
                     EmitInt( #ljPTRADD )
                  Else  ; #ljSUBTRACT
                     EmitInt( #ljPTRSUB )
                  EndIf
               ; V1.023.30: String comparison - both operands must be strings
               ElseIf (leftType & #C2FLAG_STR) And (rightType & #C2FLAG_STR)
                  If *x\NodeType = #ljEQUAL
                     EmitInt( #ljSTREQ )
                  ElseIf *x\NodeType = #ljNotEqual
                     EmitInt( #ljSTRNE )
                  Else
                     ; Other comparisons not supported for strings - emit default
                     EmitInt( *x\NodeType )
                  EndIf
               ElseIf opType & #C2FLAG_FLOAT And gszATR(*x\NodeType)\flttoken > 0
                  EmitInt( gszATR(*x\NodeType)\flttoken )
               Else
                  EmitInt( *x\NodeType )
               EndIf
            EndIf

         Case #ljOr, #ljAND, #ljMOD, #ljXOR
            CodeGenerator( *x\left )
            CodeGenerator( *x\right )
            EmitInt( *x\NodeType)

         Case #ljNOT
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType)

         Case #ljNEGATE
            CodeGenerator( *x\left )

            If *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               negType = gVarMeta(n)\flags & #C2FLAG_TYPE
            ElseIf *x\left\NodeType = #ljFLOAT
               negType = #C2FLAG_FLOAT
            EndIf

            If negType & #C2FLAG_FLOAT
               EmitInt( #ljFLOATNEG )
            Else
               EmitInt( #ljNEGATE )
            EndIf

         Case #ljGETADDR  ; Address-of operator: &variable or &arr[index] or &function
            ; V1.020.098: Check if this is a function pointer: &function
            If *x\left And *x\left\NodeType = #ljIDENT
               ; V1.020.114: The identifier value contains function ID (as string), not name
               ; Scanner stores Str(gCurrFunction) in TOKEN()\value for function calls
               ; We need to search mapModules() for matching function ID
               searchFuncId.i = Val(*x\left\value)
               foundFunc.i = #False

               ; Search mapModules() for this function ID
               ForEach mapModules()
                  If mapModules()\function = searchFuncId
                     ; This is a function! Emit GETFUNCADDR with function ID
                     ; The function PC will be patched later by postprocessor (like CALL)
                     EmitInt( #ljGETFUNCADDR, mapModules()\function )
                     foundFunc = #True
                     ProcedureReturn
                  EndIf
               Next

               ;If Not foundFunc
               ;   Debug "    -> Not a function (funcId=" + Str(searchFuncId) + " not found in mapModules())"
               ;EndIf
            EndIf

            ; Check if this is an array element: &arr[index]
            If *x\left And *x\left\NodeType = #ljLeftBracket
               ; Array element pointer: &arr[index]
               ; *x\left\left = array variable (ljIDENT)
               ; *x\left\right = index expression

               If *x\left\left And *x\left\left\NodeType = #ljIDENT
                  n = FetchVarOffset(*x\left\left\value)

                  ; Emit index expression first (pushes index to stack)
                  CodeGenerator( *x\left\right )

                  ; Determine opcode based on array type from metadata (not TypeHint)
                  ; Use gVarMeta flags like normal array indexing does
                  Protected arrayOpcode.i = #ljGETARRAYADDR  ; Default to integer
                  Protected arrayType.i = gVarMeta(n)\flags & #C2FLAG_TYPE
                  If arrayType = #C2FLAG_STR
                     arrayOpcode = #ljGETARRAYADDRS
                  ElseIf arrayType = #C2FLAG_FLOAT
                     arrayOpcode = #ljGETARRAYADDRF
                  EndIf

                  ; Emit GETARRAYADDR with array slot
                  EmitInt( arrayOpcode, n )
               Else
                  SetError( "Address-of array operator requires array variable", #C2ERR_EXPECTED_PRIMARY )
               EndIf

            ; Regular variable pointer: &var
            ElseIf *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Mark variable as having its address taken (for pointer metadata)
               gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_POINTER

               ; V1.022.54: Check if this is a struct variable
               If gVarMeta(n)\structType <> ""
                  ; Struct pointer - emit GETSTRUCTADDR with base slot
                  EmitInt( #ljGETSTRUCTADDR, n )
               Else
                  ; Emit type-specific GETADDR based on variable type hint
                  Protected opcode.i = #ljGETADDR  ; Default to integer
                  If *x\left\TypeHint = #ljSTRING
                     opcode = #ljGETADDRS
                  ElseIf *x\left\TypeHint = #ljFLOAT
                     opcode = #ljGETADDRF
                  EndIf

                  EmitInt( opcode, n )
               EndIf
            Else
               SetError( "Address-of operator requires a variable, array element, or function", #C2ERR_EXPECTED_PRIMARY )
            EndIf

         Case #ljPTRFETCH  ; Pointer dereference: *ptr
            ; Emit code to evaluate pointer expression (should be slot index)
            CodeGenerator( *x\left )

            ; V1.20.5: Emit specialized PTRFETCH if expected type is set
            If gPtrFetchExpectedType & #C2FLAG_FLOAT
               EmitInt( #ljPTRFETCH_FLOAT )
            ElseIf gPtrFetchExpectedType & #C2FLAG_STR
               EmitInt( #ljPTRFETCH_STR )
            ElseIf gPtrFetchExpectedType & #C2FLAG_INT
               EmitInt( #ljPTRFETCH_INT )
            Else
               ; No expected type - emit generic PTRFETCH (will be typed by postprocessor or at runtime)
               EmitInt( #ljPTRFETCH )
            EndIf

            ; Clear expected type after use
            gPtrFetchExpectedType = 0

         Case #ljCall
            funcId = Val( *x\value )
            paramCount = *x\paramCount  ; Get actual param count from tree node

            ; V1.020.102: Check if Call has a left child (expression to evaluate for function pointer)
            ; This handles cases like: operations[i](x, y) where operations[i] is in left child
            If *x\left
               ; Evaluate the expression to get function pointer on stack
               CodeGenerator(*x\left)
               ; Emit function pointer call
               EmitInt( #ljCALLFUNCPTR, 0 )
               llObjects()\j = paramCount     ; nParams
               llObjects()\n = 0              ; nLocals (unknown)
               llObjects()\ndx = 0            ; nLocalArrays (unknown)
               ProcedureReturn
            EndIf

            ; V1.020.098: Check if this is actually a function pointer call
            ; If funcId is 0 and the name doesn't exist as a function, it might be a variable
            If funcId = 0
               ; Try to find the name as a variable instead of a function
               funcPtrSlot.i = -1
               searchName.s = *x\value

               ; Try local variable first (if in a function)
               If gCurrentFunctionName <> ""
                  searchName = gCurrentFunctionName + "_" + *x\value
                  For i = 0 To gnLastVariable
                     If gVarMeta(i)\name = searchName
                        funcPtrSlot = i
                        Break
                     EndIf
                  Next
               EndIf

               ; Try global variable if not found as local
               If funcPtrSlot = -1
                  For i = 0 To gnLastVariable
                     If gVarMeta(i)\name = *x\value
                        funcPtrSlot = i
                        Break
                     EndIf
                  Next
               EndIf

               ; If found as a variable, emit function pointer call
               If funcPtrSlot >= 0
                  ; This is a function pointer call!
                  ; Emit: FETCH funcPtrSlot, then CALLFUNCPTR
                  ; Note: CALLFUNCPTR needs nParams, nLocals, nLocalArrays but we don't know them
                  ; For now, we'll set defaults and let runtime handle it
                  EmitInt( #ljFetch, funcPtrSlot )
                  EmitInt( #ljCALLFUNCPTR, 0 )  ; Function PC on stack
                  llObjects()\j = paramCount     ; nParams
                  llObjects()\n = 0              ; nLocals (unknown for function pointers)
                  llObjects()\ndx = 0            ; nLocalArrays (unknown)
                  ProcedureReturn
               EndIf
            EndIf

            ; Check if this is a built-in function (opcode >= #ljBUILTIN_RANDOM)
            ; V1.023.29: Also check for type conversion opcodes (str(), strf())
            If funcId >= #ljBUILTIN_RANDOM Or funcId = #ljITOS Or funcId = #ljFTOS
               ; Built-in function or type conversion - emit opcode directly
               EmitInt( funcId )
               llObjects()\j = paramCount
            Else
               ; User-defined function - emit CALL with function ID
               ; Store nParams in j and nLocals in n (no packing)
               Protected nLocals.l, nLocalArrays.l
               EmitInt( #ljCall, funcId )

               ; Find nLocals and nLocalArrays for this function
               ForEach mapModules()
                  If mapModules()\function = funcId
                     nLocals = mapModules()\nLocals
                     nLocalArrays = mapModules()\nLocalArrays
                     Break
                  EndIf
               Next

               ; Store separately: j = nParams, n = nLocals, ndx = nLocalArrays, funcid = function ID
               llObjects()\j = paramCount
               llObjects()\n = nLocals
               llObjects()\ndx = nLocalArrays
               llObjects()\funcid = funcId
            EndIf
            
         Case #ljHalt
            EmitInt( *x\NodeType, 0 )

         ; Type conversion operators (unary - operate on left child)
         Case #ljITOF, #ljFTOI, #ljITOS, #ljFTOS, #ljSTOF, #ljSTOI
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType )

         ; Cast operators (V1.18.63) - smart type conversion based on source and target
         Case #ljCAST_INT, #ljCAST_FLOAT, #ljCAST_STRING
            ; Generate code for the expression to be cast
            CodeGenerator( *x\left )

            ; Determine source type
            Protected sourceType.w = GetExprResultType(*x\left)

            ; Emit appropriate conversion based on source and target types
            Select *x\NodeType
               Case #ljCAST_INT
                  ; Cast to int
                  If sourceType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOI )  ; float -> int
                  ElseIf sourceType & #C2FLAG_STR
                     EmitInt( #ljSTOI )  ; string -> int
                  EndIf
                  ; If already int, no conversion needed

               Case #ljCAST_FLOAT
                  ; Cast to float
                  If sourceType & #C2FLAG_INT
                     EmitInt( #ljITOF )  ; int -> float
                  ElseIf sourceType & #C2FLAG_STR
                     EmitInt( #ljSTOF )  ; string -> float
                  EndIf
                  ; If already float, no conversion needed

               Case #ljCAST_STRING
                  ; Cast to string
                  If sourceType & #C2FLAG_INT
                     EmitInt( #ljITOS )  ; int -> string
                  ElseIf sourceType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOS )  ; float -> string
                  EndIf
                  ; If already string, no conversion needed
            EndSelect

         ; V1.022.64: Array resize operation
         Case #ljARRAYRESIZE
            ; Emit ARRAYRESIZE opcode
            ; Node fields: value = array name, paramCount = new size, TypeHint = isLocal
            Protected resizeArrayName.s = *x\value
            Protected resizeNewSize.i = *x\paramCount
            Protected resizeIsLocal.i = *x\TypeHint
            Protected resizeVarSlot.i
            Protected resizeSlotToEmit.i

            ; Look up the array variable slot
            resizeVarSlot = FetchVarOffset(resizeArrayName)

            ; Determine which slot to emit (paramOffset for local, varSlot for global)
            If resizeIsLocal
               resizeSlotToEmit = gVarMeta(resizeVarSlot)\paramOffset
            Else
               resizeSlotToEmit = resizeVarSlot
            EndIf

            ; Emit the resize instruction using EmitInt + llObjects fields
            ; _AR()\i = array slot (global varSlot or local paramOffset)
            ; _AR()\j = new size
            ; _AR()\n = isLocal flag
            EmitInt(#ljARRAYRESIZE, resizeSlotToEmit)
            llObjects()\j = resizeNewSize
            llObjects()\n = resizeIsLocal

         Default
            SetError("Error in CodeGenerator at node " + Str(*x\NodeType) + " " + *x\value + " ---> " + gszATR(*x\NodeType)\s, #C2ERR_CODEGEN_FAILED)

      EndSelect

      gCodeGenRecursionDepth - 1

      ; Reset code generation state when returning from root level
      ; This ensures clean state for next compilation even if Init() isn't called
      If gCodeGenRecursionDepth = 0
         gCodeGenFunction = 0
         gCodeGenParamIndex = -1
         gCodeGenLocalIndex = 0
         gCurrentFunctionName = ""
      EndIf
   EndProcedure
    
   Procedure            ListCode( gadget = 0 )
      Protected         i
      Protected         flag
      Protected.s       temp, line, FullCode

      Debug ";--"
      Debug ";-- Variables & Constants --"
      Debug ";--"

      For i = 0 To gnLastVariable - 1
         If gVarMeta(i)\flags & #C2FLAG_INT
            temp = "Integer"
         ElseIf gVarMeta(i)\flags & #C2FLAG_FLOAT
            temp = "Float"
         ElseIf gVarMeta(i)\flags & #C2FLAG_STR
            temp = "String"
         ElseIf gVarMeta(i)\flags & #C2FLAG_IDENT
            temp = "Variable"
         EndIf

         If gVarMeta(i)\flags & #C2FLAG_CONST
            temp + " constant"
         EndIf

         Debug RSet(Str(i),6, " ") + "   " + LSet(gVarMeta(i)\name,20," ") + "  (" + temp + ")"
      Next

      Debug ";--"
      Debug ";--     Code Section      --"
      Debug ";--"

      ForEach llObjects()
         ASMLine( llObjects(),0 )
         Debug Line
         FullCode + Line +  #CRLF$
      Next

      Debug ";--"
      Debug ";--     End Program       --"
      Debug ";--"
      ;SetClipboardText( FullCode )
   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 64
; FirstLine = 36
; Folding = ---
; Markers = 1894,1972
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 1
; EnableBuildCount = 0
; EnableExeConstant