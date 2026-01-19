; c2-codegen-lookup.pbi
; O(1) variable lookup wrappers for code generation
; V1.035.0: Initial creation - standardizes access to MapCodeElements system
; V1.035.12: Consolidated GetCodeElement, FindVariableSlot, RegisterCodeElement from c2-codegen-v08.pbi
;
; Purpose: Provide consistent O(1) variable lookup interface for codegen,
; replacing scattered O(N) For loops with centralized map-based lookups.
;
; Note: Core O(1 infrastructure (maps) defined in:
;   - c2-modules-V23.pb: MapCodeElements, MapLocalByOffset, FindVariableSlotByName,
;     FindVariableSlotByOffset, FindStructSlotByName

;- ============================================================================
;- Core Code Element Functions (V1.035.12: moved from c2-codegen-v08.pbi)
;- ============================================================================

; Get code element by name with optional function context
; Returns pointer to stCodeElement or #Null if not found
Procedure.i          GetCodeElement(name.s, functionContext.s = "")
   Protected key.s, mangledKey.s

   ; Try function-local name first (if in function context)
   If functionContext <> ""
      mangledKey = LCase(functionContext + "_" + name)
      If FindMapElement(MapCodeElements(), mangledKey)
         ProcedureReturn @MapCodeElements()
      EndIf
   EndIf

   ; Try global name
   key = LCase(name)
   If FindMapElement(MapCodeElements(), key)
      ProcedureReturn @MapCodeElements()
   EndIf

   ProcedureReturn #Null
EndProcedure

; Find variable slot by name using O(1) map lookup
; Returns slot index or -1 if not found
Procedure.i          FindVariableSlot(name.s, functionContext.s = "")
   Protected *elem.stCodeElement

   *elem = GetCodeElement(name, functionContext)
   If *elem
      ProcedureReturn *elem\varSlot
   EndIf

   ProcedureReturn -1
EndProcedure

; Compatibility wrapper: tries O(1) map first, falls back to O(N) scan
; Use during migration - will be removed once all code uses map
Procedure.i          FindVariableSlotCompat(name.s, functionContext.s = "")
   Protected *elem.stCodeElement, i.i, searchName.s

   ; Try O(1) map lookup first
   *elem = GetCodeElement(name, functionContext)
   If *elem
      ProcedureReturn *elem\varSlot
   EndIf

   ; Fall back to O(N) scan for variables not yet in map
   If functionContext <> ""
      searchName = LCase(functionContext + "_" + name)
      For i = 0 To gnLastVariable - 1
         If LCase(gVarMeta(i)\name) = searchName
            ProcedureReturn i
         EndIf
      Next
   EndIf

   ; Try global name
   searchName = LCase(name)
   For i = 0 To gnLastVariable - 1
      If LCase(gVarMeta(i)\name) = searchName
         ProcedureReturn i
      EndIf
   Next

   ProcedureReturn -1
EndProcedure


; Register a variable in MapCodeElements (call after creating gVarMeta entry)
; This syncs the map with gVarMeta for O(1) lookup
Procedure            RegisterCodeElement(slot.i, functionContext.s = "")
   Protected key.s, elemType.w, offsetKey.s

   If slot < 0 Or slot >= gnLastVariable
      ProcedureReturn
   EndIf

   ; Build lookup key
   If functionContext <> "" And gVarMeta(slot)\paramOffset >= 0
      key = LCase(functionContext + "_" + gVarMeta(slot)\name)
   Else
      key = LCase(gVarMeta(slot)\name)
   EndIf

   ; Skip if already registered
   If FindMapElement(MapCodeElements(), key)
      ProcedureReturn
   EndIf

   ; Determine element type
   If gVarMeta(slot)\flags & #C2FLAG_CONST
      elemType = #ELEMENT_CONSTANT
   ElseIf gVarMeta(slot)\flags & #C2FLAG_ARRAY
      elemType = #ELEMENT_ARRAY
   ElseIf gVarMeta(slot)\flags & #C2FLAG_PARAM
      elemType = #ELEMENT_PARAMETER
   Else
      elemType = #ELEMENT_VARIABLE
   EndIf

   ; Create map entry
   AddMapElement(MapCodeElements(), key)
   MapCodeElements()\name = gVarMeta(slot)\name
   MapCodeElements()\id = slot
   MapCodeElements()\varSlot = slot
   MapCodeElements()\elementType = elemType
   MapCodeElements()\varType = gVarMeta(slot)\flags & #C2FLAG_TYPE
   MapCodeElements()\paramOffset = gVarMeta(slot)\paramOffset
   MapCodeElements()\functionContext = functionContext
   MapCodeElements()\structType = gVarMeta(slot)\structType
   MapCodeElements()\elementSize = gVarMeta(slot)\elementSize
   MapCodeElements()\size = gVarMeta(slot)\arraySize

   ; Set boolean flags
   MapCodeElements()\isIdent = Bool(gVarMeta(slot)\flags & #C2FLAG_IDENT)
   MapCodeElements()\isArray = Bool(gVarMeta(slot)\flags & #C2FLAG_ARRAY)
   MapCodeElements()\isPointer = Bool(gVarMeta(slot)\flags & #C2FLAG_POINTER)

   ; Copy constant values
   MapCodeElements()\valueInt = gVarMeta(slot)\valueInt
   MapCodeElements()\valueFloat = gVarMeta(slot)\valueFloat
   MapCodeElements()\valueString = gVarMeta(slot)\valueString

   ; V1.034.0: Also register in MapLocalByOffset for paramOffset-based lookup
   If functionContext <> "" And gVarMeta(slot)\paramOffset >= 0
      offsetKey = LCase(functionContext) + "_" + Str(gVarMeta(slot)\paramOffset)
      If Not FindMapElement(MapLocalByOffset(), offsetKey)
         MapLocalByOffset(offsetKey) = slot
      EndIf
      ; V1.039.21: Register local variable name for ASM display (strip function prefix)
      If Not FindMapElement(gAsmLocalNameMap(), offsetKey)
         Protected localName.s = gVarMeta(slot)\name
         Protected prefixLen.i = Len(functionContext) + 1  ; "funcname_"
         ; Strip function prefix if present (handles both "func_var" and "_func_var" formats)
         If LCase(Left(localName, prefixLen)) = LCase(functionContext) + "_"
            localName = Mid(localName, prefixLen + 1)
         ElseIf LCase(Left(localName, prefixLen + 1)) = "_" + LCase(functionContext) + "_"
            localName = Mid(localName, prefixLen + 2)
         EndIf
         gAsmLocalNameMap(offsetKey) = localName
      EndIf
   EndIf
EndProcedure

;- ============================================================================
;- Variable Lookup Interface
;- ============================================================================

; Unified variable lookup - tries all sources in priority order
;
; Priority:
;   1. O(1) map lookup (MapCodeElements)
;   2. O(N) fallback to gVarMeta scan
;
; Parameters:
;   name            - Variable name (with or without mangling)
;   functionContext - Current function name (for local variable mangling)
;   requireFlags    - Optional flags that must be present (e.g., #C2FLAG_STRUCT)
;
; Returns:
;   Slot index or -1 if not found
;
Procedure.i LookupVariable(name.s, functionContext.s = "", requireFlags.w = 0)
   Protected slot.i
   Protected key.s, mangledKey.s

   ; Try function-local mangled name first
   If functionContext <> ""
      mangledKey = LCase(functionContext + "_" + name)
      If FindMapElement(MapCodeElements(), mangledKey)
         slot = MapCodeElements()\varSlot
         If requireFlags = 0 Or (gVarMeta(slot)\flags & requireFlags)
            ProcedureReturn slot
         EndIf
      EndIf
   EndIf

   ; Try global/non-mangled name
   key = LCase(name)
   If FindMapElement(MapCodeElements(), key)
      slot = MapCodeElements()\varSlot
      If requireFlags = 0 Or (gVarMeta(slot)\flags & requireFlags)
         ProcedureReturn slot
      EndIf
   EndIf

   ; Fallback to O(N) scan
   Protected i.i

   ; Try mangled local first
   If functionContext <> ""
      For i = 1 To gnLastVariable - 1
         If LCase(gVarMeta(i)\name) = mangledKey
            If requireFlags = 0 Or (gVarMeta(i)\flags & requireFlags)
               ProcedureReturn i
            EndIf
         EndIf
      Next
   EndIf

   ; Try global
   For i = 1 To gnLastVariable - 1
      If LCase(gVarMeta(i)\name) = key
         If requireFlags = 0 Or (gVarMeta(i)\flags & requireFlags)
            ProcedureReturn i
         EndIf
      EndIf
   Next

   ProcedureReturn -1
EndProcedure

;- ============================================================================
;- Local Variable Lookup by Offset
;- ============================================================================

; Look up local variable by paramOffset
;
; Parameters:
;   paramOffset     - Local variable offset (0-based)
;   functionContext - Function name
;
; Returns:
;   Slot index or -1 if not found
;
Procedure.i LookupLocalByOffset(paramOffset.i, functionContext.s)
   ; Use existing O(1) function
   ProcedureReturn FindVariableSlotByOffset(paramOffset, functionContext)
EndProcedure

;- ============================================================================
;- Constant Lookup
;- ============================================================================

; Look up or create integer constant
Procedure.i LookupOrCreateIntConst(value.i)
   Protected key.s = Str(value)

   If FindMapElement(mapConstInt(), key)
      ProcedureReturn mapConstInt()
   EndIf

   ; Create new constant slot
   AddMapElement(mapConstInt(), key)
   mapConstInt() = gnLastVariable

   gVarMeta(gnLastVariable)\name = "$const_" + key
   gVarMeta(gnLastVariable)\flags = #C2FLAG_INT | #C2FLAG_CONST
   gVarMeta(gnLastVariable)\paramOffset = -1
   gnLastVariable + 1

   ProcedureReturn mapConstInt()
EndProcedure

; Look up or create float constant
Procedure.i LookupOrCreateFloatConst(value.d)
   Protected key.s = StrD(value, 10)

   If FindMapElement(mapConstFloat(), key)
      ProcedureReturn mapConstFloat()
   EndIf

   ; Create new constant slot
   AddMapElement(mapConstFloat(), key)
   mapConstFloat() = gnLastVariable

   gVarMeta(gnLastVariable)\name = "$constf_" + key
   gVarMeta(gnLastVariable)\flags = #C2FLAG_FLOAT | #C2FLAG_CONST
   gVarMeta(gnLastVariable)\paramOffset = -1
   gnLastVariable + 1

   ProcedureReturn mapConstFloat()
EndProcedure

; Look up or create string constant
Procedure.i LookupOrCreateStringConst(value.s)
   If FindMapElement(mapConstStr(), value)
      ProcedureReturn mapConstStr()
   EndIf

   ; Create new constant slot
   AddMapElement(mapConstStr(), value)
   mapConstStr() = gnLastVariable

   gVarMeta(gnLastVariable)\name = "$consts_" + Str(gnLastVariable)
   gVarMeta(gnLastVariable)\flags = #C2FLAG_STR | #C2FLAG_CONST
   gVarMeta(gnLastVariable)\paramOffset = -1
   gnLastVariable + 1

   ProcedureReturn mapConstStr()
EndProcedure

;- ============================================================================
;- Map Registration
;- ============================================================================

; Populate MapCodeElements from gVarMeta after compilation phase
; Call this once after AST/constants are extracted
Procedure PopulateCodeElementMaps()
   Protected i.i, key.s

   ClearMap(MapCodeElements())
   ClearMap(MapLocalByOffset())
   ; V1.039.29: Don't clear gAsmLocalNameMap - parameter names are added during codegen
   ; and would be lost if cleared here. Local variable names are added below.

   For i = 1 To gnLastVariable - 1
      If gVarMeta(i)\name <> ""
         ; Add to name lookup map
         key = LCase(gVarMeta(i)\name)
         If Not FindMapElement(MapCodeElements(), key)
            AddMapElement(MapCodeElements(), key)
            MapCodeElements()\varSlot = i
            MapCodeElements()\name = gVarMeta(i)\name
            MapCodeElements()\varType = gVarMeta(i)\flags & #C2FLAG_TYPE
            MapCodeElements()\paramOffset = gVarMeta(i)\paramOffset
         EndIf

         ; Add to offset lookup map for locals
         If gVarMeta(i)\paramOffset >= 0
            ; V1.039.21: Extract function context from mangled name
            ; Format: "_funcname_varname" - skip leading underscore, find next underscore
            Protected varName.s = gVarMeta(i)\name
            Protected startPos.i = 1
            ; Skip leading underscore if present
            If Left(varName, 1) = "_"
               startPos = 2
            EndIf
            Protected underscorePos.i = FindString(varName, "_", startPos)
            If underscorePos > startPos
               Protected funcContext.s = Mid(varName, startPos, underscorePos - startPos)
               key = LCase(funcContext) + "_" + Str(gVarMeta(i)\paramOffset)
               If Not FindMapElement(MapLocalByOffset(), key)
                  AddMapElement(MapLocalByOffset(), key)
                  MapLocalByOffset() = i
               EndIf
               ; V1.039.21: Also add to ASM local name map (variable name without function prefix)
               If Not FindMapElement(gAsmLocalNameMap(), key)
                  Protected localName.s = Mid(varName, underscorePos + 1)
                  gAsmLocalNameMap(key) = localName
               EndIf
            EndIf
         EndIf
      EndIf
   Next
EndProcedure

;- ============================================================================
;- Variable Existence Check
;- ============================================================================

; Check if variable exists (O(1) lookup)
Procedure.b VariableExists(name.s, functionContext.s = "")
   ProcedureReturn Bool(LookupVariable(name, functionContext) >= 0)
EndProcedure

; Check if local variable exists by offset
Procedure.b LocalExistsByOffset(paramOffset.i, functionContext.s)
   ProcedureReturn Bool(LookupLocalByOffset(paramOffset, functionContext) >= 0)
EndProcedure

;- ============================================================================
;- End of c2-codegen-lookup.pbi
;- ============================================================================

; IDE Options = PureBasic 6.10 (Windows - x64)
; CursorPosition = 1
; Folding = --
