; ============================================================================
; CX Serialization Module v02
; ============================================================================
; Handles saving/loading compiled .ocx (Object CX) files
; Binary format with JSON header for metadata
;
; File Format:
;   [8 bytes]  Magic: "CXOBJ001"
;   [4 bytes]  JSON header length
;   [N bytes]  JSON header (UTF-8)
;   [4 bytes]  Bytecode instruction count
;   [N bytes]  Binary bytecode array
;   [4 bytes]  Global template count
;   [N bytes]  Binary global templates
;   [4 bytes]  Function template count
;   [N bytes]  Binary function templates
;
; V1.039.0 - Initial implementation
; V1.039.37 - Refactored to use PureBasic JSON library
; ============================================================================

; ============================================================================
; Write Procedures - Save compiled object to .od file
; ============================================================================

Procedure.i SerializePragmasToJSON(parentJson.i)
   ; Add pragmas object to parent JSON
   ; Returns the pragmas JSON value
   Protected pragmasObj.i = SetJSONObject(AddJSONMember(JSONValue(parentJson), "pragmas"))

   ForEach mapPragmas()
      SetJSONString(AddJSONMember(pragmasObj, MapKey(mapPragmas())), mapPragmas())
   Next

   ProcedureReturn pragmasObj
EndProcedure

Procedure.i SerializeStructDefsToJSON(parentJson.i)
   ; Add structDefs object to parent JSON
   Protected structDefsObj.i = SetJSONObject(AddJSONMember(JSONValue(parentJson), "structDefs"))
   Protected structObj.i, fieldsArray.i, fieldObj.i

   ForEach mapStructDefs()
      structObj = SetJSONObject(AddJSONMember(structDefsObj, MapKey(mapStructDefs())))
      SetJSONInteger(AddJSONMember(structObj, "totalSize"), mapStructDefs()\totalSize)

      fieldsArray = SetJSONArray(AddJSONMember(structObj, "fields"))

      ForEach mapStructDefs()\fields()
         fieldObj = SetJSONObject(AddJSONElement(fieldsArray))
         SetJSONString(AddJSONMember(fieldObj, "name"), mapStructDefs()\fields()\name)
         SetJSONInteger(AddJSONMember(fieldObj, "fieldType"), mapStructDefs()\fields()\fieldType)
         SetJSONInteger(AddJSONMember(fieldObj, "offset"), mapStructDefs()\fields()\offset)
         SetJSONInteger(AddJSONMember(fieldObj, "isArray"), mapStructDefs()\fields()\isArray)
         SetJSONInteger(AddJSONMember(fieldObj, "arraySize"), mapStructDefs()\fields()\arraySize)
         SetJSONString(AddJSONMember(fieldObj, "structType"), mapStructDefs()\fields()\structType)
      Next
   Next

   ProcedureReturn structDefsObj
EndProcedure

Procedure.i SerializeModulesToJSON(parentJson.i)
   ; Add modules object to parent JSON
   Protected modulesObj.i = SetJSONObject(AddJSONMember(JSONValue(parentJson), "modules"))
   Protected modObj.i

   ForEach mapModules()
      modObj = SetJSONObject(AddJSONMember(modulesObj, MapKey(mapModules())))
      SetJSONInteger(AddJSONMember(modObj, "function"), mapModules()\function)
      SetJSONInteger(AddJSONMember(modObj, "nParams"), mapModules()\nParams)
      SetJSONInteger(AddJSONMember(modObj, "nLocals"), mapModules()\nLocals)
      SetJSONInteger(AddJSONMember(modObj, "Index"), mapModules()\Index)
      SetJSONInteger(AddJSONMember(modObj, "returnType"), mapModules()\returnType)
      SetJSONInteger(AddJSONMember(modObj, "nRequiredParams"), mapModules()\nRequiredParams)
   Next

   ProcedureReturn modulesObj
EndProcedure

Procedure.s BuildHeaderJSON(sourceFile.s, includeSource.b, includeASM.b = #False)
   ; Build complete JSON header using PureBasic JSON library
   Protected json.i, rootObj.i, statsObj.i
   Protected timestamp.s = FormatDate("%yyyy-%mm-%dd %hh:%ii:%ss", Date())
   Protected result.s
   Protected asmListing.s

   json = CreateJSON(#PB_Any)
   If Not json
      ProcedureReturn "{}"
   EndIf

   rootObj = SetJSONObject(JSONValue(json))

   ; Basic info
   SetJSONString(AddJSONMember(rootObj, "version"), #OD_VERSION$)
   SetJSONString(AddJSONMember(rootObj, "source"), sourceFile)
   SetJSONString(AddJSONMember(rootObj, "compiled"), timestamp)

   ; Pragmas, struct defs, modules
   SerializePragmasToJSON(json)
   SerializeStructDefsToJSON(json)
   SerializeModulesToJSON(json)

   ; Stats object
   statsObj = SetJSONObject(AddJSONMember(rootObj, "stats"))
   SetJSONInteger(AddJSONMember(statsObj, "codeSize"), ArraySize(arCode()))
   SetJSONInteger(AddJSONMember(statsObj, "globalCount"), ArraySize(gGlobalTemplate()))
   SetJSONInteger(AddJSONMember(statsObj, "funcCount"), gnFuncTemplateCount)

   ; Optional: include full source code
   If includeSource And gszOriginalSource > ""
      SetJSONString(AddJSONMember(rootObj, "sourceCode"), gszOriginalSource)
   EndIf

   ; V1.039.12: Optional: include ASM listing (verbose mode)
   If includeASM
      asmListing = ListCodeToString()
      SetJSONString(AddJSONMember(rootObj, "asmListing"), asmListing)
   EndIf

   result = ComposeJSON(json)
   FreeJSON(json)

   ProcedureReturn result
EndProcedure

Procedure WriteVarTemplateBinary(file.i, *tpl.stVarTemplate)
   ; Write a single stVarTemplate in binary format
   ; Format: flags(4) + i(8) + f(8) + ptrtype(2) + arraySize(4) + paramOffset(4) + elementSize(4) + ssLen(4) + ss(N)
   Protected ssBytes.i

   WriteLong(file, *tpl\flags)
   WriteQuad(file, *tpl\i)
   WriteDouble(file, *tpl\f)
   WriteWord(file, *tpl\ptrtype)
   WriteLong(file, *tpl\arraySize)
   WriteLong(file, *tpl\paramOffset)
   WriteLong(file, *tpl\elementSize)

   ; Write string with length prefix
   ssBytes = StringByteLength(*tpl\ss, #PB_UTF8)
   WriteLong(file, ssBytes)
   If ssBytes > 0
      WriteString(file, *tpl\ss, #PB_UTF8)
   EndIf
EndProcedure

Procedure WriteCodeInsBinary(file.i, *ins.stCodeIns)
   ; Write a single stCodeIns in binary format (18 bytes fixed)
   WriteLong(file, *ins\code)
   WriteLong(file, *ins\i)
   WriteLong(file, *ins\j)
   WriteWord(file, *ins\n)
   WriteWord(file, *ins\ndx)
   WriteLong(file, *ins\funcid)
   WriteWord(file, *ins\anchor)
EndProcedure

Procedure WriteFuncTemplateBinary(file.i, *ftpl.stFuncTemplate)
   ; Write a single stFuncTemplate in binary format
   Protected i.i
   Protected templateCount.i

   WriteLong(file, *ftpl\funcId)
   WriteLong(file, *ftpl\localCount)
   WriteLong(file, *ftpl\funcSlot)
   WriteLong(file, *ftpl\nParams)

   ; Write template array size and contents
   templateCount = ArraySize(*ftpl\template())
   WriteLong(file, templateCount)

   For i = 0 To templateCount
      WriteVarTemplateBinary(file, *ftpl\template(i))
   Next
EndProcedure

Procedure.i SaveCompiledObject(filename.s, sourceFile.s, includeSource.b = #True, includeASM.b = #False)
   ; Save compiled bytecode and templates to .od file
   ; Returns 0 on success, -1 on error
   ; V1.039.12: Added includeASM parameter for verbose mode
   Protected file.i
   Protected headerJson.s
   Protected headerBytes.i
   Protected i.i
   Protected codeCount.i
   Protected globalCount.i

   file = CreateFile(#PB_Any, filename)
   If Not file
      Debug "SaveCompiledObject: Failed to create file: " + filename
      ProcedureReturn -1
   EndIf

   ; Write magic number (8 bytes ASCII)
   WriteString(file, #OD_MAGIC$, #PB_Ascii)

   ; Build and write JSON header
   headerJson = BuildHeaderJSON(sourceFile, includeSource, includeASM)
   headerBytes = StringByteLength(headerJson, #PB_UTF8)
   WriteLong(file, headerBytes)
   WriteString(file, headerJson, #PB_UTF8)

   ; Write bytecode array
   codeCount = ArraySize(arCode())
   WriteLong(file, codeCount)
   For i = 0 To codeCount
      WriteCodeInsBinary(file, arCode(i))
   Next

   ; Write global templates
   globalCount = ArraySize(gGlobalTemplate())
   WriteLong(file, globalCount)
   For i = 0 To globalCount
      WriteVarTemplateBinary(file, gGlobalTemplate(i))
   Next

   ; Write function templates
   WriteLong(file, gnFuncTemplateCount)
   For i = 0 To gnFuncTemplateCount - 1
      WriteFuncTemplateBinary(file, gFuncTemplates(i))
   Next

   CloseFile(file)
   ProcedureReturn 0
EndProcedure

; ============================================================================
; Read Procedures - Load compiled object from .od file
; ============================================================================

Procedure ParsePragmasFromJSON(pragmasValue.i)
   ; Parse pragmas JSON object and populate mapPragmas
   Protected key.s
   Protected memberValue.i

   ClearMap(mapPragmas())

   If JSONType(pragmasValue) = #PB_JSON_Object
      If ExamineJSONMembers(pragmasValue)
         While NextJSONMember(pragmasValue)
            key = JSONMemberKey(pragmasValue)
            memberValue = JSONMemberValue(pragmasValue)
            If JSONType(memberValue) = #PB_JSON_String
               mapPragmas(key) = GetJSONString(memberValue)
            EndIf
         Wend
      EndIf
   EndIf
EndProcedure

Procedure ReadVarTemplateBinary(file.i, *tpl.stVarTemplate)
   ; Read a single stVarTemplate from binary
   Protected ssBytes.i

   *tpl\flags = ReadLong(file)
   *tpl\i = ReadQuad(file)
   *tpl\f = ReadDouble(file)
   *tpl\ptrtype = ReadWord(file)
   *tpl\arraySize = ReadLong(file)
   *tpl\paramOffset = ReadLong(file)
   *tpl\elementSize = ReadLong(file)

   ; Read string with length prefix
   ssBytes = ReadLong(file)
   If ssBytes > 0
      *tpl\ss = ReadString(file, #PB_UTF8, ssBytes)
   Else
      *tpl\ss = ""
   EndIf

   ; Pointer cannot be serialized - clear it
   *tpl\ptr = 0
EndProcedure

Procedure ReadCodeInsBinary(file.i, *ins.stCodeIns)
   ; Read a single stCodeIns from binary (18 bytes fixed)
   *ins\code = ReadLong(file)
   *ins\i = ReadLong(file)
   *ins\j = ReadLong(file)
   *ins\n = ReadWord(file)
   *ins\ndx = ReadWord(file)
   *ins\funcid = ReadLong(file)
   *ins\anchor = ReadWord(file)
EndProcedure

Procedure ReadFuncTemplateBinary(file.i, *ftpl.stFuncTemplate)
   ; Read a single stFuncTemplate from binary
   Protected i.i
   Protected templateCount.i

   *ftpl\funcId = ReadLong(file)
   *ftpl\localCount = ReadLong(file)
   *ftpl\funcSlot = ReadLong(file)
   *ftpl\nParams = ReadLong(file)

   ; Read template array
   templateCount = ReadLong(file)
   ReDim *ftpl\template(templateCount)

   For i = 0 To templateCount
      ReadVarTemplateBinary(file, *ftpl\template(i))
   Next
EndProcedure

Procedure.i LoadCompiledObject(filename.s)
   ; Load compiled bytecode and templates from .od file
   ; Returns 0 on success, -1 on error
   Protected file.i
   Protected magic.s
   Protected headerLen.i
   Protected headerJson.s
   Protected i.i
   Protected *headerMem
   Protected json.i
   Protected rootValue.i
   Protected pragmasValue.i
   Protected codeCount.i
   Protected globalCount.i

   file = ReadFile(#PB_Any, filename)
   If Not file
      Debug "LoadCompiledObject: Failed to open file: " + filename
      ProcedureReturn -1
   EndIf

   ; Verify magic number
   magic = ReadString(file, #PB_Ascii, 8)
   If magic <> #OD_MAGIC$
      Debug "LoadCompiledObject: Invalid magic number: " + magic
      CloseFile(file)
      ProcedureReturn -1
   EndIf

   ; Read JSON header (headerLen is in bytes, not characters)
   headerLen = ReadLong(file)
   ; Read raw bytes and convert to UTF-8 string
   *headerMem = AllocateMemory(headerLen + 1)
   ReadData(file, *headerMem, headerLen)
   PokeB(*headerMem + headerLen, 0)  ; Null terminate
   headerJson = PeekS(*headerMem, -1, #PB_UTF8)
   FreeMemory(*headerMem)

   ; Parse header JSON using PureBasic JSON library
   json = ParseJSON(#PB_Any, headerJson)
   If json
      rootValue = JSONValue(json)
      If JSONType(rootValue) = #PB_JSON_Object
         ; Extract pragmas
         pragmasValue = GetJSONMember(rootValue, "pragmas")
         If pragmasValue
            ParsePragmasFromJSON(pragmasValue)
         EndIf
      EndIf
      FreeJSON(json)
   EndIf

   ; Read bytecode array
   codeCount = ReadLong(file)
   ReDim arCode(codeCount)
   For i = 0 To codeCount
      ReadCodeInsBinary(file, arCode(i))
   Next

   ; Read global templates
   globalCount = ReadLong(file)
   ReDim gGlobalTemplate(globalCount)
   For i = 0 To globalCount
      ReadVarTemplateBinary(file, gGlobalTemplate(i))
   Next
   gnLastVariable = globalCount + 1  ; gnLastVariable is count, not last index

   ; Read function templates
   gnFuncTemplateCount = ReadLong(file)
   ReDim gFuncTemplates(gnFuncTemplateCount)
   For i = 0 To gnFuncTemplateCount - 1
      ReadFuncTemplateBinary(file, gFuncTemplates(i))
   Next

   CloseFile(file)

   ; Set loaded flag for VM (gObjectLoaded defined in c2-inc-v20.pbi)
   gObjectLoaded = #True

   ProcedureReturn 0
EndProcedure
