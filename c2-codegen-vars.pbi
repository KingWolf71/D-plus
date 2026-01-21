; c2-codegen-vars.pbi
; Variable resolution for code generation
; V1.035.9: Initial creation - extracted from c2-codegen-v08.pbi
;
; Contains:
; - FetchVarOffset() - Variable slot lookup and creation
;
; Dependencies: c2-inc-v19.pbi

   ; OSDebug macro for conditional debug output (same as in c2-codegen-emit.pbi)
   CompilerIf Defined(OSDEBUG_VARS, #PB_Constant) = 0
      #OSDEBUG_VARS = 0
   CompilerEndIf
   Macro OSDebug_Vars(msg)
      CompilerIf #OSDEBUG_VARS
         PrintN(msg)
      CompilerEndIf
   EndMacro

   Procedure            FetchVarOffset(text.s, *assignmentTree.stTree = 0, syntheticType.i = 0, forceLocal.i = #False)
      ; V1.030.56: Debug slot 176 at ABSOLUTE START of FetchVarOffset (before any Protected)
      CompilerIf #DEBUG
         If gnLastVariable > 176 And gCurrentFunctionName = "_calculatearea"
            ; Debug "V1.030.56: FVO ABSOLUTE START slot176 structType='" + gVarMeta(176)\structType + "' text='" + text + "'"
         EndIf
      CompilerEndIf
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
      ; V1.029.10: DOT notation handling variables
      Protected         dotPos.i
      Protected         dotStructName.s
      Protected         dotFieldChain.s
      Protected         dotMangledName.s
      Protected         dotStructSlot.i
      Protected         dotStructType.s
      Protected         dotFieldOffset.i
      Protected         dotCurrentType.s
      Protected         dotRemaining.s
      Protected         dotFieldFound.b
      Protected         dotNextDot.i
      Protected         dotCurrentField.s
      ; V1.030.33: Backslash notation handling variables
      Protected         bsFieldChain.s
      Protected         bsCurrentType.s
      Protected         bsAccumOffset.i
      Protected         bsFieldFound.b
      Protected         bsTraversedNested.b
      Protected         bsNextSlash.i
      Protected         bsCurrentField.s
      Protected         bsIsLocalStruct.b
      ; V1.022.100: Token search variables
      Protected         tokenSearchName.s
      Protected         prefixLen.i
      ; V1.029.86: Struct variable flags
      Protected         structVarFlags.i

      ; V1.030.55: Debug slot 176 IMMEDIATELY after Protected declarations (before any code)
      CompilerIf #DEBUG
         If gnLastVariable > 176 And gCurrentFunctionName = "_calculatearea"
            ; Debug "V1.030.55: POST-PROTECTED slot176 structType='" + gVarMeta(176)\structType + "' text='" + text + "'"
         EndIf
      CompilerEndIf

      j = -1
      structFieldPos = 0

      ; V1.030.53: Debug slot 176 at ENTRY of FetchVarOffset for _calculatearea
      CompilerIf #DEBUG
         Static fvo176LastStructType.s = ""
         If gnLastVariable > 176 And gCurrentFunctionName = "_calculatearea"
            If gVarMeta(176)\structType <> fvo176LastStructType
               ; Debug "V1.030.53: FVO ENTRY slot176 CHANGED! was '" + fvo176LastStructType + "' now '" + gVarMeta(176)\structType + "' text='" + text + "'"
               fvo176LastStructType = gVarMeta(176)\structType
            EndIf
         EndIf
      CompilerEndIf
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
         If FindMapElement(mapConstStr(), text)
            ProcedureReturn mapConstStr()
         EndIf
      EndIf

      ; V1.029.10: Handle DOT notation struct field names (e.g., "r.bottomRight.x")
      ; This is used when accessing local struct parameter fields with dot notation
      dotPos = FindString(text, ".")
      If dotPos > 0 And dotPos < Len(text)
         ; Not a type suffix (.i, .f, .s) - check if first part is a local struct param
         dotStructName = Trim(Left(text, dotPos - 1))
         dotFieldChain = Trim(Mid(text, dotPos + 1))
         dotStructSlot = -1

         ; V1.031.29: Debug DOT notation entry
         If LCase(dotStructName) = "local"
            OSDebug_Vars("V1.031.29: DOT ENTRY: text='" + text + "' dotStructName='" + dotStructName + "' dotFieldChain='" + dotFieldChain + "' gCurrentFunctionName='" + gCurrentFunctionName + "'")
         EndIf

         ; Look for mangled local struct first
         If gCurrentFunctionName <> ""
            dotMangledName = gCurrentFunctionName + "_" + dotStructName
            ; V1.031.29: Debug search for local struct
            If LCase(dotStructName) = "local"
               OSDebug_Vars("V1.031.29: DOT SEARCH LOCAL: searching for mangled='" + dotMangledName + "'")
            EndIf
            For i = 0 To gnLastVariable - 1
               If LCase(Trim(gVarMeta(i)\name)) = LCase(dotMangledName) And (gVarMeta(i)\flags & #C2FLAG_STRUCT)
                  dotStructSlot = i
                  ; V1.031.29: Debug found local struct
                  If LCase(dotStructName) = "local"
                     OSDebug_Vars("V1.031.29: DOT FOUND LOCAL: slot=" + Str(i) + " name='" + gVarMeta(i)\name + "' flags=$" + Hex(gVarMeta(i)\flags,#PB_Word))
                  EndIf
                  Break
               EndIf
            Next
         EndIf

         ; V1.029.15: If not found as mangled local, search for struct PARAMETER (non-mangled, paramOffset >= 0)
         ; V1.029.17: Also check structType since params might not have #C2FLAG_STRUCT flag
         If dotStructSlot < 0 And gCurrentFunctionName <> ""
            For i = 0 To gnLastVariable - 1
               If LCase(Trim(gVarMeta(i)\name)) = LCase(dotStructName) And gVarMeta(i)\paramOffset >= 0
                  ; Found by name and paramOffset - check if it's a struct (either by flag or structType)
                  If (gVarMeta(i)\flags & #C2FLAG_STRUCT) Or gVarMeta(i)\structType <> ""
                     dotStructSlot = i
                     Break
                  EndIf
               EndIf
            Next
         EndIf

         ; V1.029.12: If not found as local/param, search for GLOBAL struct with exact name (paramOffset = -1)
         If dotStructSlot < 0
            For i = 0 To gnLastVariable - 1
               If LCase(Trim(gVarMeta(i)\name)) = LCase(dotStructName) And (gVarMeta(i)\flags & #C2FLAG_STRUCT) And gVarMeta(i)\paramOffset = -1
                  dotStructSlot = i
                  Break
               EndIf
            Next
         EndIf

         ; If found as local or global struct, compute field offset from chain
         If dotStructSlot >= 0
            ; V1.029.14: If local struct hasn't had paramOffset assigned yet, assign it now
            ; This can happen when struct was created in AST but first accessed in codegen via DOT notation
            ;Debug "DOT PARAMOFFSET CHECK: slot=" + Str(dotStructSlot) + " paramOffset=" + Str(gVarMeta(dotStructSlot)\paramOffset) + " gCodeGenFunction=" + Str(gCodeGenFunction) + " gCodeGenParamIndex=" + Str(gCodeGenParamIndex)
            If gVarMeta(dotStructSlot)\paramOffset < 0 And gCodeGenFunction > 0 And gCodeGenParamIndex < 0
               ; Check if it's actually a local (mangled name)
               ; V1.030.15: Debug the comparison
               ; Debug "V1.030.15: PARAMOFFSET CHECK - slot=" + Str(dotStructSlot) + " name='" + gVarMeta(dotStructSlot)\name + "' gCurrentFunctionName='" + gCurrentFunctionName + "'"
               ; Debug "V1.030.15: LEFT='" + LCase(Left(gVarMeta(dotStructSlot)\name, Len(gCurrentFunctionName) + 1)) + "' RIGHT='" + LCase(gCurrentFunctionName + "_") + "' MATCH=" + Str(Bool(LCase(Left(gVarMeta(dotStructSlot)\name, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")))
               If LCase(Left(gVarMeta(dotStructSlot)\name, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
                  ; V1.029.43: With \ptr storage, each struct uses only 1 slot.
                  ; Only assign paramOffset to base slot - no field slots exist.
                  gVarMeta(dotStructSlot)\paramOffset = gCodeGenLocalIndex
                  Debug "DOT PARAMOFFSET ASSIGNED: slot=" + Str(dotStructSlot) + " paramOffset=" + Str(gCodeGenLocalIndex)
                  gCodeGenLocalIndex + 1

                  ; Update nLocals in mapModules
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                        Break
                     EndIf
                  Next
               EndIf
            EndIf

            dotStructType = gVarMeta(dotStructSlot)\structType
            dotFieldOffset = 0
            dotCurrentType = dotStructType
            dotRemaining = dotFieldChain
            dotFieldFound = #True

            ; V1.030.60: Debug - trace field chain walk with slot info
            OSDebug_Vars("V1.031.29: DOT FIELD WALK START: slot=" + Str(dotStructSlot) + " name='" + gVarMeta(dotStructSlot)\name + "' structType='" + dotStructType + "' fieldChain='" + dotFieldChain + "'")
            If dotStructType = ""
               OSDebug_Vars("V1.031.29: WARNING - structType is EMPTY! This will cause field walk to fail.")
            EndIf

            ; Walk the field chain (e.g., "bottomRight.x" -> bottomRight(+2) then x(+0))
            While dotRemaining <> "" And dotFieldFound
               dotNextDot = FindString(dotRemaining, ".")
               If dotNextDot > 0
                  dotCurrentField = Left(dotRemaining, dotNextDot - 1)
                  dotRemaining = Mid(dotRemaining, dotNextDot + 1)
               Else
                  dotCurrentField = dotRemaining
                  dotRemaining = ""
               EndIf

               ; Debug "V1.030.39: DOT FIELD STEP: looking for '" + dotCurrentField + "' in type '" + dotCurrentType + "'"

               dotFieldFound = #False
               If FindMapElement(mapStructDefs(), dotCurrentType)
                  ForEach mapStructDefs()\fields()
                     If LCase(mapStructDefs()\fields()\name) = LCase(dotCurrentField)
                        ; Debug "V1.030.39: DOT FIELD FOUND: '" + dotCurrentField + "' at offset=" + Str(mapStructDefs()\fields()\offset) + " nestedType='" + mapStructDefs()\fields()\structType + "'"
                        dotFieldOffset = dotFieldOffset + mapStructDefs()\fields()\offset
                        dotCurrentType = mapStructDefs()\fields()\structType  ; For nested structs
                        dotFieldFound = #True
                        Break
                     EndIf
                  Next
                  If Not dotFieldFound
                     ; Debug "V1.030.39: DOT FIELD NOT FOUND: '" + dotCurrentField + "' in type '" + dotCurrentType + "'"
                  EndIf
               Else
                  ; Debug "V1.030.39: DOT TYPE NOT FOUND: '" + dotCurrentType + "' in mapStructDefs()"
               EndIf
            Wend
            ; Debug "V1.030.39: DOT FIELD WALK END: totalOffset=" + Str(dotFieldOffset) + " byteOffset=" + Str(dotFieldOffset * 8) + " dotFieldFound=" + Str(dotFieldFound)

            ; V1.030.60: FIX - Only return if field was actually found
            ; The old condition "dotFieldFound Or dotRemaining = ''" was buggy:
            ; After processing last field, dotRemaining="" regardless of whether field was found.
            ; This caused "False Or True = True" to return with partial offset when final field wasn't found.
            If dotFieldFound
               ; V1.029.63: With \ptr storage, return the BASE slot for DOT field access
               ; Field byte offset is stored in structFieldOffset for STRUCT_FETCH/STORE opcodes
               ; This is consistent with backslash notation handling at line 891-893
               ; EmitInt looks up field type dynamically from mapStructDefs using byte offset
               gVarMeta(dotStructSlot)\structFieldBase = dotStructSlot
               gVarMeta(dotStructSlot)\structFieldOffset = dotFieldOffset * 8
               CompilerIf #DEBUG
                  ; Debug "V1.030.37: DOT FIELD OFFSET: slot=" + Str(dotStructSlot) + " fieldChain='" + dotFieldChain + "' fieldOffset=" + Str(dotFieldOffset) + " byteOffset=" + Str(dotFieldOffset * 8)
               CompilerEndIf
               ProcedureReturn dotStructSlot
            Else
               ; V1.031.29: FIX - Field walk failed but we found an existing struct.
               ; Check if dotFieldChain is actually the struct TYPE (not a field name).
               ; Example: "local.Point" where Point is the struct type, not a field.
               ; In this case, return the existing struct slot.
               If LCase(dotFieldChain) <> "i" And LCase(dotFieldChain) <> "f" And LCase(dotFieldChain) <> "s" And LCase(dotFieldChain) <> "d"
                  If FindMapElement(mapStructDefs(), dotFieldChain)
                     ; dotFieldChain is a struct type name, not a field!
                     ; This is a type annotation referring to existing struct variable.
                     OSDebug_Vars("V1.031.29: DOT EXISTING STRUCT: slot=" + Str(dotStructSlot) + " is struct type '" + dotFieldChain + "' - returning existing")
                     ProcedureReturn dotStructSlot
                  EndIf
               EndIf
            EndIf
         EndIf

         ; V1.029.84: If struct/field not found, check if this is a struct type annotation (e.g., "person.Person")
         ; This handles declarations like: person.Person = { }
         If dotStructSlot < 0 And dotFieldChain <> ""
            ; V1.031.29: Debug struct type annotation detection
            OSDebug_Vars("V1.031.29: STRUCT TYPE CHECK: dotStructName='" + dotStructName + "' dotFieldChain='" + dotFieldChain + "' mapStructDefs has Point=" + Str(Bool(FindMapElement(mapStructDefs(), "Point") <> 0)))
            CompilerIf #DEBUG
               ; Debug "V1.029.86: Checking struct type annotation: dotStructName='" + dotStructName + "' dotFieldChain='" + dotFieldChain + "'"
            CompilerEndIf
            ; Check if dotFieldChain is a known struct type (not primitive .i, .f, .s, .d)
            If LCase(dotFieldChain) <> "i" And LCase(dotFieldChain) <> "f" And LCase(dotFieldChain) <> "s" And LCase(dotFieldChain) <> "d"
               If FindMapElement(mapStructDefs(), dotFieldChain)
                  ; This is a struct type annotation! Use base name only
                  text = dotStructName
                  ; Store struct type to set later when creating the variable
                  structTypeName = dotFieldChain
                  ; V1.031.29: Debug detected struct type
                  OSDebug_Vars("V1.031.29: STRUCT TYPE DETECTED! text='" + text + "' structTypeName='" + structTypeName + "'")
                  CompilerIf #DEBUG
                     ; Debug "V1.029.86: DETECTED struct type annotation! structTypeName='" + structTypeName + "' text='" + text + "'"
                  CompilerEndIf
               Else
                  OSDebug_Vars("V1.031.29: STRUCT TYPE MISS! dotFieldChain '" + dotFieldChain + "' NOT in mapStructDefs()")
                  CompilerIf #DEBUG
                     ; Debug "V1.029.86: dotFieldChain '" + dotFieldChain + "' NOT found in mapStructDefs()"
                  CompilerEndIf
               EndIf
            Else
               ; V1.030.63: FIX - Type suffix detected (.i, .f, .s, .d) and no struct found
               ; Strip type suffix from text so variable is named correctly
               ; Without this fix, "w.f" stays as "w.f" causing wrong slot lookup
               text = dotStructName
               CompilerIf #DEBUG
                  ; Debug "V1.030.63: Type suffix stripped in DOT path: dotFieldChain='" + dotFieldChain + "' text='" + text + "'"
               CompilerEndIf
            EndIf
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

         ; V1.030.36: If not found as local, search for struct PARAMETER (non-mangled, paramOffset >= 0)
         If structSlot < 0 And gCurrentFunctionName <> ""
            For i = 0 To gnLastVariable - 1
               If LCase(Trim(gVarMeta(i)\name)) = LCase(structName) And gVarMeta(i)\paramOffset >= 0
                  If (gVarMeta(i)\flags & #C2FLAG_STRUCT) Or gVarMeta(i)\structType <> ""
                     structSlot = i
                     Break
                  EndIf
               EndIf
            Next
         EndIf

         ; If not found as local or parameter, try global
         If structSlot < 0
            For i = 0 To gnLastVariable - 1
               If LCase(Trim(gVarMeta(i)\name)) = LCase(structName) And (gVarMeta(i)\flags & #C2FLAG_STRUCT)
                  structSlot = i
                  Break
               EndIf
            Next
         EndIf

         ; If struct found, look up field offset
         ; V1.030.33: Handle nested struct field chains (e.g., "topLeft\x" for localRect\topLeft\x)
         ; Walk through backslash-separated fields, accumulating offsets like DOT path does
         If structSlot >= 0
            structTypeName = gVarMeta(structSlot)\structType
            bsFieldChain = fieldName
            bsCurrentType = structTypeName
            bsAccumOffset = 0
            bsFieldFound = #True
            bsTraversedNested = #False  ; V1.030.35: Track if we went through nested struct

            While bsFieldChain <> "" And bsFieldFound
               bsNextSlash = FindString(bsFieldChain, "\")
               If bsNextSlash > 0
                  bsCurrentField = Left(bsFieldChain, bsNextSlash - 1)
                  bsFieldChain = Mid(bsFieldChain, bsNextSlash + 1)
               Else
                  bsCurrentField = bsFieldChain
                  bsFieldChain = ""
               EndIf

               bsFieldFound = #False
               If FindMapElement(mapStructDefs(), bsCurrentType)
                  ForEach mapStructDefs()\fields()
                     If LCase(Trim(mapStructDefs()\fields()\name)) = LCase(bsCurrentField)
                        ; V1.030.66: Debug - trace field offset lookup in backslash chain
                        ; Debug "V1.030.66 FIELD_LOOKUP: type='" + bsCurrentType + "' field='" + bsCurrentField + "' storedOffset=" + Str(mapStructDefs()\fields()\offset) + " prevAccum=" + Str(bsAccumOffset)
                        bsAccumOffset = bsAccumOffset + mapStructDefs()\fields()\offset
                        ; V1.030.35: Track if this field is a nested struct that we continue to traverse
                        If mapStructDefs()\fields()\structType <> "" And bsFieldChain <> ""
                           bsTraversedNested = #True
                        EndIf
                        bsCurrentType = mapStructDefs()\fields()\structType  ; For nested structs
                        bsFieldFound = #True
                        Break
                     EndIf
                  Next
               EndIf
            Wend

            fieldOffset = bsAccumOffset
            fieldFound = bsFieldFound

            If fieldFound
               ; V1.030.34/35: Check if struct is LOCAL or if we need flattened slots
               ; LOCAL structs always use \ptr storage
               ; GLOBAL structs use \ptr for simple fields, flattened slots for nested fields
               bsIsLocalStruct = #False
               If gVarMeta(structSlot)\paramOffset >= 0
                  ; Already has paramOffset assigned - it's local
                  bsIsLocalStruct = #True
               ElseIf gCodeGenFunction > 0 And gCodeGenParamIndex < 0
                  ; Check if it's a local struct (mangled name = function_varname)
                  If LCase(Left(gVarMeta(structSlot)\name, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
                     bsIsLocalStruct = #True
                     ; V1.030.25: Assign paramOffset for local struct
                     gVarMeta(structSlot)\paramOffset = gCodeGenLocalIndex
                     gCodeGenLocalIndex + 1

                     ; Update nLocals in mapModules
                     ForEach mapModules()
                        If mapModules()\function = gCodeGenFunction
                           mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                           Break
                        EndIf
                     Next
                     CompilerIf #DEBUG
                        ; Debug "V1.030.25: Backslash path - assigned paramOffset=" + Str(gVarMeta(structSlot)\paramOffset) + " to local struct '" + gVarMeta(structSlot)\name + "'"
                     CompilerEndIf
                  EndIf
               EndIf

               ; V1.030.59: ALWAYS use \ptr storage for struct field access
               ; Previously V1.030.35 used flattened slots for global nested fields,
               ; but this broke SCOPY and FETCH_STRUCT which expect \ptr storage.
               ; - LOCAL structs: Use \ptr storage (structFieldBase)
               ; - GLOBAL structs: Use \ptr storage (structFieldBase) - fixes SCOPY/params!
               ; V1.029.43: With \ptr storage, return the BASE slot for field access.
               ; Field byte offset is stored in structFieldOffset for STRUCT_FETCH/STORE opcodes.
               gVarMeta(structSlot)\structFieldBase = structSlot
               gVarMeta(structSlot)\structFieldOffset = fieldOffset * 8
               ; V1.030.66: Debug - trace backslash chain byte offset calculation
               ; Debug "V1.030.66 BACKSLASH: name='" + gVarMeta(structSlot)\name + "' fieldChain='" + text + "' slotOffset=" + Str(fieldOffset) + " byteOffset=" + Str(fieldOffset * 8) + " paramOffset=" + Str(gVarMeta(structSlot)\paramOffset)
               ProcedureReturn structSlot
            EndIf
         EndIf
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
               ; V1.026.20: Fix for local collections - assign paramOffset if not yet set
               ; Variable may have been created during AST parsing when gCodeGenFunction was 0
               ; Now in CodeGenerator, we can assign the proper paramOffset
               If gVarMeta(i)\paramOffset < 0 And gCodeGenFunction > 0 And gCodeGenParamIndex < 0
                  ; V1.029.43: With \ptr storage, each struct uses only 1 slot.
                  ; Only assign paramOffset to base slot - no field slots exist.
                  gVarMeta(i)\paramOffset = gCodeGenLocalIndex
                  gCodeGenLocalIndex + 1

                  ; Update nLocals in mapModules
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                        Break
                     EndIf
                  Next
                  CompilerIf #DEBUG
                     ; Debug "V1.026.20: Assigned paramOffset=" + Str(gVarMeta(i)\paramOffset) + " to local '" + searchName + "'"
                  CompilerEndIf
               EndIf
               ; V1.029.98: Clear struct field metadata when returning whole variable (not field access)
               ; This prevents stale values from DOT/backslash accesses affecting whole-struct references
               gVarMeta(i)\structFieldBase = -1
               gVarMeta(i)\structFieldOffset = 0
               ProcedureReturn i  ; Found local variable
            EndIf
         Next

         ; V1.029.94: If mangled name not found, search for param with non-mangled name
         ; This handles the case where param was created during #ljPOP (before gCurrentFunctionName was set)
         ; and now we're in the function body trying to find it with the mangled name.
         ; Params have paramOffset >= 0 and PARAM flag set.
         For i = 0 To gnLastVariable - 1
            If LCase(gVarMeta(i)\name) = LCase(text) And gVarMeta(i)\paramOffset >= 0
               If gVarMeta(i)\flags & #C2FLAG_PARAM
                  ; Found as non-mangled param - use it
                  CompilerIf #DEBUG
                     ; Debug "V1.029.94: Found non-mangled param '" + text + "' at slot " + Str(i) + " (paramOffset=" + Str(gVarMeta(i)\paramOffset) + ")"
                  CompilerEndIf
                  ; V1.029.98: Clear struct field metadata when returning whole variable
                  gVarMeta(i)\structFieldBase = -1
                  gVarMeta(i)\structFieldOffset = 0
                  ProcedureReturn i
               EndIf
            EndIf
         Next

         ; Not found as local - check if global exists (unless forceLocal is set)
         ; V1.022.71: forceLocal=true when type annotation present (.i/.f/.s)
         ; var = expr (no type) --> uses global if exists
         ; var.type = expr (with type) --> creates local (shadows global)
         ; V1.029.79: Don't check gCodeGenParamIndex < 0 (same fix as lines 965 and 1048)

         If forceLocal = #False
            ; No type annotation - check if global exists and use it
            For i = 0 To gnLastVariable - 1
               ; V1.035.18: Skip constants - string "X" should not match variable "x"
               If gVarMeta(i)\flags & #C2FLAG_CONST
                  Continue
               EndIf
               If LCase(gVarMeta(i)\name) = LCase(text) And gVarMeta(i)\paramOffset = -1
                  ; Found as global - use it (intended behavior for var = expr)
                  CompilerIf #DEBUG
                     Debug "FetchVarOffset: Found global '" + text + "' at slot " + Str(i)
                  CompilerEndIf
                  ; V1.029.98: Clear struct field metadata when returning whole variable
                  gVarMeta(i)\structFieldBase = -1
                  gVarMeta(i)\structFieldOffset = 0
                  ProcedureReturn i
               EndIf
            Next
         ElseIf forceLocal
            ; V1.022.71: Type annotation present - create local (shadow global if exists)
            CompilerIf #DEBUG
               ; Debug "V1.022.71: Type annotation - creating local '" + text + "' (shadows global if exists)"
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
            ; V1.029.77: Don't check gCodeGenParamIndex < 0 (same fix as for new variables)
            If gCurrentFunctionName <> "" And gCodeGenFunction > 0
               If gVarMeta(i)\paramOffset < 0
                  ; This is a local variable without an offset - assign one
                  ; V1.022.31: Don't assign local offsets to $ synthetic temps - they're forced global
                  ; by GetExprSlotOrTemp. Including them here caused gaps in local slot numbering.
                  ; V1.029.77: Also check NOT a parameter (same as line 1052)
                  If LCase(Left(text, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
                     If (gVarMeta(i)\flags & #C2FLAG_PARAM) = 0
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
            EndIf
            ; V1.029.98: Clear struct field metadata when returning whole variable
            gVarMeta(i)\structFieldBase = -1
            gVarMeta(i)\structFieldOffset = 0
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
         tokenSearchName = text
         If gCurrentFunctionName <> ""
            prefixLen = Len(gCurrentFunctionName) + 1  ; "functionname_"
            If LCase(Left(text, prefixLen)) = LCase(gCurrentFunctionName + "_")
               ; Extract original name after the function prefix
               tokenSearchName = Mid(text, prefixLen + 1)
               CompilerIf #DEBUG
                  ; Debug "V1.022.100: Searching for original '" + tokenSearchName + "' (mangled: '" + text + "')"
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
                  ; Debug "V1.022.100: Found token '" + tokenSearchName + "' typeHint=" + Str(foundTokenTypeHint) + " tokenType=" + Str(foundTokenType)
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
      ; V1.029.44: Initialize structFieldBase to -1 (not a struct field)
      ; This prevents false positives when checking for struct field access
      gVarMeta(gnLastVariable)\structFieldBase = -1

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
         ; V1.039.50: Add to constant map for deduplication
         AddMapElement(mapConstInt(), text)
         mapConstInt() = gnLastVariable
      ElseIf syntheticType = #ljFLOAT
         gVarMeta(gnLastVariable)\valueFloat = ValF(text)
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
         ; V1.039.50: Add to constant map for deduplication
         AddMapElement(mapConstFloat(), text)
         mapConstFloat() = gnLastVariable
      ElseIf syntheticType = #ljSTRING
         gVarMeta(gnLastVariable)\valueString = text
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_STR
         ; V1.039.50: Add to constant map for deduplication
         AddMapElement(mapConstStr(), text)
         mapConstStr() = gnLastVariable
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
                  ; Debug "V1.022.100: Set FLOAT type for '" + text + "' from token typeHint"
               CompilerEndIf
            ElseIf foundTokenTypeHint = #ljSTRING
               gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_STR
               CompilerIf #DEBUG
                  ; Debug "V1.022.100: Set STR type for '" + text + "' from token typeHint"
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

      ; V1.029.83: Set struct type and flag if this is a struct variable (e.g., "person.Person")
      If structTypeName <> ""
         gVarMeta(gnLastVariable)\structType = structTypeName
         ; V1.029.87: Set elementSize for struct byte size calculation in STRUCT_ALLOC
         If FindMapElement(mapStructDefs(), structTypeName)
            gVarMeta(gnLastVariable)\elementSize = mapStructDefs()\totalSize
         Else
            gVarMeta(gnLastVariable)\elementSize = 1  ; Default to 1 field if struct not found
         EndIf
         ; V1.029.86: Set flags explicitly - IDENT + STRUCT only (remove primitive type flags)
         ; Preserve CONST flag if present
         structVarFlags = #C2FLAG_IDENT | #C2FLAG_STRUCT
         If gVarMeta(gnLastVariable)\flags & #C2FLAG_CONST
            structVarFlags = structVarFlags | #C2FLAG_CONST
         EndIf
         gVarMeta(gnLastVariable)\flags = structVarFlags
         CompilerIf #DEBUG
            ; Debug "V1.029.87: Set struct type '" + structTypeName + "' for variable '" + text + "' with elementSize=" + Str(gVarMeta(gnLastVariable)\elementSize) + " (flags=" + Str(gVarMeta(gnLastVariable)\flags) + ")"
         CompilerEndIf
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

      ; V1.030.63: Debug - track new variable creation for w/h
      If FindString(text, "_w") Or FindString(text, "_h")
         ; Debug "V1.030.63 NEW_VAR: slot=" + Str(gnLastVariable - 1) + " name='" + text + "' structFieldBase=" + Str(gVarMeta(gnLastVariable - 1)\structFieldBase) + " paramOffset=" + Str(gVarMeta(gnLastVariable - 1)\paramOffset)
      EndIf

      ProcedureReturn gnLastVariable - 1
   EndProcedure
