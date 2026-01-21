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

   ; V1.035.8: OSDebug macro moved to c2-codegen-emit.pbi

   ; V1.031.114: Maximum else-if branches supported in iterative IF processing
   #MAX_ELSEIF_BRANCHES = 256

   Declare              CodeGenerator( *x.stTree, *link.stTree = 0 )

   ; V1.030.0: Variable metadata verification pass
   ; Checks for common metadata inconsistencies that cause runtime crashes
   ; V1.030.4: Added debug output to diagnose persistent crash
   Procedure.i          VerifyVariableMetadata()
      Protected i.i, errors.i = 0

      Debug "VERIFY: gnLastVariable=" + Str(gnLastVariable)

      ; V1.030.47: Debug dump of all struct params at start of codegen
      ; Debug "V1.030.47: STRUCT PARAM DUMP AT CODEGEN START:"
      For i = 0 To gnLastVariable - 1
         If (gVarMeta(i)\flags & #C2FLAG_PARAM) And (gVarMeta(i)\flags & #C2FLAG_STRUCT)
            Debug "  PARAM+STRUCT [" + Str(i) + "] '" + gVarMeta(i)\name + "' structType='" + gVarMeta(i)\structType + "' paramOffset=" + Str(gVarMeta(i)\paramOffset)
         EndIf
      Next
      ; Debug "V1.030.47: END STRUCT PARAM DUMP"

      For i = 0 To gnLastVariable - 1
         ; Skip empty/unused slots
         If gVarMeta(i)\name = ""
            Continue
         EndIf

         ; Check 1: Variables with structType MUST have STRUCT flag - AUTO-FIX
         If gVarMeta(i)\structType <> "" And Not (gVarMeta(i)\flags & #C2FLAG_STRUCT)
            Debug "VERIFY FIX [" + Str(i) + "] '" + gVarMeta(i)\name + "': structType='" + gVarMeta(i)\structType + "' flags=" + Str(gVarMeta(i)\flags) + " -> adding STRUCT flag"
            gVarMeta(i)\flags = (gVarMeta(i)\flags & ~#C2FLAG_TYPE) | #C2FLAG_STRUCT | #C2FLAG_IDENT
            errors + 1
         EndIf

         ; Check 2: Struct variables should have elementSize > 0 - AUTO-FIX
         If (gVarMeta(i)\flags & #C2FLAG_STRUCT) And gVarMeta(i)\elementSize = 0
            If gVarMeta(i)\structType <> "" And FindMapElement(mapStructDefs(), gVarMeta(i)\structType)
               gVarMeta(i)\elementSize = mapStructDefs()\totalSize
            EndIf
         EndIf
      Next

      Debug "VERIFY: Fixed " + Str(errors) + " variables"
      ProcedureReturn errors
   EndProcedure

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

   ; V1.035.8: IsLocalVar moved to c2-codegen-emit.pbi

   ; V1.035.12: O(1) Code Element Lookup Functions moved to c2-codegen-lookup.pbi
   ; - GetCodeElement
   ; - FindVariableSlot
   ; - FindVariableSlotCompat
   ; - RegisterCodeElement

   ; V1.035.8: MarkPreloadable and EmitInt moved to c2-codegen-emit.pbi


   ; V1.035.9: FetchVarOffset moved to c2-codegen-vars.pbi

   ; V1.035.10: Type helper functions moved to c2-codegen-types.pbi
   ; - GetExprResultType
   ; - GetExprSlotOrTemp
   ; - ContainsFunctionCall
   ; - CollectVariables

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
      ; V1.024.0: FOR loop and SWITCH statement variables
      Protected         *forInit.stTree, *forCond.stTree, *forUpdate.stTree, *forBody.stTree
      Protected         *caseList.stTree, *caseIter.stTree, *caseNode.stTree
      Protected         caseCount.i, caseIdx.i, defaultHole.i, hasDefault.i, foundLoop.i
      Protected         switchExprType.w     ; V1.024.4: Switch expression type for typed DUP
      ; V1.024.15: Use arrays instead of linked lists to avoid recursion issues
      Protected Dim     caseNodeArr.i(64)          ; Array of case node pointers (max 64 cases)
      Protected Dim     caseHoleArr.i(64)          ; Array of case hole IDs
      Protected         caseNodeArrCount.i         ; Number of entries in arrays
      ; V1.029.39: Struct field fetch variables (for STRUCT_FETCH_* codegen)
      Protected         sfBaseSlot.i, sfByteOffset.i, sfIsLocal.b, sfFieldType.w
      Protected         sfStructByteSize.i  ; V1.029.40: For lazy STRUCT_ALLOC
      ; V1.034.6: FOREACH variables
      Protected         *forEachColl.stTree, *forEachBody.stTree
      Protected         foreachIsMap.i, foreachSlot.i, foreachVarName.s
      ; V1.039.43: All inline Protected declarations moved to procedure start (CLAUDE.md rule #5)
      ; #ljPOP case variables
      Protected         spParamValue.s, spDotPos.i, spBaseName.s, spStructType.s, spIsStructParam.b
      Protected         spTypePart.s, spFoundPreCreated.i, spSearchSuffix.s, spVarIdx.i, spVarName.s
      Protected         spStructSearchName.s, spSearchFullName.s, paramAsmKey.s
      Protected         localParamOffset.i, localStructSize.i, localStructByteSize.i
      Protected         globalStructSize.i, globalStructByteSize.i
      ; #ljIDENT case variables
      Protected         identHasDot.b, identHasBackslash.b, identIsCollection.b
      Protected         identLocalOffset.i, identIsLocal.b, dotFieldType.w
      Protected         dfDotPos.i, dfStructName.s, dfFieldChain.s, dfBaseSlot.i, dfBaseStructType.s
      Protected         dfMangledBase.s, dfSearchIdx.i, dfCurrentType.s, dfRemaining.s
      Protected         dfNextDot.i, dfCurrentField.s
      Protected         sfLookupType.s, sfLookupOffset.i, sfLookupFound.b
      Protected         sfAccumOffset.i, sfFieldSize.i, sfNestedType.s
      Protected         sfIsParam.b, localFieldType.w
      ; #ljARRAY_OF_STRUCT_FETCH case variables
      Protected         aosArraySlot.i, aosIsLocal.i, aosElementSize.i, aosFieldOffset.i
      Protected         aosIndexSlot.i, aosOpcode.i
      ; #ljMD_FETCH case variables
      Protected         mdSlot.i, mdNDims.i, mdIsLocal.i, mdArrayIndex.i
      Protected         *mdIdx0.stTree, *mdIdx1.stTree, *mdIdx2.stTree, *mdIdx3.stTree
      Protected         mdAllConstant.b, mdConstIdx0.i, mdConstIdx1.i, mdConstIdx2.i, mdConstIdx3.i
      Protected         mdLinearIndex.i, mdConstSlot.i, mdFetchOpcode.i, mdHasValue.b, mdFetchOpcodeStack.i
      ; #ljARRAY_FETCH case variables
      Protected         arrayFetchIndexSlot.i, isLocal.i, arrayIndex.i, arrayFetchOpcode.i
      ; #ljSTRUCT_ARRAY_REF case variables
      Protected         sarParts.s, sarStructSlot.i, sarFieldOffset.i, sarIsLocal.i, sarByteOffset.i, sarIndexSlot.i
      ; #ljSTRUCT_ARRAY_STORE_DIRECT case variables
      Protected         sasDirectParts.s, sasDirectStructSlot.i, sasDirectFieldOffset.i, sasDirectIsLocal.i
      Protected         sasDirectByteOffset.i, sasDirectValueSlot.i, sasDirectIndexSlot.i
      ; #ljPTR_STRUCT_FIELD case variables
      Protected         psfParts.s, psfField1.s, psfField2.s, psfPtrSlot.i, psfFieldOffset.i
      Protected         psfActualNodeType.i, psfIsStructVar.i, psfIsLocalPtr.i, psfMetaSlot.i
      Protected         psfStructType.s, psfFieldType.i, psfResByteOffset.i
      Protected         psfIdentName.s, psfFieldName.s, psfVarIdx.i, psfMangledName.s, psfFuncName.s
      Protected         psfByteOffset.i, psfIsParam.b, psfStructByteSize.i
      ; #ljPTR_STRUCT_FIELD store case variables
      Protected         pssaParts.s, pssaField1.s, pssaField2.s, pssaPtrSlot.i, pssaFieldOffset.i
      Protected         pssaValueSlot.i, pssaStoreOp.i, pssaIsStructVar.i, pssaIsLocalPtr.i, pssaMetaSlot.i
      Protected         pssaStructType.s, pssaFieldType.i, pssaIdentName.s, pssaFieldName.s, pssaVarIdx.i
      Protected         pssaMangledName.s, pssaFuncName.s, pssaByteOffset.i, pssaIsParam.b, pssaStructByteSize.i
      ; Pointer definition case variables
      Protected         ptrDefVarName.s, ptrDefIsNew.i, ptrDefSlot.i, ptrDefMangledName.s, ptrDefSrcSlot.i
      ; Array store case variables
      Protected         arrayStoreValueSlot.i, arrayStoreIndexSlot.i, isLocalStore.i, arrayIndexStore.i, arrayStoreOpcode.i
      ; #ljMD_STORE case variables
      Protected         mdStoreSlot.i, mdStoreNDims.i, mdStoreIsLocal.i, mdStoreArrayIndex.i, mdStoreValueSlot.i
      Protected         *mdStoreIdx0.stTree, *mdStoreIdx1.stTree, *mdStoreIdx2.stTree, *mdStoreIdx3.stTree
      Protected         mdStoreAllConst.b, mdStoreConstIdx0.i, mdStoreConstIdx1.i, mdStoreConstIdx2.i, mdStoreConstIdx3.i
      Protected         mdStoreLinearIdx.i, mdStoreConstSlot.i, mdStoreOpcode.i, mdStoreHasVal.b, mdStoreOpcodeStack.i
      ; #ljSTRUCT_ARRAY_STORE case variables
      Protected         sasPartsStore.s, sasStructSlotStore.i, sasFieldOffsetStore.i, sasIsLocalStore.i
      Protected         sasBaseSlotStore.i, sasValueSlotStore.i, sasIndexSlotStore.i, structStoreOp.i
      ; #ljARRAY_OF_STRUCT_STORE case variables
      Protected         aosStoreArraySlot.i, aosStoreIsLocal.i, aosStoreElementSize.i, aosStoreFieldOffset.i
      Protected         aosStoreIndexSlot.i, aosStoreOpcode.i
      ; Struct copy case variables
      Protected         scStructCopyDone.i, scSrcSlot.i, scStructType.s, scSlotCount.i
      Protected         scDestIsLocal.b, scDestIsParam.b, scByteSize.i, scSrcIsLocal.b, scSrcIsParam.b
      Protected         *ptrFetchNode.stTree, isStructFieldAssignment.i, hasExplicitType.i
      ; Struct field assignment init variables
      Protected         initStructByteSize.i, sfaFieldType.w, sfaBaseSlot.i, sfaFlatOffset.i, sfaCurrentType.s
      Protected         sfaFound.b, sfaNextType.s, sfaFieldStart.i, sfaFieldEnd.i, sfaTotalSize.i, sfaMaxIter.i
      ; #ljIF case variables
      Protected         *ifNode.stTree
      Protected Dim     ifJmpHoles.i(#MAX_ELSEIF_BRANCHES)
      Protected         ifJmpCount.i
      ; #ljSEQ case variables
      Protected         *seqWalk.stTree, seqDepth.i, savedInFuncArgs.b, *stmtNode.stTree
      ; #ljFUNCTION case variables
      Protected         ljfDebugId.i, ljfStructParamPrefix.s, ljfVarIdx.i
      ; Array get/resize case variables
      Protected         isLocalArray.i, localArrayOffset.i, arrayOpcode.i, arrayType.i
      Protected         gaStructType.s, gaSlotCount.i, gaFieldPrefix.s, gaSearchIdx.i, gaSlotName.s
      Protected         isLocalVar.i, localOffset.i, opcode.i, varFlags.w
      ; #ljCALL case variables
      Protected         isListFunc.i, isMapFunc.i, isBuiltinFunc.i, nLocals.l, nLocalArrays.l
      Protected         arrIdx.l, arrVarSlot.l, sourceType.w
      ; #ljRESIZE case variables
      Protected         resizeArrayName.s, resizeNewSize.i, resizeIsLocal.i, resizeVarSlot.i, resizeSlotToEmit.i
      ; #ljLIST_NEW case variables
      Protected         listNewName.s, listNewTypeHint.i, listNewVarSlot.i, listNewIsLocal.i, listNewSlotToEmit.i
      Protected         listNewType.i, listNewElementSize.i
      ; #ljMAP_NEW case variables
      Protected         mapNewName.s, mapNewTypeHint.i, mapNewVarSlot.i, mapNewIsLocal.i, mapNewSlotToEmit.i
      Protected         mapNewType.i, mapNewElementSize.i

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
               ; V1.039.30: Use DROP instead of POP 0 - avoids unnecessary write to discard slot
               EmitInt( #ljDROP )
            Else
               ; V1.029.11: Check if parameter has struct type suffix (e.g., "r.Rectangle")
               ; Structure parameters have format "paramName.StructType"
               spParamValue = *x\value
               spDotPos = FindString(spParamValue, ".")
               spBaseName = spParamValue
               spStructType = ""
               spIsStructParam = #False

               If spDotPos > 0 And spDotPos < Len(spParamValue)
                  spTypePart = Mid(spParamValue, spDotPos + 1)
                  ; Check if the suffix is a known struct type (not .i, .f, .s primitive types)
                  If LCase(spTypePart) <> "i" And LCase(spTypePart) <> "f" And LCase(spTypePart) <> "s" And LCase(spTypePart) <> "d"
                     If FindMapElement(mapStructDefs(), spTypePart)
                        spIsStructParam = #True
                        spBaseName = Left(spParamValue, spDotPos - 1)
                        spStructType = spTypePart
                     EndIf
                  EndIf
               EndIf

               ; For struct params, use base name; otherwise use full value
               ; V1.029.70: Variables pre-declared at procedure scope per CLAUDE.md rule #5

               If spIsStructParam
                  ; V1.029.95: Search for pre-created struct params with EXACT mangled name
                  ; (gCodeGenParamIndex >= 0 means we're in parameter processing phase)
                  ; gCurrentFunctionName IS set because #ljFunction runs BEFORE params (SEQ processes LEFT first).
                  ; V1.029.94 bug: suffix search matched params from OTHER functions with same param name.
                  ; Fix: search for exact mangled name "functionName_paramName" instead of suffix.
                  ; Note: Struct params pre-created during AST may have non-mangled names (gCurrentFunctionName=""
                  ; during AST), but FetchVarOffset will find them via global search (paramOffset=-1).
                  If gCodeGenParamIndex >= 0 And gCurrentFunctionName <> ""
                     spFoundPreCreated = -1
                     spStructSearchName = LCase(gCurrentFunctionName + "_" + spBaseName)
                     ; Debug "V1.030.47: POP struct search: searchName='" + spStructSearchName + "' structType='" + spStructType + "'"
                     For spVarIdx = 0 To gnLastVariable - 1
                        ; Check if this is a PARAM with EXACT matching mangled name and struct type
                        If gVarMeta(spVarIdx)\flags & #C2FLAG_PARAM
                           If LCase(gVarMeta(spVarIdx)\structType) = LCase(spStructType)
                              If LCase(gVarMeta(spVarIdx)\name) = spStructSearchName
                                 ; Debug "V1.030.47: POP struct FOUND at slot " + Str(spVarIdx)
                                 spFoundPreCreated = spVarIdx
                                 Break
                              EndIf
                           EndIf
                        EndIf
                     Next

                     If spFoundPreCreated >= 0
                        n = spFoundPreCreated
                     Else
                        ; Debug "V1.030.47: POP struct NOT FOUND, calling FetchVarOffset('" + spBaseName + "')"
                        n = FetchVarOffset(spBaseName)
                     EndIf
                  Else
                     ; Not in function param processing - just fetch by base name
                     n = FetchVarOffset(spBaseName)
                  EndIf
               Else
                  ; V1.029.95: Non-struct params - search for pre-created param with EXACT mangled name
                  ; (gCodeGenParamIndex >= 0 means we're in parameter processing phase)
                  ; gCurrentFunctionName IS set because #ljFunction runs BEFORE params (SEQ processes LEFT first).
                  ; V1.029.94 bug: suffix search matched params from OTHER functions (e.g., moveRect_idx
                  ; was found when processing scaleRect's idx param, corrupting paramOffset).
                  ; Fix: search for exact mangled name "functionName_paramName" instead of suffix.
                  If gCodeGenParamIndex >= 0 And gCurrentFunctionName <> ""
                     spFoundPreCreated = -1
                     spSearchFullName = LCase(gCurrentFunctionName + "_" + *x\value)
                     For spVarIdx = 0 To gnLastVariable - 1
                        ; Check if this is a PARAM with EXACT matching mangled name (not just suffix)
                        If gVarMeta(spVarIdx)\flags & #C2FLAG_PARAM
                           If LCase(gVarMeta(spVarIdx)\name) = spSearchFullName
                              spFoundPreCreated = spVarIdx
                              Break
                           EndIf
                        EndIf
                     Next

                     If spFoundPreCreated >= 0
                        n = spFoundPreCreated
                     Else
                        n = FetchVarOffset(*x\value)
                     EndIf
                  Else
                     n = FetchVarOffset(*x\value)
                  EndIf
               EndIf

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
                  ; V1.030.24: BUG FIX - use mapModules()\nParams directly instead of gCodeGenLocalIndex
                  ; gCodeGenLocalIndex = nParams + nLocalArrays, but formula needs pure nParams
                  ; Old code: (gCodeGenLocalIndex - 1) - gCodeGenParamIndex = WRONG when nLocalArrays > 0
                  gVarMeta( n )\paramOffset = (mapModules()\nParams - 1) - gCodeGenParamIndex

                  ; V1.039.29: Register parameter name for ASM listing display
                  ; Key format: funcname_paramoffset (same as local variables)
                  ; Strip leading underscore from gCurrentFunctionName for key
                  paramAsmKey = LCase(Mid(gCurrentFunctionName, 2)) + "_" + Str(gVarMeta(n)\paramOffset)
                  If Not FindMapElement(gAsmLocalNameMap(), paramAsmKey)
                     gAsmLocalNameMap(paramAsmKey) = gVarMeta(n)\name
                  EndIf

                  ; V1.029.38: Struct parameter - just 1 slot with \ptr pointer (pass-by-reference)
                  ; The caller pushes gVar(baseSlot)\ptr, CALL stores it in local frame
                  ; Callee accesses fields via STRUCT_FETCH_*/STRUCT_STORE_* using the \ptr
                  If spIsStructParam
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_STRUCT
                     gVarMeta( n )\structType = spStructType
                     ; V1.029.38: No need to reserve field slots - data accessed via \ptr
                  ElseIf *x\typeHint = #ljFLOAT
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_FLOAT
                  ElseIf *x\typeHint = #ljSTRING
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_STR
                  Else
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_INT
                  EndIf

                  ; Decrement parameter index (parameters processed in reverse, last to first)
                  ; V1.029.82: All params (including structs) decrement by 1 with \ptr storage
                  gCodeGenParamIndex - 1

                  ; Note: We DON'T emit POP - parameters stay on stack
               ElseIf gCurrentFunctionName <> ""
                  ; V1.029.68: Skip if this is a struct PARAM that was already handled in #ljFunction
                  ; Struct params have PARAM flag set and paramOffset >= 0 from my #ljFunction fix.
                  ; We must NOT treat them as local variables (which would allocate new memory).
                  ; NOTE: This branch only runs when gCodeGenParamIndex < 0, which shouldn't happen
                  ; for properly handled params. This is a safety check for edge cases.
                  If (gVarMeta(n)\flags & #C2FLAG_PARAM) And (gVarMeta(n)\flags & #C2FLAG_STRUCT) And gVarMeta(n)\paramOffset >= 0
                     ; Already handled - do nothing (don't allocate new struct memory)
                     CompilerIf #DEBUG
                        ; Debug "V1.029.68: Skipping struct param - already has paramOffset=" + Str(gVarMeta(n)\paramOffset)
                     CompilerEndIf
                  Else
                  ; Local variable inside a function - assign offset and emit LSTORE
                  ; V1.029.23: Use LSTORE opcodes for locals (writes to local frame, not global)
                  ; V1.029.25: Handle local struct variables - allocate all field slots
                  gVarMeta( n )\paramOffset = gCodeGenLocalIndex
                  localParamOffset = gCodeGenLocalIndex  ; Save before increment

                  ; Check if this is a local struct variable
                  If spIsStructParam And spStructType <> ""
                     ; V1.029.36: Local struct with \ptr storage - allocate only 1 slot
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_STRUCT
                     gVarMeta( n )\structType = spStructType

                     localStructSize = 1
                     localStructByteSize = 8  ; Default 8 bytes
                     If FindMapElement(mapStructDefs(), spStructType)
                        localStructSize = mapStructDefs()\totalSize
                        localStructByteSize = localStructSize * 8  ; 8 bytes per field
                     EndIf

                     ; V1.029.36: Only 1 slot needed - data stored in \ptr
                     gCodeGenLocalIndex + 1  ; Base slot only

                     ; V1.029.36: Emit STRUCT_ALLOC_LOCAL to allocate memory for local struct
                     EmitInt(#ljSTRUCT_ALLOC_LOCAL, localParamOffset)
                     llObjects()\j = localStructByteSize   ; Byte size

                     ; Store byte size in metadata for later use
                     gVarMeta( n )\arraySize = localStructByteSize  ; Reuse arraySize for struct byte size
                  Else
                     ; Simple local variable
                     gCodeGenLocalIndex + 1  ; Increment for next local

                     ; V1.034.16: Directly emit STORE with j=1 (bypass EmitInt local detection)
                     ; We know this is a local, and we have the paramOffset directly
                     AddElement(llObjects())
                     If *x\typeHint = #ljFLOAT
                        llObjects()\code = #ljSTOREF
                        gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
                     ElseIf *x\typeHint = #ljSTRING
                        llObjects()\code = #ljSTORES
                        gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_STR
                     Else
                        llObjects()\code = #ljStore
                        gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_INT
                     EndIf
                     llObjects()\j = 1   ; Mark as local
                     llObjects()\i = localParamOffset
                  EndIf

                  ; Update nLocals in mapModules immediately
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                        Break
                     EndIf
                  Next
                  EndIf  ; V1.029.68: Close local variable Else branch
               Else
                  ; Global variable
                  ; V1.029.36: Check for global struct variable
                  If spIsStructParam And spStructType <> ""
                     ; Global struct with \ptr storage - allocate only 1 slot
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_STRUCT
                     gVarMeta( n )\structType = spStructType

                     globalStructSize = 1
                     globalStructByteSize = 8
                     If FindMapElement(mapStructDefs(), spStructType)
                        globalStructSize = mapStructDefs()\totalSize
                        globalStructByteSize = globalStructSize * 8
                     EndIf

                     ; Emit STRUCT_ALLOC for global struct
                     EmitInt(#ljSTRUCT_ALLOC, n)
                     llObjects()\j = globalStructByteSize

                     ; V1.029.66: Store field count in elementSize for vmTransferMetaToRuntime
                     ; vmTransferMetaToRuntime uses: structByteSize = elementSize * 8
                     gVarMeta( n )\elementSize = globalStructSize
                  ElseIf *x\typeHint = #ljFLOAT
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
            ; V1.029.5: Check if this is a struct - need to push all slots for function parameters
            ; V1.029.12: Skip struct push for DOT notation field access (e.g., "rect1.topLeft.x")
            ; DOT in identifier means field access, not whole-struct reference
            ; V1.029.30: Skip struct push for collections - they store struct TYPE but are pool slots
            ; V1.029.44: Skip struct push for backslash field access (e.g., "p1\x")
            identHasDot = Bool(FindString(*x\value, ".") > 0)
            identHasBackslash = Bool(FindString(*x\value, "\") > 0)
            identIsCollection = Bool(gVarMeta(n)\flags & (#C2FLAG_LIST | #C2FLAG_MAP))
            If gVarMeta(n)\structType <> "" And (gVarMeta(n)\flags & #C2FLAG_STRUCT) And Not identHasDot And Not identHasBackslash And Not identIsCollection
               ; V1.029.38: With \ptr storage, use FETCH_STRUCT/LFETCH_STRUCT to push both \i and \ptr
               ; The base slot contains gVar(n)\ptr which points to all struct data
               ; Callee accesses fields via STRUCT_FETCH_*/STRUCT_STORE_* using the \ptr
               ; FETCH_STRUCT copies both \i and \ptr so CALL reversal works correctly
               ; V1.034.24: Use unified FETCH_STRUCT with j=1 for locals
               AddElement(llObjects())
               llObjects()\code = #ljFETCH_STRUCT
               If gVarMeta(n)\paramOffset >= 0
                  ; Local struct (variable or parameter) - set j=1 and use paramOffset
                  llObjects()\i = gVarMeta(n)\paramOffset
                  llObjects()\j = 1
               Else
                  ; Global struct - j=0 (default)
                  llObjects()\i = n
               EndIf
               ; No extra struct slots - just 1 slot for the pointer
               ; (gExtraStructSlots stays 0)
            Else
               ; Original non-struct code
               ; Emit appropriate FETCH variant based on variable type
               ; V1.029.10: Check if variable is local (struct field of local param)
               identLocalOffset = gVarMeta(n)\paramOffset
               identIsLocal = IsLocalVar(n)

               ; V1.029.12: For DOT notation, determine field type from struct definition
               ; This is needed because offset-0 fields share slot with struct base
               ; V1.029.19: Fixed to find BASE struct slot (n is field slot, not base slot)
               dotFieldType = 0
               If identHasDot
                  ; Look up field type from struct definition by walking the chain
                  dfDotPos = FindString(*x\value, ".")
                  dfStructName = Left(*x\value, dfDotPos - 1)
                  dfFieldChain = Mid(*x\value, dfDotPos + 1)

                  ; V1.029.19: Find the BASE struct slot to get structType
                  ; n is the field slot, but we need the base struct's type
                  dfBaseSlot = -1
                  dfBaseStructType = ""
                  dfMangledBase = ""

                  ; Search for base struct (mangled local first, then global)
                  If gCurrentFunctionName <> ""
                     dfMangledBase = gCurrentFunctionName + "_" + dfStructName
                     For dfSearchIdx = 0 To gnLastVariable - 1
                        If LCase(Trim(gVarMeta(dfSearchIdx)\name)) = LCase(dfMangledBase) And gVarMeta(dfSearchIdx)\structType <> ""
                           dfBaseSlot = dfSearchIdx
                           dfBaseStructType = gVarMeta(dfSearchIdx)\structType
                           Break
                        EndIf
                     Next
                  EndIf
                  ; V1.029.24: Search for struct parameter (non-mangled name, paramOffset >= 0)
                  If dfBaseSlot < 0 And gCurrentFunctionName <> ""
                     For dfSearchIdx = 0 To gnLastVariable - 1
                        If LCase(Trim(gVarMeta(dfSearchIdx)\name)) = LCase(dfStructName) And gVarMeta(dfSearchIdx)\structType <> "" And gVarMeta(dfSearchIdx)\paramOffset >= 0
                           dfBaseSlot = dfSearchIdx
                           dfBaseStructType = gVarMeta(dfSearchIdx)\structType
                           Break
                        EndIf
                     Next
                  EndIf
                  ; Fall back to global search
                  If dfBaseSlot < 0
                     For dfSearchIdx = 0 To gnLastVariable - 1
                        If LCase(Trim(gVarMeta(dfSearchIdx)\name)) = LCase(dfStructName) And gVarMeta(dfSearchIdx)\structType <> "" And gVarMeta(dfSearchIdx)\paramOffset = -1
                           dfBaseSlot = dfSearchIdx
                           dfBaseStructType = gVarMeta(dfSearchIdx)\structType
                           Break
                        EndIf
                     Next
                  EndIf

                  dfCurrentType = dfBaseStructType
                  dfRemaining = dfFieldChain

                  While dfRemaining <> "" And dfCurrentType <> ""
                     dfNextDot = FindString(dfRemaining, ".")
                     dfCurrentField = ""
                     If dfNextDot > 0
                        dfCurrentField = Left(dfRemaining, dfNextDot - 1)
                        dfRemaining = Mid(dfRemaining, dfNextDot + 1)
                     Else
                        dfCurrentField = dfRemaining
                        dfRemaining = ""
                     EndIf

                     If FindMapElement(mapStructDefs(), dfCurrentType)
                        ForEach mapStructDefs()\fields()
                           If LCase(mapStructDefs()\fields()\name) = LCase(dfCurrentField)
                              If dfRemaining = ""
                                 ; Final field - get its type
                                 dotFieldType = mapStructDefs()\fields()\fieldType
                              EndIf
                              dfCurrentType = mapStructDefs()\fields()\structType
                              Break
                           EndIf
                        Next
                     Else
                        dfCurrentType = ""
                     EndIf
                  Wend
               EndIf

               ; V1.026.6: Maps and lists always store pool slot index (integer), not the value
               If gVarMeta(n)\flags & (#C2FLAG_MAP | #C2FLAG_LIST)
                  EmitInt( #ljFetch, n )  ; Always fetch as integer for collections

               ; V1.029.37: Check if this is a struct field access with \ptr storage
               ElseIf gVarMeta(n)\structFieldBase >= 0
                  ; Struct field access - use STRUCT_FETCH_* with base slot and byte offset
                  sfBaseSlot = gVarMeta(n)\structFieldBase
                  sfByteOffset = gVarMeta(n)\structFieldOffset
                  ; V1.030.61: Debug - trace what offset is being used for struct fetch
                  ; Debug "V1.030.61: STRUCT_FETCH n=" + Str(n) + " name='" + gVarMeta(n)\name + "' sfBaseSlot=" + Str(sfBaseSlot) + " sfByteOffset=" + Str(sfByteOffset) + " value='" + *x\value + "'"
                  sfIsLocal = Bool(gVarMeta(sfBaseSlot)\paramOffset >= 0)
                  sfFieldType = dotFieldType
                  ; V1.029.64: Look up field type from struct definition using byte offset
                  ; Must handle nested structs by walking the type chain
                  If sfFieldType = 0 And gVarMeta(sfBaseSlot)\structType <> ""
                     sfLookupType = gVarMeta(sfBaseSlot)\structType
                     sfLookupOffset = sfByteOffset / 8  ; Convert byte offset to field index
                     sfLookupFound = #False

                     ; Walk nested struct chain until we find a primitive field
                     While Not sfLookupFound And sfLookupType <> ""
                        If FindMapElement(mapStructDefs(), sfLookupType)
                           sfAccumOffset = 0
                           ForEach mapStructDefs()\fields()
                              sfFieldSize = 1  ; Default size for primitives
                              ; V1.029.72: Check for array fields - use arraySize for field size
                              If mapStructDefs()\fields()\isArray And mapStructDefs()\fields()\arraySize > 1
                                 sfFieldSize = mapStructDefs()\fields()\arraySize
                              ElseIf mapStructDefs()\fields()\structType <> ""
                                 ; Nested struct - get its total size
                                 sfNestedType = mapStructDefs()\fields()\structType
                                 If FindMapElement(mapStructDefs(), sfNestedType)
                                    sfFieldSize = mapStructDefs()\totalSize
                                 EndIf
                                 FindMapElement(mapStructDefs(), sfLookupType)  ; Restore position
                              EndIf

                              ; Check if target offset falls within this field
                              If sfLookupOffset >= sfAccumOffset And sfLookupOffset < sfAccumOffset + sfFieldSize
                                 If mapStructDefs()\fields()\structType <> ""
                                    ; Nested struct - recurse into it
                                    sfLookupType = mapStructDefs()\fields()\structType
                                    sfLookupOffset = sfLookupOffset - sfAccumOffset
                                    Break  ; Continue outer while loop with nested type
                                 Else
                                    ; Primitive field found
                                    sfFieldType = mapStructDefs()\fields()\fieldType
                                    sfLookupFound = #True
                                    Break
                                 EndIf
                              EndIf
                              sfAccumOffset + sfFieldSize
                           Next
                           If ListIndex(mapStructDefs()\fields()) = -1
                              Break  ; Field not found, exit
                           EndIf
                        Else
                           Break  ; Struct type not found
                        EndIf
                     Wend
                  EndIf
                  If sfFieldType = 0
                     sfFieldType = #C2FLAG_INT  ; Default to int if still unknown
                  EndIf

                  ; V1.029.40: Lazy STRUCT_ALLOC_LOCAL - emit on first field access for LOCAL structs
                  ; Global structs are pre-allocated by VM in vmTransferMetaToRuntime()
                  ; V1.029.65: Skip for struct PARAMETERS - they receive pointer from caller via FETCH_STRUCT
                  sfIsParam = Bool(gVarMeta(sfBaseSlot)\flags & #C2FLAG_PARAM)
                  ;Debug "FETCH ALLOC CHECK: slot=" + Str(sfBaseSlot) + " name='" + gVarMeta(sfBaseSlot)\name + "' isLocal=" + Str(sfIsLocal) + " isParam=" + Str(sfIsParam) + " emitted=" + Str(gVarMeta(sfBaseSlot)\structAllocEmitted) + " paramOffset=" + Str(gVarMeta(sfBaseSlot)\paramOffset)
                  If sfIsLocal And Not sfIsParam And Not gVarMeta(sfBaseSlot)\structAllocEmitted
                     ; Calculate byte size from struct definition
                     sfStructByteSize = 8  ; Default 8 bytes (1 field)
                     If gVarMeta(sfBaseSlot)\structType <> "" And FindMapElement(mapStructDefs(), gVarMeta(sfBaseSlot)\structType)
                        sfStructByteSize = mapStructDefs()\totalSize * 8  ; 8 bytes per field
                     EndIf

                     ; Emit STRUCT_ALLOC_LOCAL before the fetch
                     gEmitIntLastOp = AddElement( llObjects() )
                     llObjects()\code = #ljSTRUCT_ALLOC_LOCAL
                     llObjects()\i = gVarMeta(sfBaseSlot)\paramOffset
                     llObjects()\j = sfStructByteSize

                     ; Mark as allocated
                     gVarMeta(sfBaseSlot)\structAllocEmitted = #True
                  EndIf

                  If sfIsLocal
                     ; Local struct - use LOCAL variant with paramOffset
                     If sfFieldType & #C2FLAG_FLOAT
                        EmitInt(#ljSTRUCT_FETCH_FLOAT_LOCAL, gVarMeta(sfBaseSlot)\paramOffset)
                     ElseIf sfFieldType & #C2FLAG_STR
                        ; V1.029.55: String field support
                        EmitInt(#ljSTRUCT_FETCH_STR_LOCAL, gVarMeta(sfBaseSlot)\paramOffset)
                     Else
                        EmitInt(#ljSTRUCT_FETCH_INT_LOCAL, gVarMeta(sfBaseSlot)\paramOffset)
                     EndIf
                  Else
                     ; Global struct - use direct slot
                     If sfFieldType & #C2FLAG_FLOAT
                        EmitInt(#ljSTRUCT_FETCH_FLOAT, sfBaseSlot)
                     ElseIf sfFieldType & #C2FLAG_STR
                        ; V1.029.55: String field support
                        EmitInt(#ljSTRUCT_FETCH_STR, sfBaseSlot)
                     Else
                        EmitInt(#ljSTRUCT_FETCH_INT, sfBaseSlot)
                     EndIf
                  EndIf
                  llObjects()\j = sfByteOffset  ; Byte offset within struct
                  ; V1.030.61: Debug - confirm byte offset written to instruction
                  ; Debug "V1.030.61: STRUCT_FETCH EMITTED: opcode=" + Str(llObjects()\code) + " i=" + Str(llObjects()\i) + " j=" + Str(llObjects()\j) + " (byte offset)"

               ElseIf identIsLocal And identLocalOffset >= 0
                  ; V1.029.10: Local variable - use LFETCH with paramOffset
                  ; V1.029.16: For DOT notation fields, use dotFieldType to determine correct type
                  ; V1.029.24: Fixed - call EmitInt with FETCH opcodes and slot n, not LFETCH with paramOffset
                  ; EmitInt handles conversion FETCH->LFETCH and sets correct paramOffset
                  localFieldType = dotFieldType
                  If localFieldType = 0
                     localFieldType = gVarMeta(n)\flags
                  EndIf
                  If localFieldType & #C2FLAG_STR
                     EmitInt( #ljFETCHS, n )
                  ElseIf localFieldType & #C2FLAG_FLOAT
                     EmitInt( #ljFETCHF, n )
                  Else
                     EmitInt( #ljFetch, n )
                  EndIf
               ElseIf dotFieldType & #C2FLAG_STR
                  ; V1.029.12: Use DOT field type for correct FETCH variant
                  EmitInt( #ljFETCHS, n )
               ElseIf dotFieldType & #C2FLAG_FLOAT
                  EmitInt( #ljFETCHF, n )
               ElseIf dotFieldType <> 0
                  EmitInt( #ljFetch, n )  ; Integer DOT field
               ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                  EmitInt( #ljFETCHS, n )
               ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                  EmitInt( #ljFETCHF, n )
               Else
                  EmitInt( #ljFetch, n )
               EndIf
            EndIf
            gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT

         ; V1.026.0: Push slot index for collection function first parameter
         Case #ljPUSH_SLOT
            ; Left child contains the IDENT node - look up its slot
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               EmitInt( #ljPUSH_SLOT, n )
            EndIf

         ; V1.20.21: Pointer field access (ptr\i, ptr\f, ptr\s)
         ; V1.20.22: Can be either simple variable (leaf) or array element (node with left child)
         ; V1.034.66: Mark variables as pointers for arithmetic detection
         Case #ljPTRFIELD_I
            If *x\left
               ; Array element pointer field: arr[i]\i
               CodeGenerator( *x\left )  ; Generate array access (leaves pointer on stack)
            Else
               ; Simple variable pointer field: ptr\i
               n = FetchVarOffset(*x\value)
               EmitInt( #ljFetch, n )    ; Fetch pointer variable
               ; V1.034.66: Mark this variable as a pointer for arithmetic detection
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT | #C2FLAG_POINTER
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
               ; V1.034.66: Mark this variable as a pointer for arithmetic detection
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT | #C2FLAG_POINTER
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
               ; V1.034.66: Mark this variable as a pointer for arithmetic detection
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT | #C2FLAG_POINTER
            EndIf
            EmitInt( #ljPTRFETCH_STR )   ; Dereference as string

         ; V1.022.45: Struct array field access (arr[i]\field)
         ; *x\left = array access node (#ljLeftBracket)
         ; *x\value = "elementSize|fieldOffset" (encoded as pipe-delimited string)
         Case #nd_StructArrayField_I, #nd_StructArrayField_F, #nd_StructArrayField_S
            If *x\left And *x\left\NodeType = #ljLeftBracket And *x\left\left
               ; Get array base slot
               aosArraySlot = FetchVarOffset(*x\left\left\value)
               aosIsLocal = 0
               If gVarMeta(aosArraySlot)\paramOffset >= 0
                  aosIsLocal = 1
               EndIf

               ; V1.022.45: Parse elementSize|fieldOffset from value field
               aosElementSize = Val(StringField(*x\value, 1, "|"))
               aosFieldOffset = Val(StringField(*x\value, 2, "|"))

               ; Get index expression slot
               aosIndexSlot = GetExprSlotOrTemp(*x\left\right)

               ; Select opcode based on field type
               aosOpcode = 0
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

         ; V1.036.0: Multi-dimensional array access (arr[i][j][k])
         ; *x\left = array variable (ljIDENT) with additional indices stored in its children
         ; *x\right = first index expression (*mdIndices[0])
         ; *x\value = "varSlot|nDims"
         ; *x\paramCount = number of dimensions
         ; Additional indices stored in: left\right = idx[1], left\left = idx[2], right\left = idx[3]
         Case #nd_MultiDimIndex
            mdSlot = Val(StringField(*x\value, 1, "|"))
            mdNDims = Val(StringField(*x\value, 2, "|"))
            mdIsLocal = 0
            mdArrayIndex = mdSlot

            ; Check if array is local
            If gVarMeta(mdSlot)\paramOffset >= 0
               mdIsLocal = 1
               mdArrayIndex = gVarMeta(mdSlot)\paramOffset
            EndIf

            ; Retrieve index expressions from node structure
            *mdIdx0 = *x\right           ; First index
            *mdIdx1 = 0
            *mdIdx2 = 0
            *mdIdx3 = 0

            If mdNDims >= 2 And *x\left
               *mdIdx1 = *x\left\right
            EndIf
            If mdNDims >= 3 And *x\left
               *mdIdx2 = *x\left\left
            EndIf
            If mdNDims >= 4 And *x\right
               *mdIdx3 = *x\right\left
            EndIf

            ; Check if all indices are compile-time constants
            mdAllConstant = #True
            mdConstIdx0 = 0 : mdConstIdx1 = 0 : mdConstIdx2 = 0 : mdConstIdx3 = 0
            mdLinearIndex = 0

            ; Check and collect constant index values
            If *mdIdx0 And *mdIdx0\NodeType = #ljINT
               mdConstIdx0 = Val(*mdIdx0\value)
            Else
               mdAllConstant = #False
            EndIf

            If mdNDims >= 2
               If *mdIdx1 And *mdIdx1\NodeType = #ljINT
                  mdConstIdx1 = Val(*mdIdx1\value)
               Else
                  mdAllConstant = #False
               EndIf
            EndIf

            If mdNDims >= 3
               If *mdIdx2 And *mdIdx2\NodeType = #ljINT
                  mdConstIdx2 = Val(*mdIdx2\value)
               Else
                  mdAllConstant = #False
               EndIf
            EndIf

            If mdNDims >= 4
               If *mdIdx3 And *mdIdx3\NodeType = #ljINT
                  mdConstIdx3 = Val(*mdIdx3\value)
               Else
                  mdAllConstant = #False
               EndIf
            EndIf

            If mdAllConstant
               ; All indices are constants - compute linear index at compile time
               mdLinearIndex = mdConstIdx0 * gVarMeta(mdSlot)\dimStrides[0]
               If mdNDims >= 2
                  mdLinearIndex + mdConstIdx1 * gVarMeta(mdSlot)\dimStrides[1]
               EndIf
               If mdNDims >= 3
                  mdLinearIndex + mdConstIdx2 * gVarMeta(mdSlot)\dimStrides[2]
               EndIf
               If mdNDims >= 4
                  mdLinearIndex + mdConstIdx3 * gVarMeta(mdSlot)\dimStrides[3]
               EndIf

               ; Create temp slot for constant linear index
               ; V1.037.2: FIX - Use #ljINT synthetic type to create proper constant slot
               ; FetchVarOffset with #ljINT sets CONST flag and valueInt, enabling runtime transfer
               mdConstSlot = FetchVarOffset(Str(mdLinearIndex), 0, #ljINT)

               ; Determine array type and emit fetch
               mdFetchOpcode = 0
               If gVarMeta(mdSlot)\flags & #C2FLAG_STR
                  mdFetchOpcode = #ljARRAYFETCH_STR
               ElseIf gVarMeta(mdSlot)\flags & #C2FLAG_FLOAT
                  mdFetchOpcode = #ljARRAYFETCH_FLOAT
               Else
                  mdFetchOpcode = #ljARRAYFETCH_INT
               EndIf

               EmitInt(mdFetchOpcode, mdArrayIndex)
               llObjects()\j = mdIsLocal
               llObjects()\ndx = mdConstSlot

               CompilerIf #DEBUG
                  Debug "MultiDim FETCH const: slot=" + Str(mdSlot) + " linearIdx=" + Str(mdLinearIndex)
               CompilerEndIf

            Else
               ; Variable indices - generate runtime computation
               ; Compute: idx0 * stride0 + idx1 * stride1 + ...

               ; Generate code for first index * stride
               mdHasValue = #False
               If gVarMeta(mdSlot)\dimStrides[0] = 1
                  ; Stride is 1, just use index directly
                  CodeGenerator(*mdIdx0)
                  mdHasValue = #True
               ElseIf gVarMeta(mdSlot)\dimStrides[0] > 1
                  CodeGenerator(*mdIdx0)
                  EmitInt(#ljPUSH_IMM, gVarMeta(mdSlot)\dimStrides[0])
                  EmitInt(#ljMULTIPLY)
                  mdHasValue = #True
               EndIf

               ; Add remaining dimensions
               If mdNDims >= 2 And *mdIdx1
                  If gVarMeta(mdSlot)\dimStrides[1] = 1
                     CodeGenerator(*mdIdx1)
                  Else
                     CodeGenerator(*mdIdx1)
                     EmitInt(#ljPUSH_IMM, gVarMeta(mdSlot)\dimStrides[1])
                     EmitInt(#ljMULTIPLY)
                  EndIf
                  If mdHasValue
                     EmitInt(#ljADD)
                  EndIf
                  mdHasValue = #True
               EndIf

               If mdNDims >= 3 And *mdIdx2
                  If gVarMeta(mdSlot)\dimStrides[2] = 1
                     CodeGenerator(*mdIdx2)
                  Else
                     CodeGenerator(*mdIdx2)
                     EmitInt(#ljPUSH_IMM, gVarMeta(mdSlot)\dimStrides[2])
                     EmitInt(#ljMULTIPLY)
                  EndIf
                  If mdHasValue
                     EmitInt(#ljADD)
                  EndIf
                  mdHasValue = #True
               EndIf

               If mdNDims >= 4 And *mdIdx3
                  If gVarMeta(mdSlot)\dimStrides[3] = 1
                     CodeGenerator(*mdIdx3)
                  Else
                     CodeGenerator(*mdIdx3)
                     EmitInt(#ljPUSH_IMM, gVarMeta(mdSlot)\dimStrides[3])
                     EmitInt(#ljMULTIPLY)
                  EndIf
                  If mdHasValue
                     EmitInt(#ljADD)
                  EndIf
               EndIf

               ; Stack now has the linear index - emit ARRAYFETCH_STACK variant
               mdFetchOpcodeStack = 0
               If gVarMeta(mdSlot)\flags & #C2FLAG_STR
                  mdFetchOpcodeStack = #ljARRAYFETCH_STR
               ElseIf gVarMeta(mdSlot)\flags & #C2FLAG_FLOAT
                  mdFetchOpcodeStack = #ljARRAYFETCH_FLOAT
               Else
                  mdFetchOpcodeStack = #ljARRAYFETCH_INT
               EndIf

               EmitInt(mdFetchOpcodeStack, mdArrayIndex)
               llObjects()\j = mdIsLocal
               llObjects()\ndx = -1  ; -1 indicates stack-based index

               CompilerIf #DEBUG
                  Debug "MultiDim FETCH stack: slot=" + Str(mdSlot) + " dims=" + Str(mdNDims)
               CompilerEndIf
            EndIf

         Case #ljINT, #ljFLOAT, #ljSTRING
            n = FetchVarOffset( *x\value, 0, *x\NodeType )
            ; V1.029.46: Use type-specific PUSH opcode to preserve float/string types
            If *x\NodeType = #ljFLOAT
               EmitInt( #ljPUSHF, n )
            ElseIf *x\NodeType = #ljSTRING
               EmitInt( #ljPUSHS, n )
            Else
               EmitInt( #ljPush, n )
            EndIf

         Case #ljLeftBracket
            ; Array indexing: arr[index]
            ; *x\left = array variable (ljIDENT)
            ; *x\right = index expression
            ; V1.022.21: Slot-only optimization - no stack ops for simple index expressions

            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; V1.022.21: Get slot for index (may emit code for complex expressions)
               arrayFetchIndexSlot = GetExprSlotOrTemp(*x\right)

               ; Determine if array is local or global at compile time
               isLocal = 0
               arrayIndex = n  ; Default to global varSlot

               If gVarMeta(n)\paramOffset >= 0
                  ; V1.18.0: Local array - use paramOffset for unified gVar[] slot calculation
                  isLocal = 1
                  arrayIndex = gVarMeta(n)\paramOffset
               EndIf

               ; V1.022.22: Emit typed ARRAYFETCH directly (skip postprocessor typing)
               ; Determine type from array metadata
               arrayFetchOpcode = 0
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
            ; V1.029.58: Updated for \ptr storage - pass structSlot and byteOffset separately
            ; *x\left = index expression
            ; *x\value = "structVarSlot|fieldOffset|fieldName"

            ; Parse value to get struct info
            sarParts = *x\value
            sarStructSlot = Val(StringField(sarParts, 1, "|"))
            sarFieldOffset = Val(StringField(sarParts, 2, "|"))
            sarIsLocal = 0
            sarByteOffset = sarFieldOffset * 8  ; V1.029.58: Byte offset for \ptr storage
            sarIndexSlot = 0

            ; Check if struct is local (has paramOffset >= 0)
            If gVarMeta(sarStructSlot)\paramOffset >= 0
               sarIsLocal = 1
            EndIf

            ; V1.022.20: Get slot for index (may emit code for complex expressions)
            sarIndexSlot = GetExprSlotOrTemp(*x\left)

            ; V1.029.58: Emit struct array fetch with \ptr storage params
            ; i = struct slot (or paramOffset for local)
            ; j = isLocal
            ; n = field byte offset (fieldOffset * 8)
            ; ndx = index slot
            If sarIsLocal
               EmitInt( *x\NodeType, gVarMeta(sarStructSlot)\paramOffset )
            Else
               EmitInt( *x\NodeType, sarStructSlot )
            EndIf
            llObjects()\j = sarIsLocal
            llObjects()\n = sarByteOffset
            llObjects()\ndx = sarIndexSlot

         Case #ljSTRUCTARRAY_STORE_INT, #ljSTRUCTARRAY_STORE_FLOAT, #ljSTRUCTARRAY_STORE_STR
            ; V1.022.4: Direct struct array field store (standalone statement)
            ; V1.022.20: Slot-only optimization - no stack ops for simple expressions
            ; V1.029.58: Updated for \ptr storage - pass structSlot and byteOffset separately
            ; *x\left = index expression
            ; *x\right = value expression
            ; *x\value = "structVarSlot|fieldOffset|fieldName"

            ; Parse value to get struct info
            sasDirectParts = *x\value
            sasDirectStructSlot = Val(StringField(sasDirectParts, 1, "|"))
            sasDirectFieldOffset = Val(StringField(sasDirectParts, 2, "|"))
            sasDirectIsLocal = 0
            sasDirectByteOffset = sasDirectFieldOffset * 8  ; V1.029.58: Byte offset for \ptr storage
            sasDirectValueSlot = 0
            sasDirectIndexSlot = 0

            ; Check if struct is local (has paramOffset >= 0)
            If gVarMeta(sasDirectStructSlot)\paramOffset >= 0
               sasDirectIsLocal = 1
            EndIf

            ; V1.022.20: Get slots for value and index (may emit code for complex expressions)
            ; Value first, then index (preserves evaluation order)
            sasDirectValueSlot = GetExprSlotOrTemp(*x\right)
            sasDirectIndexSlot = GetExprSlotOrTemp(*x\left)

            ; V1.029.58: Emit struct array store opcode with \ptr storage params
            ; i = struct slot (or paramOffset for local)
            ; j = isLocal
            ; n = field byte offset (fieldOffset * 8)
            ; ndx = index slot
            ; funcid = value slot
            If sasDirectIsLocal
               EmitInt( *x\NodeType, gVarMeta(sasDirectStructSlot)\paramOffset )
            Else
               EmitInt( *x\NodeType, sasDirectStructSlot )
            EndIf
            llObjects()\j = sasDirectIsLocal
            llObjects()\n = sasDirectByteOffset
            llObjects()\ndx = sasDirectIndexSlot
            llObjects()\funcid = sasDirectValueSlot

         Case #ljPTRSTRUCTFETCH_INT, #ljPTRSTRUCTFETCH_FLOAT, #ljPTRSTRUCTFETCH_STR
            ; V1.022.54: Struct pointer field fetch - ptr\field
            ; V1.022.55: Handle both resolved ("ptrVarSlot|fieldOffset") and deferred ("identName|fieldName") formats
            psfParts = *x\value
            psfField1 = StringField(psfParts, 1, "|")
            psfField2 = StringField(psfParts, 2, "|")
            psfPtrSlot = 0
            psfFieldOffset = 0
            psfActualNodeType = *x\NodeType
            ; V1.029.41: Declare shared variables for struct var detection
            psfIsStructVar = #False
            psfIsLocalPtr = #False
            psfMetaSlot = -1
            psfStructType = ""
            psfFieldType = 0

            ; Check if first field is numeric (resolved) or identifier (deferred)
            ; V1.023.13: Changed condition - slot "0" should use deferred path since slot 0 is reserved
            If Val(psfField1) > 0
               ; Resolved format: "ptrVarSlot|fieldOffset"
               psfPtrSlot = Val(psfField1)
               psfFieldOffset = Val(psfField2)
               psfMetaSlot = psfPtrSlot  ; For resolved format, metaSlot = ptrSlot

               ; V1.029.41: Check if this is a struct VARIABLE or struct POINTER
               If gVarMeta(psfPtrSlot)\pointsToStructType <> ""
                  psfIsStructVar = #False
                  psfStructType = gVarMeta(psfPtrSlot)\pointsToStructType
               ElseIf gVarMeta(psfPtrSlot)\structType <> ""
                  psfIsStructVar = #True
                  psfStructType = gVarMeta(psfPtrSlot)\structType
               EndIf

               ; Look up field type for proper opcode selection
               If psfStructType <> "" And FindMapElement(mapStructDefs(), psfStructType)
                  ForEach mapStructDefs()\fields()
                     If mapStructDefs()\fields()\offset = psfFieldOffset
                        psfFieldType = mapStructDefs()\fields()\fieldType
                        Break
                     EndIf
                  Next
               EndIf

               ; V1.029.41: Emit for resolved format - handle struct var vs pointer
               If psfIsStructVar
                  psfResByteOffset = psfFieldOffset * 8  ; Convert field offset to byte offset

                  ; Select correct opcode based on field type (global - resolved format is always global scope)
                  If psfFieldType & #C2FLAG_FLOAT
                     psfActualNodeType = #ljSTRUCT_FETCH_FLOAT
                  ElseIf psfFieldType & #C2FLAG_STR
                     ; V1.029.55: String field support
                     psfActualNodeType = #ljSTRUCT_FETCH_STR
                  Else
                     psfActualNodeType = #ljSTRUCT_FETCH_INT
                  EndIf

                  ; Emit STRUCT_FETCH: i = slot, j = byte offset
                  EmitInt(psfActualNodeType, psfMetaSlot)
                  llObjects()\j = psfResByteOffset
               Else
                  ; Struct POINTER or unknown - use PTRSTRUCTFETCH
                  EmitInt(psfActualNodeType, psfPtrSlot)
                  llObjects()\n = psfFieldOffset
               EndIf
            Else
               ; Deferred format: "identName|fieldName" - resolve now
               psfIdentName = psfField1
               psfFieldName = psfField2
               psfVarIdx = 0

               ; V1.022.120: Find the variable - search LOCAL (mangled) name FIRST, then global
               ; This matches FetchVarOffset behavior and ensures local variables are found
               psfPtrSlot = -1
               psfIsLocalPtr = #False    ; V1.029.41: Now declared at top
               psfMetaSlot = -1          ; V1.029.41: Now declared at top
               psfMangledName = ""
               psfFuncName = gCurrentFunctionName

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
                  CompilerIf #DEBUG
                     Debug "PTRSTRUCTFETCH deferred: searching for '" + psfIdentName + "' in slots 1 to " + Str(gnLastVariable - 1)
                  CompilerEndIf
                  For psfVarIdx = 1 To gnLastVariable - 1
                     If LCase(gVarMeta(psfVarIdx)\name) = LCase(psfIdentName)
                        psfPtrSlot = psfVarIdx
                        psfMetaSlot = psfVarIdx
                        ; psfIsLocalPtr stays FALSE for global variables
                        CompilerIf #DEBUG
                           Debug "PTRSTRUCTFETCH deferred: FOUND '" + psfIdentName + "' at slot " + Str(psfVarIdx)
                        CompilerEndIf
                        Break
                     EndIf
                  Next
               EndIf

               If psfPtrSlot < 0
                  CompilerIf #DEBUG
                     Debug "PTRSTRUCTFETCH deferred: NOT FOUND - dumping gVarMeta slots:"
                     For psfVarIdx = 1 To gnLastVariable - 1
                        If gVarMeta(psfVarIdx)\name <> ""
                           Debug "  Slot " + Str(psfVarIdx) + ": name='" + gVarMeta(psfVarIdx)\name + "' flags=" + Str(gVarMeta(psfVarIdx)\flags) + " structType='" + gVarMeta(psfVarIdx)\structType + "'"
                        EndIf
                     Next
                  CompilerEndIf
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

               ; Get struct type from pointer OR struct variable (use saved metaSlot, not encoded psfPtrSlot)
               ; V1.029.40: Check both pointsToStructType (pointer) and structType (struct var)
               ; V1.029.41: Track whether this is a pointer or struct variable (vars declared at top)
               psfStructType = gVarMeta(psfMetaSlot)\pointsToStructType
               psfIsStructVar = #False
               If psfStructType = ""
                  psfStructType = gVarMeta(psfMetaSlot)\structType
                  psfIsStructVar = #True  ; This is a struct VARIABLE, not a pointer
               EndIf
               If psfStructType = ""
                  SetError("Variable '" + psfIdentName + "' is not a struct pointer or struct variable", #C2ERR_CODEGEN_FAILED)
                  ProcedureReturn
               EndIf

               ; Look up field in struct type
               psfFieldOffset = -1
               psfFieldType = 0  ; V1.029.41: Now declared at top
               If FindMapElement(mapStructDefs(), psfStructType)
                  ForEach mapStructDefs()\fields()
                     If LCase(mapStructDefs()\fields()\name) = LCase(psfFieldName)
                        psfFieldOffset = mapStructDefs()\fields()\offset
                        psfFieldType = mapStructDefs()\fields()\fieldType
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

               ; V1.029.41: For struct VARIABLES (not pointers), use STRUCT_FETCH_* opcodes
               ; These use byte offset in contiguous memory (\ptr storage)
               If psfIsStructVar
                  psfByteOffset = psfFieldOffset * 8  ; Convert field offset to byte offset

                  ; Emit lazy STRUCT_ALLOC_LOCAL for local struct if not already done
                  ; V1.029.65: Skip for struct PARAMETERS - they receive pointer from caller
                  psfIsParam = Bool(gVarMeta(psfMetaSlot)\flags & #C2FLAG_PARAM)
                  If psfIsLocalPtr And Not psfIsParam And Not gVarMeta(psfMetaSlot)\structAllocEmitted
                     psfStructByteSize = 8
                     If FindMapElement(mapStructDefs(), psfStructType)
                        psfStructByteSize = mapStructDefs()\totalSize * 8
                     EndIf
                     EmitInt(#ljSTRUCT_ALLOC_LOCAL, gVarMeta(psfMetaSlot)\paramOffset)
                     llObjects()\j = psfStructByteSize
                     gVarMeta(psfMetaSlot)\structAllocEmitted = #True
                  EndIf

                  ; Select correct opcode based on field type and local/global
                  If psfFieldType & #C2FLAG_FLOAT
                     If psfIsLocalPtr
                        psfActualNodeType = #ljSTRUCT_FETCH_FLOAT_LOCAL
                     Else
                        psfActualNodeType = #ljSTRUCT_FETCH_FLOAT
                     EndIf
                  Else
                     ; INT or STR (strings stored as pointers = int)
                     If psfIsLocalPtr
                        psfActualNodeType = #ljSTRUCT_FETCH_INT_LOCAL
                     Else
                        psfActualNodeType = #ljSTRUCT_FETCH_INT
                     EndIf
                  EndIf

                  ; Emit STRUCT_FETCH: i = slot/paramOffset, j = byte offset
                  If psfIsLocalPtr
                     EmitInt(psfActualNodeType, gVarMeta(psfMetaSlot)\paramOffset)
                  Else
                     EmitInt(psfActualNodeType, psfMetaSlot)  ; Use metaSlot for global
                  EndIf
                  llObjects()\j = psfByteOffset
                  ; Skip the PTRSTRUCTFETCH emission below
               Else
                  ; Struct POINTER - use PTRSTRUCTFETCH (existing behavior)
                  ; Emit opcode: i=ptrVarSlot, n=fieldOffset
                  EmitInt(psfActualNodeType, psfPtrSlot)
                  llObjects()\n = psfFieldOffset
               EndIf
            EndIf


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
               pssaParts = *x\left\value
               pssaField1 = StringField(pssaParts, 1, "|")
               pssaField2 = StringField(pssaParts, 2, "|")
               pssaPtrSlot = 0
               pssaFieldOffset = 0
               pssaValueSlot = 0
               pssaStoreOp = 0
               ; V1.029.41: Declare shared variables for struct var detection
               pssaIsStructVar = #False
               pssaIsLocalPtr = #False
               pssaMetaSlot = -1
               pssaStructType = ""
               pssaFieldType = 0

               ; Check if first field is numeric (resolved) or identifier (deferred)
               ; V1.023.13: Changed condition - slot "0" should use deferred path since slot 0 is reserved
               If Val(pssaField1) > 0
                  ; Resolved format: "ptrVarSlot|fieldOffset"
                  pssaPtrSlot = Val(pssaField1)
                  pssaFieldOffset = Val(pssaField2)
                  pssaMetaSlot = pssaPtrSlot  ; For resolved format, metaSlot = ptrSlot

                  ; V1.029.41: Check if this is a struct VARIABLE or struct POINTER
                  If gVarMeta(pssaPtrSlot)\pointsToStructType <> ""
                     pssaIsStructVar = #False
                     pssaStructType = gVarMeta(pssaPtrSlot)\pointsToStructType
                  ElseIf gVarMeta(pssaPtrSlot)\structType <> ""
                     pssaIsStructVar = #True
                     pssaStructType = gVarMeta(pssaPtrSlot)\structType
                  EndIf

                  ; Look up field type for proper opcode selection
                  If pssaStructType <> "" And FindMapElement(mapStructDefs(), pssaStructType)
                     ForEach mapStructDefs()\fields()
                        If mapStructDefs()\fields()\offset = pssaFieldOffset
                           pssaFieldType = mapStructDefs()\fields()\fieldType
                           Break
                        EndIf
                     Next
                  EndIf

                  ; Determine store opcode based on AST node type (for default PTRSTRUCTSTORE)
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
                  pssaIdentName = pssaField1
                  pssaFieldName = pssaField2
                  pssaVarIdx = 0

                  ; V1.022.120: Find the variable - search LOCAL (mangled) name FIRST, then global
                  ; This matches FetchVarOffset behavior and ensures local variables are found
                  pssaPtrSlot = -1
                  pssaIsLocalPtr = #False   ; V1.029.41: Now declared at top
                  pssaMetaSlot = -1         ; V1.029.41: Now declared at top
                  pssaMangledName = ""
                  pssaFuncName = gCurrentFunctionName

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

                  ; Get struct type from pointer OR struct variable (use saved metaSlot, not encoded pssaPtrSlot)
                  ; V1.029.41: Also check structType for struct variables (vars now declared at top)
                  pssaStructType = gVarMeta(pssaMetaSlot)\pointsToStructType
                  pssaIsStructVar = #False
                  If pssaStructType = ""
                     pssaStructType = gVarMeta(pssaMetaSlot)\structType
                     pssaIsStructVar = #True
                  EndIf
                  If pssaStructType = ""
                     SetError("Variable '" + pssaIdentName + "' is not a struct pointer or struct variable", #C2ERR_CODEGEN_FAILED)
                     ProcedureReturn
                  EndIf

                  ; Look up field in struct type
                  pssaFieldOffset = -1
                  pssaFieldType = 0  ; V1.029.41: Now declared at top
                  If FindMapElement(mapStructDefs(), pssaStructType)
                     ForEach mapStructDefs()\fields()
                        If LCase(mapStructDefs()\fields()\name) = LCase(pssaFieldName)
                           pssaFieldOffset = mapStructDefs()\fields()\offset
                           pssaFieldType = mapStructDefs()\fields()\fieldType
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

               ; V1.029.41: For struct VARIABLES (not pointers), use STRUCT_STORE_* opcodes
               If pssaIsStructVar
                  pssaByteOffset = pssaFieldOffset * 8  ; Convert field offset to byte offset

                  ; Emit lazy STRUCT_ALLOC_LOCAL for local struct if not already done
                  ; V1.029.65: Skip for struct PARAMETERS - they receive pointer from caller
                  pssaIsParam = Bool(gVarMeta(pssaMetaSlot)\flags & #C2FLAG_PARAM)
                  If pssaIsLocalPtr And Not pssaIsParam And Not gVarMeta(pssaMetaSlot)\structAllocEmitted
                     pssaStructByteSize = 8
                     If FindMapElement(mapStructDefs(), pssaStructType)
                        pssaStructByteSize = mapStructDefs()\totalSize * 8
                     EndIf
                     EmitInt(#ljSTRUCT_ALLOC_LOCAL, gVarMeta(pssaMetaSlot)\paramOffset)
                     llObjects()\j = pssaStructByteSize
                     gVarMeta(pssaMetaSlot)\structAllocEmitted = #True
                  EndIf

                  ; Select correct opcode based on field type and local/global
                  If pssaFieldType & #C2FLAG_FLOAT
                     If pssaIsLocalPtr
                        pssaStoreOp = #ljSTRUCT_STORE_FLOAT_LOCAL
                     Else
                        pssaStoreOp = #ljSTRUCT_STORE_FLOAT
                     EndIf
                  Else
                     ; INT or STR (strings stored as pointers = int)
                     If pssaIsLocalPtr
                        pssaStoreOp = #ljSTRUCT_STORE_INT_LOCAL
                     Else
                        pssaStoreOp = #ljSTRUCT_STORE_INT
                     EndIf
                  EndIf

                  ; Emit STRUCT_STORE: i = slot/paramOffset, j = byte offset, ndx = value slot
                  Debug "STRUCTSTORE EMIT: pssaStoreOp=" + Str(pssaStoreOp) + " slot=" + Str(pssaMetaSlot) + " byteOffset=" + Str(pssaByteOffset) + " valueSlot=" + Str(pssaValueSlot)
                  If pssaIsLocalPtr
                     EmitInt(pssaStoreOp, gVarMeta(pssaMetaSlot)\paramOffset)
                  Else
                     EmitInt(pssaStoreOp, pssaMetaSlot)  ; Use metaSlot for global
                  EndIf
                  llObjects()\j = pssaByteOffset
                  llObjects()\ndx = pssaValueSlot
               Else
                  ; Struct POINTER - use PTRSTRUCTSTORE (existing behavior)
                  ; Emit opcode: i=ptrVarSlot, n=fieldOffset, ndx=valueSlot
                  EmitInt(pssaStoreOp, pssaPtrSlot)
                  llObjects()\n = pssaFieldOffset
                  llObjects()\ndx = pssaValueSlot
               EndIf


            ; Check if left side is pointer dereference
            ElseIf *x\left And *x\left\NodeType = #ljPTRFETCH
               ; V1.022.61: Check if this is NEW pointer variable definition vs existing dereference
               ; *ptr = &something where ptr is NEW -> pointer definition, use STORE
               ; *ptr = value where ptr EXISTS -> dereference assignment, use PTRSTORE
               ptrDefVarName = ""
               ptrDefIsNew = #True
               ptrDefSlot = 0

               If *x\left\left And *x\left\left\NodeType = #ljIDENT
                  ptrDefVarName = *x\left\left\value

                  ; Check if variable already exists in symbol table
                  ; Must account for function scope name mangling (same logic as FetchVarOffset)
                  ptrDefMangledName = ""

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
                        ptrDefSrcSlot = FetchVarOffset(*x\right\left\value)
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
               arrayStoreValueSlot = GetExprSlotOrTemp(*x\right)
               arrayStoreIndexSlot = GetExprSlotOrTemp(*x\left\right)

               ; Determine if array is local or global at compile time
               isLocalStore = 0
               arrayIndexStore = n  ; Default to global varSlot

               If gVarMeta(n)\paramOffset >= 0
                  ; V1.18.0: Local array - use paramOffset for unified gVar[] slot calculation
                  isLocalStore = 1
                  arrayIndexStore = gVarMeta(n)\paramOffset
               EndIf

               ; V1.022.22: Emit typed ARRAYSTORE directly (skip postprocessor typing)
               ; Determine type from array metadata
               arrayStoreOpcode = 0
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

            ; V1.036.0: Check if left side is multi-dimensional array indexing
            ElseIf *x\left And *x\left\NodeType = #nd_MultiDimIndex
               ; Multi-dimensional array assignment: arr[i][j] = value
               ; *x\left = multi-dim index node
               ; *x\right = value expression

               mdStoreSlot = Val(StringField(*x\left\value, 1, "|"))
               mdStoreNDims = Val(StringField(*x\left\value, 2, "|"))
               mdStoreIsLocal = 0
               mdStoreArrayIndex = mdStoreSlot

               ; Check if array is local
               If gVarMeta(mdStoreSlot)\paramOffset >= 0
                  mdStoreIsLocal = 1
                  mdStoreArrayIndex = gVarMeta(mdStoreSlot)\paramOffset
               EndIf

               ; Get value expression slot
               mdStoreValueSlot = GetExprSlotOrTemp(*x\right)

               ; Retrieve index expressions from node structure
               *mdStoreIdx0 = *x\left\right
               *mdStoreIdx1 = 0
               *mdStoreIdx2 = 0
               *mdStoreIdx3 = 0

               If mdStoreNDims >= 2 And *x\left\left
                  *mdStoreIdx1 = *x\left\left\right
               EndIf
               If mdStoreNDims >= 3 And *x\left\left
                  *mdStoreIdx2 = *x\left\left\left
               EndIf
               If mdStoreNDims >= 4 And *x\left\right
                  *mdStoreIdx3 = *x\left\right\left
               EndIf

               ; Check if all indices are compile-time constants
               mdStoreAllConst = #True
               mdStoreConstIdx0 = 0 : mdStoreConstIdx1 = 0 : mdStoreConstIdx2 = 0 : mdStoreConstIdx3 = 0
               mdStoreLinearIdx = 0

               If *mdStoreIdx0 And *mdStoreIdx0\NodeType = #ljINT
                  mdStoreConstIdx0 = Val(*mdStoreIdx0\value)
               Else
                  mdStoreAllConst = #False
               EndIf

               If mdStoreNDims >= 2
                  If *mdStoreIdx1 And *mdStoreIdx1\NodeType = #ljINT
                     mdStoreConstIdx1 = Val(*mdStoreIdx1\value)
                  Else
                     mdStoreAllConst = #False
                  EndIf
               EndIf

               If mdStoreNDims >= 3
                  If *mdStoreIdx2 And *mdStoreIdx2\NodeType = #ljINT
                     mdStoreConstIdx2 = Val(*mdStoreIdx2\value)
                  Else
                     mdStoreAllConst = #False
                  EndIf
               EndIf

               If mdStoreNDims >= 4
                  If *mdStoreIdx3 And *mdStoreIdx3\NodeType = #ljINT
                     mdStoreConstIdx3 = Val(*mdStoreIdx3\value)
                  Else
                     mdStoreAllConst = #False
                  EndIf
               EndIf

               If mdStoreAllConst
                  ; All indices are constants - compute linear index at compile time
                  mdStoreLinearIdx = mdStoreConstIdx0 * gVarMeta(mdStoreSlot)\dimStrides[0]
                  If mdStoreNDims >= 2
                     mdStoreLinearIdx + mdStoreConstIdx1 * gVarMeta(mdStoreSlot)\dimStrides[1]
                  EndIf
                  If mdStoreNDims >= 3
                     mdStoreLinearIdx + mdStoreConstIdx2 * gVarMeta(mdStoreSlot)\dimStrides[2]
                  EndIf
                  If mdStoreNDims >= 4
                     mdStoreLinearIdx + mdStoreConstIdx3 * gVarMeta(mdStoreSlot)\dimStrides[3]
                  EndIf

                  ; Create temp slot for constant linear index
                  ; V1.037.2: FIX - Use #ljINT synthetic type to create proper constant slot
                  ; FetchVarOffset with #ljINT sets CONST flag and valueInt, enabling runtime transfer
                  mdStoreConstSlot = FetchVarOffset(Str(mdStoreLinearIdx), 0, #ljINT)

                  ; Determine array type and emit store
                  mdStoreOpcode = 0
                  If gVarMeta(mdStoreSlot)\flags & #C2FLAG_STR
                     mdStoreOpcode = #ljARRAYSTORE_STR
                  ElseIf gVarMeta(mdStoreSlot)\flags & #C2FLAG_FLOAT
                     mdStoreOpcode = #ljARRAYSTORE_FLOAT
                  Else
                     mdStoreOpcode = #ljARRAYSTORE_INT
                  EndIf

                  EmitInt(mdStoreOpcode, mdStoreArrayIndex)
                  llObjects()\j = mdStoreIsLocal
                  llObjects()\ndx = mdStoreConstSlot
                  llObjects()\n = mdStoreValueSlot

                  CompilerIf #DEBUG
                     Debug "MultiDim STORE const: slot=" + Str(mdStoreSlot) + " linearIdx=" + Str(mdStoreLinearIdx)
                  CompilerEndIf

               Else
                  ; Variable indices - generate runtime computation
                  ; Push value first, then compute and push linear index

                  ; Generate code for first index * stride
                  mdStoreHasVal = #False
                  If gVarMeta(mdStoreSlot)\dimStrides[0] = 1
                     CodeGenerator(*mdStoreIdx0)
                     mdStoreHasVal = #True
                  ElseIf gVarMeta(mdStoreSlot)\dimStrides[0] > 1
                     CodeGenerator(*mdStoreIdx0)
                     EmitInt(#ljPUSH_IMM, gVarMeta(mdStoreSlot)\dimStrides[0])
                     EmitInt(#ljMULTIPLY)
                     mdStoreHasVal = #True
                  EndIf

                  ; Add remaining dimensions
                  If mdStoreNDims >= 2 And *mdStoreIdx1
                     If gVarMeta(mdStoreSlot)\dimStrides[1] = 1
                        CodeGenerator(*mdStoreIdx1)
                     Else
                        CodeGenerator(*mdStoreIdx1)
                        EmitInt(#ljPUSH_IMM, gVarMeta(mdStoreSlot)\dimStrides[1])
                        EmitInt(#ljMULTIPLY)
                     EndIf
                     If mdStoreHasVal
                        EmitInt(#ljADD)
                     EndIf
                     mdStoreHasVal = #True
                  EndIf

                  If mdStoreNDims >= 3 And *mdStoreIdx2
                     If gVarMeta(mdStoreSlot)\dimStrides[2] = 1
                        CodeGenerator(*mdStoreIdx2)
                     Else
                        CodeGenerator(*mdStoreIdx2)
                        EmitInt(#ljPUSH_IMM, gVarMeta(mdStoreSlot)\dimStrides[2])
                        EmitInt(#ljMULTIPLY)
                     EndIf
                     If mdStoreHasVal
                        EmitInt(#ljADD)
                     EndIf
                     mdStoreHasVal = #True
                  EndIf

                  If mdStoreNDims >= 4 And *mdStoreIdx3
                     If gVarMeta(mdStoreSlot)\dimStrides[3] = 1
                        CodeGenerator(*mdStoreIdx3)
                     Else
                        CodeGenerator(*mdStoreIdx3)
                        EmitInt(#ljPUSH_IMM, gVarMeta(mdStoreSlot)\dimStrides[3])
                        EmitInt(#ljMULTIPLY)
                     EndIf
                     If mdStoreHasVal
                        EmitInt(#ljADD)
                     EndIf
                  EndIf

                  ; Stack now has linear index - emit ARRAYSTORE with stack index
                  mdStoreOpcodeStack = 0
                  If gVarMeta(mdStoreSlot)\flags & #C2FLAG_STR
                     mdStoreOpcodeStack = #ljARRAYSTORE_STR
                  ElseIf gVarMeta(mdStoreSlot)\flags & #C2FLAG_FLOAT
                     mdStoreOpcodeStack = #ljARRAYSTORE_FLOAT
                  Else
                     mdStoreOpcodeStack = #ljARRAYSTORE_INT
                  EndIf

                  EmitInt(mdStoreOpcodeStack, mdStoreArrayIndex)
                  llObjects()\j = mdStoreIsLocal
                  llObjects()\ndx = -1  ; -1 indicates stack-based index
                  llObjects()\n = mdStoreValueSlot

                  CompilerIf #DEBUG
                     Debug "MultiDim STORE stack: slot=" + Str(mdStoreSlot) + " dims=" + Str(mdStoreNDims)
                  CompilerEndIf
               EndIf

            ; V1.022.0: Check if left side is struct array field access
            ; V1.022.2: Support local and global structs
            ; V1.022.20: Slot-only optimization
            ElseIf *x\left And (*x\left\NodeType = #ljSTRUCTARRAY_FETCH_INT Or *x\left\NodeType = #ljSTRUCTARRAY_FETCH_FLOAT Or *x\left\NodeType = #ljSTRUCTARRAY_FETCH_STR)
               ; Struct array field store: s\arr[i] = value
               ; *x\left\left = index expression
               ; *x\left\value = "structVarSlot|fieldOffset|fieldName"
               ; *x\right = value expression

               ; Parse value to get struct info
               sasPartsStore = *x\left\value
               sasStructSlotStore = Val(StringField(sasPartsStore, 1, "|"))
               sasFieldOffsetStore = Val(StringField(sasPartsStore, 2, "|"))
               sasIsLocalStore = 0
               sasBaseSlotStore = 0
               sasValueSlotStore = 0
               sasIndexSlotStore = 0

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
               structStoreOp = 0
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
                  aosStoreArraySlot = FetchVarOffset(*x\left\left\left\value)
                  aosStoreIsLocal = 0
                  If gVarMeta(aosStoreArraySlot)\paramOffset >= 0
                     aosStoreIsLocal = 1
                  EndIf

                  ; V1.022.45: Parse elementSize|fieldOffset from value field
                  aosStoreElementSize = Val(StringField(*x\left\value, 1, "|"))
                  aosStoreFieldOffset = Val(StringField(*x\left\value, 2, "|"))

                  ; V1.022.45: Generate code to push value to stack first
                  CodeGenerator(*x\right)

                  ; Get slot for index expression (may emit code for complex expressions)
                  aosStoreIndexSlot = GetExprSlotOrTemp(*x\left\left\right)

                  ; Select store opcode based on field type
                  aosStoreOpcode = 0
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
               ; V1.030.54: Debug slot 176 BEFORE calling FetchVarOffset in ASSIGN
               CompilerIf #DEBUG
                  If gnLastVariable > 176 And gCurrentFunctionName = "_calculatearea"
                     ; Debug "V1.030.54: ASSIGN ENTRY slot176 structType='" + gVarMeta(176)\structType + "' LHS='" + *x\left\value + "'"
                  EndIf
               CompilerEndIf
               n = FetchVarOffset( *x\left\value, *x\right, 0, *x\left\TypeHint )

               ; V1.030.63: Debug - track ASSIGN LHS for w/h
               If FindString(*x\left\value, "w") Or FindString(*x\left\value, "h")
                  ; Debug "V1.030.63 ASSIGN_LHS: LHS='" + *x\left\value + "' slot=" + Str(n) + " name='" + gVarMeta(n)\name + "' structFieldBase=" + Str(gVarMeta(n)\structFieldBase)
               EndIf

               ; V1.022.65: Check for struct-to-struct copy (same type required)
               ; destStruct = srcStruct
               scStructCopyDone = #False
               If gVarMeta(n)\structType <> "" And *x\right And *x\right\NodeType = #ljIDENT
                  scSrcSlot = FetchVarOffset(*x\right\value)
                  If scSrcSlot >= 0 And scSrcSlot < ArraySize(gVarMeta())
                     If gVarMeta(scSrcSlot)\structType = gVarMeta(n)\structType
                        ; Both are structs of same type - emit STRUCTCOPY
                        scStructType = gVarMeta(n)\structType
                        scSlotCount = 0
                        If FindMapElement(mapStructDefs(), scStructType)
                           scSlotCount = mapStructDefs()\totalSize
                        EndIf
                        If scSlotCount > 0
                           ; V1.029.12: SIMPLIFIED - FetchVarOffset already returns correct base slots
                           ; n = dest struct base slot (from FetchVarOffset at line 2668)
                           ; scSrcSlot = source struct base slot (from FetchVarOffset at line 2674)
                           ; Struct slots are allocated consecutively, so base+0 through base+size-1 are the fields

                           ; V1.029.65: Lazy STRUCT_ALLOC for destination - needed if dest was only initialized with { }
                           ; Check if dest is local (variable) vs global, and skip if it's a parameter (receives pointer from caller)
                           ; V1.029.66: GLOBAL structs are pre-allocated by vmTransferMetaToRuntime - DO NOT re-allocate!
                           ; Only emit STRUCT_ALLOC_LOCAL for LOCAL struct variables (not parameters)
                           scDestIsLocal = Bool(gVarMeta(n)\paramOffset >= 0)
                           scDestIsParam = Bool(gVarMeta(n)\flags & #C2FLAG_PARAM)
                           scByteSize = scSlotCount * 8

                           If scDestIsLocal And Not scDestIsParam And Not gVarMeta(n)\structAllocEmitted
                              ; Emit STRUCT_ALLOC_LOCAL for local struct variable
                              gEmitIntLastOp = AddElement(llObjects())
                              llObjects()\code = #ljSTRUCT_ALLOC_LOCAL
                              llObjects()\i = gVarMeta(n)\paramOffset
                              llObjects()\j = scByteSize
                              gVarMeta(n)\structAllocEmitted = #True
                           EndIf
                           ; NOTE: Global structs are NOT allocated here - vmTransferMetaToRuntime handles them

                           ; V1.029.66: Also ensure SOURCE struct is allocated IF it's a local variable
                           ; Global source structs are already allocated; local vars may need lazy allocation
                           scSrcIsLocal = Bool(gVarMeta(scSrcSlot)\paramOffset >= 0)
                           scSrcIsParam = Bool(gVarMeta(scSrcSlot)\flags & #C2FLAG_PARAM)

                           If scSrcIsLocal And Not scSrcIsParam And Not gVarMeta(scSrcSlot)\structAllocEmitted
                              gEmitIntLastOp = AddElement(llObjects())
                              llObjects()\code = #ljSTRUCT_ALLOC_LOCAL
                              llObjects()\i = gVarMeta(scSrcSlot)\paramOffset
                              llObjects()\j = scByteSize
                              gVarMeta(scSrcSlot)\structAllocEmitted = #True
                           EndIf
                           ; NOTE: Global source structs are NOT allocated here

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
                  *ptrFetchNode = #Null

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
                     ; V1.026.0: Skip check if rightType is 0 (unknown) or is a collection type
                     ; This allows generic functions like listGet that return dynamic types
                     If rightType <> 0 And Not (rightType & #C2FLAG_LIST) And Not (rightType & #C2FLAG_MAP)
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

                  ; V1.029.58: Skip type checking for struct field assignments
                  ; Struct field type is determined from struct definition, not gVarMeta(n)\flags
                  ; gVarMeta(n) returns struct base slot which has #C2FLAG_STRUCT, not the field type
                  isStructFieldAssignment = Bool(gVarMeta(n)\structFieldBase >= 0)

                  ; V1.023.26: Strict type checking - variables cannot change type
                  If Not isStructFieldAssignment And *x\left\TypeHint = #ljFLOAT And Not (gVarMeta(n)\flags & #C2FLAG_FLOAT)
                     existingTypeName = "int"
                     If gVarMeta(n)\flags & #C2FLAG_STR
                        existingTypeName = "string"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_POINTER
                        existingTypeName = "pointer"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STRUCT
                        existingTypeName = "struct"
                     EndIf
                     SetError("Variable '" + *x\left\value + "' already declared as " + existingTypeName + ", cannot re-declare as float", 10)
                  ElseIf Not isStructFieldAssignment And *x\left\TypeHint = #ljSTRING And Not (gVarMeta(n)\flags & #C2FLAG_STR)
                     existingTypeName = "int"
                     If gVarMeta(n)\flags & #C2FLAG_FLOAT
                        existingTypeName = "float"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_POINTER
                        existingTypeName = "pointer"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STRUCT
                        existingTypeName = "struct"
                     EndIf
                     SetError("Variable '" + *x\left\value + "' already declared as " + existingTypeName + ", cannot re-declare as string", 10)
                  ElseIf Not isStructFieldAssignment And *x\left\TypeHint = #ljINT And Not (gVarMeta(n)\flags & #C2FLAG_INT)
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

                  ; V1.029.54: For struct field assignments, skip type conversion
                  ; STRUCT_STORE_* opcodes handle the actual field type from struct definition
                  ; The slot's flags may have wrong type (defaults to INT)
                  ElseIf gVarMeta(n)\structFieldBase >= 0
                     ; Just generate the RHS value - EmitInt will use correct STRUCT_STORE_* opcode
                     CodeGenerator( *x\right )
                     ; Skip all type conversion logic
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
                        hasExplicitType = #False
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

               ; V1.030.62: Handle struct initialization { } - allocate only, don't emit store
               ; The { } syntax just allocates the struct with default values, no actual store needed
               ; Without this check, STORE_STRUCT is emitted which pops garbage from empty stack
               ; V1.033.59: BUGFIX - Variables pre-declared at procedure scope per CLAUDE.md rule #5
               If *x\right And *x\right\NodeType = #ljStructInit And (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                  ; Emit STRUCT_ALLOC_LOCAL if not already allocated (for local structs only)
                  If gVarMeta(n)\paramOffset >= 0 And Not gVarMeta(n)\structAllocEmitted
                     ; Calculate byte size from struct definition
                     initStructByteSize = 8  ; Default 1 field
                     If gVarMeta(n)\structType <> "" And FindMapElement(mapStructDefs(), gVarMeta(n)\structType)
                        initStructByteSize = mapStructDefs()\totalSize * 8
                     EndIf

                     gEmitIntLastOp = AddElement(llObjects())
                     llObjects()\code = #ljSTRUCT_ALLOC_LOCAL
                     llObjects()\i = gVarMeta(n)\paramOffset
                     llObjects()\j = initStructByteSize

                     gVarMeta(n)\structAllocEmitted = #True
                  EndIf
                  ; Skip store emission - { } just allocates, doesn't store anything
                  ; Global structs are allocated in vmTransferMetaToRuntime via elementSize
               ; V1.029.84: Emit appropriate STORE variant based on variable type
               ; For struct variables, use STORE_STRUCT which copies both \i and \ptr in one operation
               ; V1.030.27/29/31: Struct FIELD assignment for LOCAL structs should NOT use STORE_STRUCT
               ; STORE_STRUCT is for whole-struct copies (localStruct = otherStruct)
               ; For field assignment (local.x = value), emit STOREF/STORES/STORE based on field type
               ; Only applies to LOCAL structs (paramOffset >= 0) which would trigger STORE_STRUCT bug
               ElseIf gVarMeta(n)\structFieldBase >= 0 And gVarMeta(n)\paramOffset >= 0
                  ; Local struct field assignment - look up field type from struct definition
                  ; V1.030.31: Use field offset ranges to find primitive field type
                  ; Field range: [field.offset, nextField.offset) or [field.offset, totalSize) for last
                  ; IMPORTANT: Don't change map element inside ForEach - corrupts iterator!
                  ; V1.033.59: Protected declarations moved outside If block to avoid stack corruption
                  sfaFieldType = 0  ; Default to INT
                  sfaBaseSlot = gVarMeta(n)\structFieldBase
                  ; V1.030.65: FIX - Convert byte offset to slot index (divide by 8)
                  ; structFieldOffset is in bytes, but mapStructDefs field offsets are in slot units
                  ; Without this conversion, field type lookup fails for non-zero offsets (y fields)
                  ; causing wrong STORE opcode type (INT instead of FLOAT) and garbage values
                  sfaFlatOffset = gVarMeta(n)\structFieldOffset / 8
                  sfaCurrentType = gVarMeta(sfaBaseSlot)\structType
                  sfaFound = #False
                  sfaNextType = ""
                  sfaMaxIter = 10  ; Safety limit for nested struct depth

                  ; Walk nested struct chain to find primitive field type
                  While sfaCurrentType <> "" And Not sfaFound And sfaMaxIter > 0
                     sfaMaxIter = sfaMaxIter - 1
                     sfaNextType = ""
                     If FindMapElement(mapStructDefs(), sfaCurrentType)
                        sfaTotalSize = mapStructDefs()\totalSize
                        ; Find which field contains the target offset using offset ranges
                        ForEach mapStructDefs()\fields()
                           sfaFieldStart = mapStructDefs()\fields()\offset
                           ; Get end offset: peek at next field or use totalSize
                           If NextElement(mapStructDefs()\fields())
                              sfaFieldEnd = mapStructDefs()\fields()\offset
                              PreviousElement(mapStructDefs()\fields())
                           Else
                              sfaFieldEnd = sfaTotalSize
                           EndIf
                           ; Check if target is in this field's range
                           If sfaFlatOffset >= sfaFieldStart And sfaFlatOffset < sfaFieldEnd
                              If mapStructDefs()\fields()\structType <> ""
                                 ; Nested struct - save for next iteration
                                 sfaNextType = mapStructDefs()\fields()\structType
                                 sfaFlatOffset = sfaFlatOffset - sfaFieldStart
                              Else
                                 ; Primitive field found
                                 sfaFieldType = mapStructDefs()\fields()\fieldType
                                 sfaFound = #True
                              EndIf
                              Break
                           EndIf
                        Next
                        ; Continue with nested type if found
                        If sfaNextType <> ""
                           sfaCurrentType = sfaNextType
                        Else
                           Break  ; Done - either found primitive or no match
                        EndIf
                     Else
                        Break  ; Struct type not found
                     EndIf
                  Wend

                  ; Emit appropriate STORE based on field type (EmitInt will convert to STRUCT_STORE_*)
                  If sfaFieldType & #C2FLAG_STR
                     EmitInt( #ljSTORES, n )
                  ElseIf sfaFieldType & #C2FLAG_FLOAT
                     EmitInt( #ljSTOREF, n )
                  Else
                     EmitInt( #ljSTORE, n )
                  EndIf
               ElseIf gVarMeta(n)\structFieldBase >= 0
                  ; Global struct field assignment - use type flags from variable metadata
                  ; V1.030.29: For global struct fields, fall through to type-based emit below
                  If gVarMeta(n)\flags & #C2FLAG_STR
                     EmitInt( #ljSTORES, n )
                  ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                     EmitInt( #ljSTOREF, n )
                  Else
                     EmitInt( #ljSTORE, n )
                  EndIf
               ElseIf (gVarMeta(n)\flags & #C2FLAG_STRUCT) And gVarMeta(n)\paramOffset >= 0
                  ; V1.034.24: Local struct variable - use unified STORE_STRUCT with j=1
                  ; The stVT structure has SEPARATE \i and \ptr fields (not a union)
                  ; Regular STORE only copies \i, but StructGetStr accesses \ptr
                  AddElement(llObjects())
                  llObjects()\code = #ljSTORE_STRUCT
                  llObjects()\i = gVarMeta(n)\paramOffset
                  llObjects()\j = 1
                  ; Mark as allocated to prevent later field access from allocating new memory
                  gVarMeta(n)\structAllocEmitted = #True
                  CompilerIf #DEBUG
                     ; Debug "V1.034.24: Emitted STORE_STRUCT j=1 for '" + gVarMeta(n)\name + "' at offset " + Str(gVarMeta(n)\paramOffset)
                  CompilerEndIf
               ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                  EmitInt( #ljSTORES, n )
               ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                  EmitInt( #ljSTOREF, n )
               Else
                  EmitInt( #ljSTORE, n )
               EndIf

               ; Type propagation: If assigning a typed value to an untyped var, update the var
               ; V1.034.24: Only check unified MOV opcodes (LMOV eliminated)
               ; V1.033.60: BUGFIX - Only check llObjects() if an element was actually emitted
               ; Struct init path doesn't emit anything for global structs, so llObjects() may be invalid
               If ListSize(llObjects()) > 0
                  If llObjects()\code <> #ljMOV And llObjects()\code <> #ljMOVS And llObjects()\code <> #ljMOVF
                     ; Keep the variable's declared type (don't change it)
                     ; Type checking could be added here later
                  EndIf
               EndIf

               EndIf  ; V1.022.65: End If Not scStructCopyDone
            EndIf
         Case #ljPRE_INC
            ; Pre-increment: ++var
            ; V1.034.24: Uses unified INC_VAR_PRE with j=1 for locals
            ; V1.034.69: Pointer conversion moved to TypeInference (mapVariableTypes not available here)
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               AddElement(llObjects())
               llObjects()\code = #ljINC_VAR_PRE
               If gVarMeta(n)\paramOffset >= 0
                  llObjects()\i = gVarMeta(n)\paramOffset
                  llObjects()\j = 1
               Else
                  llObjects()\i = n
               EndIf
            EndIf

         Case #ljPRE_DEC
            ; Pre-decrement: --var
            ; V1.034.24: Uses unified DEC_VAR_PRE with j=1 for locals
            ; V1.034.69: Pointer conversion moved to TypeInference (mapVariableTypes not available here)
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               AddElement(llObjects())
               llObjects()\code = #ljDEC_VAR_PRE
               If gVarMeta(n)\paramOffset >= 0
                  llObjects()\i = gVarMeta(n)\paramOffset
                  llObjects()\j = 1
               Else
                  llObjects()\i = n
               EndIf
            EndIf

         Case #ljPOST_INC
            ; Post-increment: var++
            ; V1.034.24: Uses unified INC_VAR_POST with j=1 for locals
            ; V1.034.69: Pointer conversion moved to TypeInference (mapVariableTypes not available here)
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               AddElement(llObjects())
               llObjects()\code = #ljINC_VAR_POST
               If gVarMeta(n)\paramOffset >= 0
                  llObjects()\i = gVarMeta(n)\paramOffset
                  llObjects()\j = 1
               Else
                  llObjects()\i = n
               EndIf
            EndIf

         Case #ljPOST_DEC
            ; Post-decrement: var--
            ; V1.034.24: Uses unified DEC_VAR_POST with j=1 for locals
            ; V1.034.69: Pointer conversion moved to TypeInference (mapVariableTypes not available here)
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               AddElement(llObjects())
               llObjects()\code = #ljDEC_VAR_POST
               If gVarMeta(n)\paramOffset >= 0
                  llObjects()\i = gVarMeta(n)\paramOffset
                  llObjects()\j = 1
               Else
                  llObjects()\i = n
               EndIf
            EndIf

         Case #ljreturn
            ; Note: The actual return type is determined at the SEQ level
            ; This case should not normally be reached since SEQ handler processes returns
            EmitInt( #ljreturn )

         Case #ljIF
            ; V1.031.114: Iterative else-if chain processing to avoid stack overflow
            ; When else-body is another IF, we iterate instead of recursing
            *ifNode = *x
            ifJmpCount = 0

            While *ifNode And *ifNode\NodeType = #ljIF
               CodeGenerator( *ifNode\left )   ; Generate condition
               EmitInt( #ljJZ)
               p1 = hole()
               CodeGenerator( *ifNode\right\left )   ; Generate then-body

               If *ifNode\right\right
                  ; Has else/else-if - emit JMP to skip else branches
                  EmitInt( #ljJMP)
                  If ifJmpCount < #MAX_ELSEIF_BRANCHES
                     ifJmpHoles(ifJmpCount) = hole()
                     ifJmpCount + 1
                  Else
                     Debug "WARNING: Exceeded " + Str(#MAX_ELSEIF_BRANCHES) + " else-if branches"
                  EndIf
               EndIf

               EmitInt( #ljNOOPIF )   ; Marker after if-body for JZ target
               fix( p1 )

               If *ifNode\right\right
                  If *ifNode\right\right\NodeType = #ljIF
                     ; Else-if chain: continue iterating instead of deep recursion
                     *ifNode = *ifNode\right\right
                  Else
                     ; Final else block: generate it and exit
                     CodeGenerator( *ifNode\right\right )
                     *ifNode = #Null
                  EndIf
               Else
                  ; No else branch - exit loop
                  *ifNode = #Null
               EndIf
            Wend

            ; Fix all JMP holes to point to the end (only if there were else branches)
            If ifJmpCount > 0
               EmitInt( #ljNOOPIF )   ; Final marker for all JMPs to target
               For i = 0 To ifJmpCount - 1
                  fix( ifJmpHoles(i) )
               Next
            EndIf

         Case #ljTERNARY
            ; Ternary operator: condition ? true_expr : false_expr
            ; *x\left = condition
            ; *x\right = COLON node with true_expr in left, false_expr in right
            ; Using dedicated TENIF/TENELSE opcodes for cleaner implementation
            If *x\left And *x\right
               gInTernary = #True                ; Disable PUSH/FETCH?MOV optimization

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

            ; V1.024.0: Push loop context for break/continue support
            AddElement(llLoopContext())
            llLoopContext()\loopStartPtr = p1
            llLoopContext()\breakCount = 0
            llLoopContext()\continueCount = 0    ; V1.024.2
            llLoopContext()\isSwitch = #False
            llLoopContext()\isForLoop = #False

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

            ; V1.024.0: Fix all break holes to point to loop end, then pop context
            For i = 0 To llLoopContext()\breakCount - 1
               fix(llLoopContext()\breakHoles[i])
            Next
            DeleteElement(llLoopContext())

         ; V1.024.0: C-style for loop
         Case #ljFOR
            ; AST structure: left = init, right = SEQ(cond, SEQ(update, body))
            *forInit = *x\left
            *forCond = 0
            *forUpdate = 0
            *forBody = 0

            If *x\right
               *forCond = *x\right\left
               If *x\right\right
                  *forUpdate = *x\right\right\left
                  *forBody = *x\right\right\right
               EndIf
            EndIf

            ; Generate init code (outside loop)
            If *forInit
               CodeGenerator(*forInit)
            EndIf

            ; Loop start marker
            EmitInt(#ljNOOPIF)
            p1 = @llObjects()

            ; Push loop context
            AddElement(llLoopContext())
            llLoopContext()\loopStartPtr = p1
            llLoopContext()\breakCount = 0
            llLoopContext()\continueCount = 0    ; V1.024.2
            llLoopContext()\isSwitch = #False
            llLoopContext()\isForLoop = #True

            ; Generate condition (if empty = infinite loop, no JZ)
            If *forCond
               CodeGenerator(*forCond)
               EmitInt(#ljJZ)
               p2 = Hole()
            Else
               p2 = 0
            EndIf

            ; Generate body
            If *forBody
               CodeGenerator(*forBody)
            EndIf

            ; Update marker (continue jumps here for FOR loops)
            EmitInt(#ljNOOPIF)
            llLoopContext()\loopUpdatePtr = @llObjects()

            ; V1.024.2: Fix continue holes to point to update section
            For i = 0 To llLoopContext()\continueCount - 1
               ; Find the hole and set its target
               ForEach llHoles()
                  If llHoles()\location = llLoopContext()\continueHoles[i]
                     llHoles()\src = llLoopContext()\loopUpdatePtr
                     Break
                  EndIf
               Next
            Next

            ; Generate update code
            If *forUpdate
               CodeGenerator(*forUpdate)
               ; V1.024.25: Drop unused values from for loop update expression
               ; POST_INC and POST_DEC push old value, PRE_INC and PRE_DEC push new value
               ; When used as update expression, these values are unused and must be dropped
               ; V1.031.10: Use DROP (discard without storing) instead of POP
               ; POP requires a slot number and was incorrectly storing to gVar(0)
               If *forUpdate\NodeType = #ljPOST_INC Or *forUpdate\NodeType = #ljPOST_DEC Or
                  *forUpdate\NodeType = #ljPRE_INC Or *forUpdate\NodeType = #ljPRE_DEC
                  EmitInt( #ljDROP )
               EndIf
            EndIf

            ; Jump back to loop start
            EmitInt(#ljJMP)
            *pJmp = @llObjects()

            ; Create backward jump hole
            AddElement(llHoles())
            llHoles()\mode = #C2HOLE_FORLOOP
            llHoles()\location = *pJmp
            llHoles()\src = p1

            ; Loop end marker
            EmitInt(#ljNOOPIF)

            ; Fix JZ hole if condition exists
            If p2
               fix(p2)
            EndIf

            ; Fix all break holes to point to loop end
            For i = 0 To llLoopContext()\breakCount - 1
               fix(llLoopContext()\breakHoles[i])
            Next
            DeleteElement(llLoopContext())

         ; V1.034.6: foreach loop for lists and maps
         ; foreach collection { body }
         ; Uses stack-based iterator so nested loops work correctly
         Case #ljFOREACH
            ; Get collection expression - typically an identifier
            *forEachColl = *x\left
            *forEachBody = *x\right

            ; Determine if it's a list or map by checking variable flags
            foreachIsMap = #False
            foreachSlot = -1
            foreachVarName = ""

            If *forEachColl And *forEachColl\NodeType = #ljIDENT
               foreachVarName = *forEachColl\value
               ; Look up variable to get type info
               foreachSlot = FindVariableSlotByName(foreachVarName, gCurrentFunctionName)
               If foreachSlot >= 0
                  If gVarMeta(foreachSlot)\flags & #C2FLAG_MAP
                     foreachIsMap = #True
                  EndIf
               EndIf
            EndIf

            ; Initialize iterator on stack: FOREACH_*_INIT pushes iter=-1
            ; The varSlot is stored in instruction \i field, not on stack
            If foreachIsMap
               EmitInt(#ljFOREACH_MAP_INIT, foreachSlot)
            Else
               EmitInt(#ljFOREACH_LIST_INIT, foreachSlot)
            EndIf

            ; Loop start marker
            EmitInt(#ljNOOPIF)
            p1 = @llObjects()

            ; Push loop context for break/continue
            AddElement(llLoopContext())
            llLoopContext()\loopStartPtr = p1
            llLoopContext()\breakCount = 0
            llLoopContext()\continueCount = 0
            llLoopContext()\isSwitch = #False
            llLoopContext()\isForLoop = #False  ; Treat like while for continue

            ; Advance iterator and check if valid
            ; FOREACH_*_NEXT reads varSlot from instruction \i, iter from stack
            ; Stack: [iter] -> [iter', success]
            If foreachIsMap
               EmitInt(#ljFOREACH_MAP_NEXT, foreachSlot)
            Else
               EmitInt(#ljFOREACH_LIST_NEXT, foreachSlot)
            EndIf

            ; JZ to end if iterator exhausted (success = 0)
            EmitInt(#ljJZ)
            p2 = Hole()

            ; Generate body
            If *forEachBody
               CodeGenerator(*forEachBody)
            EndIf

            ; Jump back to loop start
            EmitInt(#ljJMP)
            *pJmp = @llObjects()

            ; Create backward jump hole
            AddElement(llHoles())
            llHoles()\mode = #C2HOLE_LOOPBACK
            llHoles()\location = *pJmp
            llHoles()\src = p1

            ; Loop end marker
            EmitInt(#ljNOOPIF)

            ; Fix JZ hole to point to loop end
            fix(p2)

            ; Cleanup: pop iterator from stack
            EmitInt(#ljFOREACH_END)

            ; Fix all break holes to point to loop end
            For i = 0 To llLoopContext()\breakCount - 1
               fix(llLoopContext()\breakHoles[i])
            Next
            DeleteElement(llLoopContext())

         ; V1.024.0: switch statement
         Case #ljSWITCH
            ; V1.024.4: Get switch expression type for typed DUP
            switchExprType = GetExprResultType(*x\left)

            ; Evaluate switch expression and keep on stack
            CodeGenerator(*x\left)

            ; Push switch context (break allowed, continue not)
            AddElement(llLoopContext())
            llLoopContext()\breakCount = 0
            llLoopContext()\continueCount = 0    ; V1.024.2
            llLoopContext()\isSwitch = #True
            llLoopContext()\isForLoop = #False

            ; V1.024.15: Process cases using arrays instead of linked lists
            ; This avoids recursion issues with Protected NewList
            *caseList = *x\right
            caseNodeArrCount = 0
            caseCount = 0
            defaultHole = 0
            hasDefault = #False

            ; First pass: generate comparison jumps AND collect nodes/holes into arrays
            *caseIter = *caseList
            While *caseIter
               *caseNode = 0
               If *caseIter\NodeType = #ljSEQ
                  *caseNode = *caseIter\right
                  *caseIter = *caseIter\left
               Else
                  *caseNode = *caseIter
                  *caseIter = 0
               EndIf

               If *caseNode
                  ; Store node pointer in array (AST order = reverse source)
                  caseNodeArr(caseNodeArrCount) = *caseNode

                  If *caseNode\NodeType = #ljCASE
                     ; V1.024.4: Use typed DUP for speed
                     If switchExprType & #C2FLAG_STR
                        EmitInt(#ljDUP_S)
                     ElseIf switchExprType & #C2FLAG_FLOAT
                        EmitInt(#ljDUP_F)
                     Else
                        EmitInt(#ljDUP_I)  ; Integer, pointers, arrays, structs
                     EndIf
                     ; Generate case value
                     CodeGenerator(*caseNode\left)
                     ; Compare
                     EmitInt(#ljEQUAL)
                     ; Jump if equal
                     EmitInt(#ljJNZ)
                     caseHoleArr(caseNodeArrCount) = Hole()
                     caseCount + 1
                  ElseIf *caseNode\NodeType = #ljDEFAULT_CASE
                     hasDefault = #True
                     caseHoleArr(caseNodeArrCount) = -1  ; Mark as default (no hole)
                  EndIf
                  caseNodeArrCount + 1
               EndIf
            Wend

            ; Jump to default or end if no case matched
            EmitInt(#ljJMP)
            defaultHole = Hole()

            ; Second pass: generate case bodies in REVERSE order (which is source order)
            ; V1.024.21: NOOPIF required before case bodies - fix() captures current position,
            ; so we need a landing marker. Postprocessor will skip past NOOPIF to actual code.
            ; Iterate arrays backwards using For loop - safe from recursion
            For caseIdx = caseNodeArrCount - 1 To 0 Step -1
               *caseNode = caseNodeArr(caseIdx)
               If *caseNode\NodeType = #ljCASE
                  ; Emit NOOPIF as landing marker for case jump
                  EmitInt(#ljNOOPIF)
                  ; Fix case jump hole to this NOOPIF (postprocessor skips to actual body)
                  fix(caseHoleArr(caseIdx))
                  ; Generate case body (fallthrough by default)
                  If *caseNode\right
                     CodeGenerator(*caseNode\right)
                  EndIf
               ElseIf *caseNode\NodeType = #ljDEFAULT_CASE
                  ; Emit NOOPIF as landing marker for default jump
                  EmitInt(#ljNOOPIF)
                  ; Fix default jump hole to this NOOPIF (postprocessor skips to actual body)
                  fix(defaultHole)
                  defaultHole = 0
                  ; Generate default body
                  If *caseNode\right
                     CodeGenerator(*caseNode\right)
                  EndIf
               EndIf
            Next

            ; V1.024.21: Emit NOOPIF as landing marker for break and default-if-not-present
            EmitInt(#ljNOOPIF)

            ; Fix break holes to this NOOPIF (postprocessor skips to DROP)
            For i = 0 To llLoopContext()\breakCount - 1
               fix(llLoopContext()\breakHoles[i])
            Next

            ; Fix default hole (if no default case) to this NOOPIF
            If defaultHole
               fix(defaultHole)
            EndIf

            ; DROP removes the switch value from stack
            EmitInt(#ljDROP)

            DeleteElement(llLoopContext())

         ; V1.024.0: break statement
         Case #ljBREAK
            If ListSize(llLoopContext()) = 0
               SetError("break outside of loop or switch", #C2ERR_BREAK_OUTSIDE_LOOP)
            Else
               ; Emit JMP and save hole ID in current loop context
               EmitInt(#ljJMP)
               p1 = Hole()
               llLoopContext()\breakHoles[llLoopContext()\breakCount] = p1
               llLoopContext()\breakCount + 1
            EndIf

         ; V1.024.0: continue statement
         Case #ljCONTINUE
            If ListSize(llLoopContext()) = 0
               SetError("continue outside of loop", #C2ERR_CONTINUE_OUTSIDE_LOOP)
            ElseIf llLoopContext()\isSwitch
               ; Find enclosing loop (not switch)
               foundLoop = #False
               PushListPosition(llLoopContext())
               While PreviousElement(llLoopContext())
                  If Not llLoopContext()\isSwitch
                     foundLoop = #True
                     Break
                  EndIf
               Wend

               If foundLoop
                  ; Emit JMP to loop start (or update for FOR)
                  EmitInt(#ljJMP)
                  *pJmp = @llObjects()

                  ; Create continue hole
                  AddElement(llHoles())
                  llHoles()\mode = #C2HOLE_CONTINUE
                  llHoles()\location = *pJmp

                  ; V1.024.2: For FOR loops, store hole for later fixing (loopUpdatePtr not set yet)
                  If llLoopContext()\isForLoop
                     llLoopContext()\continueHoles[llLoopContext()\continueCount] = *pJmp
                     llLoopContext()\continueCount + 1
                     llHoles()\src = 0  ; Will be fixed later
                  Else
                     llHoles()\src = llLoopContext()\loopStartPtr
                  EndIf
               Else
                  SetError("continue not in loop", #C2ERR_CONTINUE_OUTSIDE_LOOP)
               EndIf
               PopListPosition(llLoopContext())
            Else
               ; Emit JMP to loop start (or update for FOR)
               EmitInt(#ljJMP)
               *pJmp = @llObjects()

               ; Create continue hole
               AddElement(llHoles())
               llHoles()\mode = #C2HOLE_CONTINUE
               llHoles()\location = *pJmp

               ; V1.024.2: For FOR loops, store hole for later fixing (loopUpdatePtr not set yet)
               If llLoopContext()\isForLoop
                  llLoopContext()\continueHoles[llLoopContext()\continueCount] = *pJmp
                  llLoopContext()\continueCount + 1
                  llHoles()\src = 0  ; Will be fixed later
               Else
                  llHoles()\src = llLoopContext()\loopStartPtr
               EndIf
            EndIf

         Case #ljSEQ
            ; V1.033.31: Iterative SEQ processing to prevent stack overflow on large files
            ; The AST uses LEFT-recursive SEQ: SEQ(SEQ(SEQ(..., stmt1), stmt2), stmt3)
            ; We flatten by following the left chain, collecting right children, then process in order

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
               ; V1.033.31: Iterative flattening for LEFT-recursive SEQ chains
               ; Flatten the left-recursive SEQ chain into a list, then process in order
               ; This avoids deep recursion for files with many statements

               ; Count depth of left SEQ chain
               *seqWalk = *x
               seqDepth = 0
               While *seqWalk And *seqWalk\NodeType = #ljSEQ
                  seqDepth + 1
                  *seqWalk = *seqWalk\left
               Wend

               ; If shallow (< 100 levels), use simple recursion for efficiency
               If seqDepth < 100
                  ; V1.035.14: Check if right child is a function call - if so, left is args
                  ; Don't drop increment results when they're function arguments
                  savedInFuncArgs = gInFuncArgs
                  If *x\right And *x\right\NodeType = #ljCall
                     gInFuncArgs = #True
                  EndIf

                  If *x\left
                     CodeGenerator( *x\left )
                  EndIf

                  ; V1.035.14: Restore flag after processing args, before processing Call
                  gInFuncArgs = savedInFuncArgs

                  If *x\right
                     CodeGenerator( *x\right )
                     ; V1.035.14: Only DROP if NOT in function args context
                     If Not gInFuncArgs
                        If *x\right\NodeType = #ljPOST_INC Or *x\right\NodeType = #ljPOST_DEC Or
                           *x\right\NodeType = #ljPRE_INC Or *x\right\NodeType = #ljPRE_DEC
                           EmitInt( #ljDROP )
                        EndIf
                     EndIf
                  EndIf
               Else
                  ; Deep chain - use iterative approach
                  ; Collect all nodes by walking the left chain, then process in correct order
                  NewList llSeqNodes.i()

                  ; Walk down the left chain, collecting right children and leaf left
                  *seqWalk = *x
                  While *seqWalk And *seqWalk\NodeType = #ljSEQ
                     ; Add right child to list (these are the statements)
                     If *seqWalk\right
                        AddElement(llSeqNodes())
                        llSeqNodes() = *seqWalk\right
                     EndIf
                     ; Move to left child (next SEQ or bottom statement)
                     If *seqWalk\left And *seqWalk\left\NodeType = #ljSEQ
                        *seqWalk = *seqWalk\left
                     Else
                        ; Bottom of chain - add the final left child
                        If *seqWalk\left
                           AddElement(llSeqNodes())
                           llSeqNodes() = *seqWalk\left
                        EndIf
                        Break
                     EndIf
                  Wend

                  ; Process in reverse order (oldest statement first)
                  ; The list was built from newest to oldest, so reverse iterate
                  If LastElement(llSeqNodes())
                     Repeat
                        *stmtNode = llSeqNodes()
                        If *stmtNode
                           CodeGenerator(*stmtNode)
                           ; Handle DROP for increment/decrement statements
                           ; V1.035.14: Only DROP if NOT in function args context
                           If Not gInFuncArgs
                              If *stmtNode\NodeType = #ljPOST_INC Or *stmtNode\NodeType = #ljPOST_DEC Or
                                 *stmtNode\NodeType = #ljPRE_INC Or *stmtNode\NodeType = #ljPRE_DEC
                                 EmitInt( #ljDROP )
                              EndIf
                           EndIf
                        EndIf
                     Until Not PreviousElement(llSeqNodes())
                  EndIf

                  FreeList(llSeqNodes())
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
            ; V1.029.75: Debug function ID lookup (only for functions 5,6,7,8)
            ljfDebugId = Val(*x\value)
            CompilerIf #DEBUG
               If ljfDebugId >= 5 And ljfDebugId <= 8
                  ; Debug "V1.029.75: #ljFunction funcId=" + Str(ljfDebugId)
               EndIf
            CompilerEndIf
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
                  ; V1.033.17: Populate function name lookup table for ASMLine display
                  ; V1.033.17/50: Populate function name lookup table for ASMLine display
                  If gCodeGenFunction >= 0
                     EnsureFuncArrayCapacity(gCodeGenFunction)
                     gFuncNames(gCodeGenFunction) = Mid(gCurrentFunctionName, 2)  ; Remove leading underscore
                  EndIf
                  ; V1.029.75: Debug match found (only for functions 5,6,7,8)
                  CompilerIf #DEBUG
                     If ljfDebugId >= 5 And ljfDebugId <= 8
                        Debug "  MATCH! '" + gCurrentFunctionName + "' nParams=" + Str(mapModules()\nParams) + " -> gCodeGenFunction=" + Str(gCodeGenFunction) + " gCodeGenParamIndex=" + Str(gCodeGenParamIndex) + " gCodeGenLocalIndex=" + Str(gCodeGenLocalIndex)
                     EndIf
                  CompilerEndIf

                  ; V1.029.68: Handle struct params that were pre-created during AST parsing
                  ; These params were processed by #ljPOP BEFORE #ljFunction was reached
                  ; (AST order is actually SEQ[marker, params], so marker IS first, but struct
                  ; params still need paramOffset set here because they were pre-created in AST).
                  ; The #ljPOP skip check will handle not overwriting and still decrementing.
                  ;
                  ; For mixed params like func(obj.Struct, dx.f, dy.f):
                  ; - Caller pushes left-to-right: obj, dx, dy
                  ; - CALL stores them: LOCAL[0]=dy, LOCAL[1]=dx, LOCAL[2]=obj
                  ; - AST processes right-to-left: dy, dx, obj (gCodeGenParamIndex: 2,1,0)
                  ; - paramOffset formula: (gCodeGenLocalIndex - 1) - gCodeGenParamIndex
                  ; - dy: (3-1)-2=0, dx: (3-1)-1=1, obj: (3-1)-0=2
                  ;
                  ; For struct params (obj), we pre-calculate its paramOffset based on its
                  ; position in the original param list (0=first param -> offset=nParams-1).
                  ljfStructParamPrefix = LCase(gCurrentFunctionName + "_")
                  ljfVarIdx = 0
                  For ljfVarIdx = 0 To gnLastVariable - 1
                     ; Check for pre-created struct params (have PARAM|STRUCT flags, mangled name)
                     If (gVarMeta(ljfVarIdx)\flags & #C2FLAG_PARAM) And (gVarMeta(ljfVarIdx)\flags & #C2FLAG_STRUCT)
                        If LCase(Left(gVarMeta(ljfVarIdx)\name, Len(ljfStructParamPrefix))) = ljfStructParamPrefix
                           ; Found a struct param for this function
                           ; For struct params, the position info was stored in elementSize during AST
                           ; Actually we don't have position, but for single struct param functions,
                           ; paramOffset = nParams - 1 - 0 = gCodeGenParamIndex (since gCodeGenParamIndex = nParams - 1)
                           ; For now, assume first struct param is first param (position 0)
                           ; TODO: Handle multiple struct params or struct params in non-first positions
                           gVarMeta(ljfVarIdx)\paramOffset = gCodeGenParamIndex
                           CompilerIf #DEBUG
                              ; Debug "V1.029.68: Set struct param '" + gVarMeta(ljfVarIdx)\name + "' paramOffset=" + Str(gVarMeta(ljfVarIdx)\paramOffset)
                           CompilerEndIf
                        EndIf
                     EndIf
                  Next
                  ; DON'T decrement gCodeGenParamIndex here - let #ljPOP handle it
                  ; This ensures non-struct params get correct offsets

                  Break
               EndIf
            Next
            ; V1.029.75: Debug if no match found (only for functions 5,6,7,8)
            CompilerIf #DEBUG
               If gCodeGenFunction = 0 And ljfDebugId >= 5 And ljfDebugId <= 8
                  Debug "  ERROR: No match found for funcId=" + Str(ljfDebugId)
               EndIf
            CompilerEndIf

         Case #ljPRTC, #ljPRTI, #ljPRTS, #ljPRTF, #ljprint
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType )

         Case #ljLESS, #ljGREATER, #ljLESSEQUAL, #ljGreaterEqual, #ljEQUAL, #ljNotEqual,
              #ljAdd, #ljSUBTRACT, #ljDIVIDE, #ljMULTIPLY

            leftType    = GetExprResultType(*x\left)
            rightType   = GetExprResultType(*x\right)
            ; Debug "V1.030.41: BINARY OP " + Str(*x\NodeType) + " leftType=" + Str(leftType) + " rightType=" + Str(rightType) + " FLOAT=" + Str(#C2FLAG_FLOAT)

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
               ; V1.034.65: Use leftType which now includes #C2FLAG_POINTER from GetExprResultType
               isPointerArithmetic = #False
               If (*x\NodeType = #ljAdd Or *x\NodeType = #ljSUBTRACT) And *x\left
                  ; V1.034.66: Check leftType for pointer flag (includes all pointer variable types)
                  If leftType & #C2FLAG_POINTER
                     isPointerArithmetic = #True
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

         Case #ljOr, #ljAND, #ljMOD, #ljXOR, #ljSHL, #ljSHR  ; V1.034.30: Added bit shift operators
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

                  ; V1.027.2: Check if this is a local array (paramOffset >= 0)
                  isLocalArray = Bool(gVarMeta(n)\paramOffset >= 0)
                  localArrayOffset = gVarMeta(n)\paramOffset

                  ; Determine opcode based on array type from metadata (not TypeHint)
                  ; Use gVarMeta flags like normal array indexing does
                  arrayOpcode = 0
                  arrayType = gVarMeta(n)\flags & #C2FLAG_TYPE

                  ; V1.033.34: Debug trace for GETARRAYADDR type selection
                  OSDebug("V1.033.34: GETARRAYADDR for '" + *x\left\left\value + "' n=" + Str(n) + " name='" + gVarMeta(n)\name + "' flags=$" + Hex(gVarMeta(n)\flags,#PB_Word) + " arrayType=$" + Hex(arrayType,#PB_Word) + " isLocal=" + Str(isLocalArray) + " paramOffset=" + Str(gVarMeta(n)\paramOffset))

                  If isLocalArray
                     ; V1.027.2: Use local array address opcodes
                     If arrayType = #C2FLAG_STR
                        arrayOpcode = #ljGETLOCALARRAYADDRS
                        OSDebug("  -> Branch: LOCAL STR, opcode=" + Str(arrayOpcode))
                     ElseIf arrayType = #C2FLAG_FLOAT
                        arrayOpcode = #ljGETLOCALARRAYADDRF
                        OSDebug("  -> Branch: LOCAL FLOAT, opcode=" + Str(arrayOpcode))
                     Else
                        arrayOpcode = #ljGETLOCALARRAYADDR
                        OSDebug("  -> Branch: LOCAL INT (default), opcode=" + Str(arrayOpcode))
                     EndIf
                     ; Emit with paramOffset (VM will calculate actualSlot = localSlotStart + paramOffset)
                     EmitInt( arrayOpcode, localArrayOffset )
                  Else
                     ; Global array - use standard GETARRAYADDR with global slot
                     If arrayType = #C2FLAG_STR
                        arrayOpcode = #ljGETARRAYADDRS
                        OSDebug("  -> Branch: GLOBAL STR, opcode=" + Str(arrayOpcode))
                     ElseIf arrayType = #C2FLAG_FLOAT
                        arrayOpcode = #ljGETARRAYADDRF
                        OSDebug("  -> Branch: GLOBAL FLOAT, opcode=" + Str(arrayOpcode))
                     Else
                        arrayOpcode = #ljGETARRAYADDR
                        OSDebug("  -> Branch: GLOBAL INT (default), opcode=" + Str(arrayOpcode))
                     EndIf
                     EmitInt( arrayOpcode, n )
                  EndIf
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
                  ; V1.029.9: Find correct struct slot by searching for FIRST FIELD
                  ; V1.029.10: Use dot notation (varName.field)
                  gaStructType = gVarMeta(n)\structType
                  gaSlotCount = 0
                  If FindMapElement(mapStructDefs(), gaStructType)
                     gaSlotCount = mapStructDefs()\totalSize
                  EndIf
                  If gaSlotCount > 1
                     gaFieldPrefix = *x\left\value + "."  ; Fields use dot notation
                     gaSearchIdx = 0
                     gaSlotName = ""
                     ; Search forwards to find FIRST field slot
                     For gaSearchIdx = 0 To gnLastVariable - 1
                        gaSlotName = gVarMeta(gaSearchIdx)\name
                        If Left(gaSlotName, Len(gaFieldPrefix)) = gaFieldPrefix
                           n = gaSearchIdx
                           Break
                        EndIf
                     Next
                  EndIf
                  ; Struct pointer - emit GETSTRUCTADDR with base slot
                  EmitInt( #ljGETSTRUCTADDR, n )
               Else
                  ; V1.027.2: Check if this is a local variable (paramOffset >= 0)
                  ; Local variables need GETLOCALADDR which calculates fp + paramOffset at runtime
                  isLocalVar = Bool(gVarMeta(n)\paramOffset >= 0)
                  localOffset = gVarMeta(n)\paramOffset

                  ; V1.031.35: Emit type-specific GETADDR based on gVarMeta flags (not TypeHint which may be incorrect)
                  opcode = 0
                  varFlags = gVarMeta(n)\flags
                  If isLocalVar
                     ; V1.027.2: Use local address opcodes for local variables
                     ; V1.031.35: Use gVarMeta flags for reliable type detection
                     If varFlags & #C2FLAG_STR
                        opcode = #ljGETLOCALADDRS
                     ElseIf varFlags & #C2FLAG_FLOAT
                        opcode = #ljGETLOCALADDRF
                     Else
                        opcode = #ljGETLOCALADDR
                     EndIf
                     ; Emit with paramOffset (VM will calculate actualSlot = localSlotStart + paramOffset)
                     EmitInt( opcode, localOffset )
                  Else
                     ; Global variable - use standard GETADDR with global slot
                     ; V1.031.35: Use gVarMeta flags for reliable type detection
                     If varFlags & #C2FLAG_STR
                        opcode = #ljGETADDRS
                     ElseIf varFlags & #C2FLAG_FLOAT
                        opcode = #ljGETADDRF
                     Else
                        opcode = #ljGETADDR
                     EndIf
                     EmitInt( opcode, n )
                  EndIf
               EndIf
            Else
               SetError( "Address-of operator requires a variable, array element, or function", #C2ERR_EXPECTED_PRIMARY )
            EndIf

         Case #ljPTRFETCH  ; Pointer dereference: *ptr
            ; V1.034.65: Mark the underlying variable as a pointer for arithmetic detection
            ; This allows p + 1 to correctly use PTRADD if p was dereferenced earlier
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               If n >= 0 And n < ArraySize(gVarMeta())
                  gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_POINTER
               EndIf
            EndIf

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
            ; V1.029.5: Adjust paramCount for struct parameters (each struct pushes totalSize slots)
            paramCount = paramCount + gExtraStructSlots
            gExtraStructSlots = 0  ; Reset for next call

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

            ; Check if this is a built-in function
            ; V1.023.29: Also check for type conversion opcodes (str(), strf())
            ; V1.026.0: Check for list/map collection functions
            ; V1.033.53: FIX - User function IDs now start at 1000 (#C2FUNCSTART)
            ; This avoids collision with built-in opcodes (which end at ~493).
            ; The mapBuiltins check is kept as additional safety.
            isListFunc = Bool(funcId >= #ljLIST_ADD And funcId <= #ljLIST_SORT)
            isMapFunc = Bool(funcId >= #ljMAP_PUT And funcId <= #ljMAP_VALUE)
            isBuiltinFunc = #False

            ; Check if funcId is a registered built-in
            ForEach mapBuiltins()
               If mapBuiltins()\opcode = funcId
                  isBuiltinFunc = #True
                  Break
               EndIf
            Next

            If isListFunc Or isMapFunc
               ; V1.026.0: Collection function - first param is collection variable
               ; The first param was already generated and pushed to stack,
               ; but we need it as a slot in \i. The value on stack is the slot index
               ; since FETCH was used for the identifier.
               ; Actually, for collection variables, we need to pass slot directly.
               ; The codegen already generated parameters onto stack.
               ; For simplicity, VM will pop the collection slot from stack.
               EmitInt(funcId)
               llObjects()\j = paramCount
               ; Store value type in \n for functions that need it (GET, SET, SORT)
               If funcId = #ljLIST_GET Or funcId = #ljLIST_SET Or funcId = #ljLIST_SORT
                  ; Will be resolved in postprocessor based on list variable type
                  llObjects()\n = 0
               EndIf
            ElseIf isBuiltinFunc Or funcId = #ljITOS Or funcId = #ljFTOS
               ; Built-in function or type conversion - emit opcode directly
               EmitInt( funcId )
               llObjects()\j = paramCount
            Else
               ; User-defined function - emit CALL with function ID
               ; Store nParams in j and nLocals in n (no packing)
               nLocals = 0 : nLocalArrays = 0

               ; Find nLocals and nLocalArrays for this function
               ForEach mapModules()
                  If mapModules()\function = funcId
                     nLocals = mapModules()\nLocals
                     nLocalArrays = mapModules()\nLocalArrays
                     Break
                  EndIf
               Next

               ; V1.034.65: Check for recursive call (funcId matches current function)
               ; Recursive calls use CALL_REC which always uses frame pool
               If funcId = gCodeGenFunction And gCodeGenFunction > 0
                  ; Recursive call - use specialized opcode with frame pool
                  EmitInt( #ljCALL_REC, funcId )
               Else
                  ; V1.033.12: Use optimized CALL opcodes for 0-2 parameters
                  Select paramCount
                     Case 0
                        EmitInt( #ljCALL0, funcId )
                     Case 1
                        EmitInt( #ljCALL1, funcId )
                     Case 2
                        EmitInt( #ljCALL2, funcId )
                     Default
                        EmitInt( #ljCall, funcId )
                  EndSelect
               EndIf

               ; Store separately: j = nParams, n = nLocals, ndx = nLocalArrays, funcid = function ID
               llObjects()\j = paramCount
               llObjects()\n = nLocals
               llObjects()\ndx = nLocalArrays
               llObjects()\funcid = funcId

               ; V1.031.105: Emit ARRAYINFO opcodes for each local array
               ; This embeds paramOffset and arraySize directly in the code stream
               ; so VM doesn't need to access gVarMeta (compiler-only data)
               If nLocalArrays > 0
                  arrIdx = 0 : arrVarSlot = 0
                  For arrIdx = 0 To nLocalArrays - 1
                     arrVarSlot = gFuncLocalArraySlots(funcId, arrIdx)
                     EmitInt(#ljARRAYINFO, gVarMeta(arrVarSlot)\paramOffset)
                     llObjects()\j = gVarMeta(arrVarSlot)\arraySize
                  Next
               EndIf
            EndIf
            
         Case #ljHalt
            EmitInt( *x\NodeType, 0 )

         ; Type conversion operators (unary - operate on left child)
         Case #ljITOF, #ljFTOI, #ljITOS, #ljFTOS, #ljSTOF, #ljSTOI
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType )

         ; Cast operators (V1.18.63) - smart type conversion based on source and target
         ; V1.036.2: Added #ljCAST_PTR for pointer casting
         Case #ljCAST_INT, #ljCAST_FLOAT, #ljCAST_STRING, #ljCAST_VOID, #ljCAST_PTR
            ; Generate code for the expression to be cast
            CodeGenerator( *x\left )

            ; Determine source type
            sourceType = GetExprResultType(*x\left)

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

               Case #ljCAST_VOID  ; V1.033.11: Discard value
                  ; Expression was already evaluated, just drop the result
                  EmitInt( #ljDROP )

               Case #ljCAST_PTR  ; V1.036.2: Cast to pointer
                  ; Pointers are integers internally, so conversion depends on source type
                  If sourceType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOI )  ; float -> int (pointer)
                  ElseIf sourceType & #C2FLAG_STR
                     EmitInt( #ljSTOI )  ; string -> int (pointer)
                  EndIf
                  ; If already int/pointer, no conversion needed
            EndSelect

         ; V1.022.64: Array resize operation
         Case #ljARRAYRESIZE
            ; Emit ARRAYRESIZE opcode
            ; Node fields: value = array name, paramCount = new size, TypeHint = isLocal
            resizeArrayName = *x\value
            resizeNewSize = *x\paramCount
            resizeIsLocal = *x\TypeHint
            resizeVarSlot = 0
            resizeSlotToEmit = 0

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

         ; V1.026.0: List creation
         ; V1.026.19: Support local list variables via \n = isLocal flag
         Case #ljLIST_NEW
            listNewName = *x\value
            listNewTypeHint = *x\TypeHint
            listNewVarSlot = 0
            listNewIsLocal = 0
            listNewSlotToEmit = 0

            listNewVarSlot = FetchVarOffset(listNewName)

            ; Check if this is a local variable
            If IsLocalVar(listNewVarSlot)
               listNewIsLocal = 1
               listNewSlotToEmit = gVarMeta(listNewVarSlot)\paramOffset
            Else
               listNewSlotToEmit = listNewVarSlot
            EndIf

            ; Convert TypeHint to C2FLAG format
            listNewType = #C2FLAG_INT
            listNewElementSize = 1
            If listNewTypeHint = #ljFLOAT
               listNewType = #C2FLAG_FLOAT
            ElseIf listNewTypeHint = #ljSTRING
               listNewType = #C2FLAG_STR
            ElseIf listNewTypeHint = #ljStructType
               ; V1.029.14: Struct list - set STRUCT flag and element size
               listNewType = #C2FLAG_STRUCT
               listNewElementSize = *x\paramCount  ; Element size stored in AST
            EndIf

            ; Emit LIST_NEW: \i = slot/offset, \j = value type, \n = isLocal, \ndx = element size (for structs)
            EmitInt(#ljLIST_NEW, listNewSlotToEmit)
            llObjects()\j = listNewType
            llObjects()\n = listNewIsLocal
            llObjects()\ndx = listNewElementSize  ; V1.029.14: Element size for struct lists

         ; V1.026.0: Map creation
         ; V1.026.19: Support local map variables via \n = isLocal flag
         Case #ljMAP_NEW
            mapNewName = *x\value
            mapNewTypeHint = *x\TypeHint
            mapNewVarSlot = 0
            mapNewIsLocal = 0
            mapNewSlotToEmit = 0

            mapNewVarSlot = FetchVarOffset(mapNewName)

            ; Check if this is a local variable
            If IsLocalVar(mapNewVarSlot)
               mapNewIsLocal = 1
               mapNewSlotToEmit = gVarMeta(mapNewVarSlot)\paramOffset
            Else
               mapNewSlotToEmit = mapNewVarSlot
            EndIf

            ; Convert TypeHint to C2FLAG format
            mapNewType = #C2FLAG_INT
            mapNewElementSize = 1
            If mapNewTypeHint = #ljFLOAT
               mapNewType = #C2FLAG_FLOAT
            ElseIf mapNewTypeHint = #ljSTRING
               mapNewType = #C2FLAG_STR
            ElseIf mapNewTypeHint = #ljStructType
               ; V1.029.14: Struct map - set STRUCT flag and element size
               mapNewType = #C2FLAG_STRUCT
               mapNewElementSize = *x\paramCount  ; Element size stored in AST
            EndIf

            ; Emit MAP_NEW: \i = slot/offset, \j = value type, \n = isLocal, \ndx = element size (for structs)
            EmitInt(#ljMAP_NEW, mapNewSlotToEmit)
            llObjects()\j = mapNewType
            llObjects()\n = mapNewIsLocal
            llObjects()\ndx = mapNewElementSize  ; V1.029.14: Element size for struct maps

         Case #ljStructInit
            ; V1.029.97: Struct initialization { } - no-op since allocation is done via STRUCT_ALLOC
            ; The { } syntax just indicates "initialize to defaults" which happens at allocation time
            ; Nothing to emit here

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

   ; V1.039.12: Generate ASM listing as string for .od file
   ; V1.039.20: Streamlined to industry-standard format
   Procedure.s         ListCodeToString()
      Protected         i
      Protected         flag
      Protected.s       temp, line, result, typeStr, valStr

      ; V1.039.21: Ensure code element maps are populated for local name display
      PopulateCodeElementMaps()

      ; Header
      result = "; CX Assembly Listing" + #CRLF$
      result + "; Generated by CX Compiler" + #CRLF$
      result + #CRLF$

      ; Data section
      result + ".data" + #CRLF$
      result + "; slot  name                  type" + #CRLF$

      For i = 0 To gnLastVariable - 1
         ; Determine type
         If gVarMeta(i)\flags & #C2FLAG_INT
            typeStr = "int"
         ElseIf gVarMeta(i)\flags & #C2FLAG_FLOAT
            typeStr = "float"
         ElseIf gVarMeta(i)\flags & #C2FLAG_STR
            typeStr = "string"
         Else
            typeStr = "var"
         EndIf

         ; Add const modifier
         If gVarMeta(i)\flags & #C2FLAG_CONST
            typeStr + " const"
         EndIf

         ; Format: slot  name  type
         valStr = gVarMeta(i)\name
         If gVarMeta(i)\flags & #C2FLAG_STR And Len(valStr) > 20
            valStr = Left(valStr, 17) + "..."
         EndIf
         result + RSet(Str(i), 4) + "  " + LSet(valStr, 22) + typeStr + #CRLF$
      Next

      ; Code section
      result + #CRLF$
      result + ".text" + #CRLF$

      ; V1.039.49: Use arCode() instead of llObjects() for reliable ASM output
      ; The llObjects() linked list may have inconsistent state after vm_ListToArray
      ; arCode() is guaranteed to contain the final compiled bytecode
      ; Use For loop and break on EOF to avoid ASMLine macro variable redeclaration
      For i = 0 To ArraySize(arCode())
         ASMLine( arCode( i ), 1 )
         result + line + #CRLF$
         If arCode( i )\code = #LJEOF
            Break
         EndIf
      Next

      result + #CRLF$
      result + "; End of listing" + #CRLF$

      ProcedureReturn result
   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 249
; FirstLine = 245
; Folding = ---------
; Markers = 1894,1972
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 2
; EnableBuildCount = 0
; EnableExeConstant
