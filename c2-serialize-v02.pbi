; ============================================================================
; D+AI Serialization Module v01
; ============================================================================
; Handles saving/loading compiled .od (Object D) files
; Binary format with JSON header for metadata
;
; File Format:
;   [8 bytes]  Magic: "DAIOBJ01"
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
; ============================================================================

; ============================================================================
; Write Procedures - Save compiled object to .od file
; ============================================================================

Procedure.s SerializePragmasToJSON()
   ; Convert mapPragmas to JSON object string
   Protected result.s = "{"
   Protected first.b = #True

   ForEach mapPragmas()
      If Not first : result + "," : EndIf
      first = #False
      result + ~"\"" + MapKey(mapPragmas()) + ~"\":\"" + mapPragmas() + ~"\""
   Next

   result + "}"
   ProcedureReturn result
EndProcedure

Procedure.s SerializeStructDefsToJSON()
   ; Convert mapStructDefs to JSON object string
   Protected result.s = "{"
   Protected first.b = #True
   Protected fieldFirst.b

   ForEach mapStructDefs()
      If Not first : result + "," : EndIf
      first = #False

      result + ~"\"" + MapKey(mapStructDefs()) + ~"\":{"
      result + ~"\"totalSize\":" + Str(mapStructDefs()\totalSize)
      result + ~",\"fields\":["

      fieldFirst = #True
      ForEach mapStructDefs()\fields()
         If Not fieldFirst : result + "," : EndIf
         fieldFirst = #False
         result + "{"
         result + ~"\"name\":\"" + mapStructDefs()\fields()\name + ~"\""
         result + ~",\"fieldType\":" + Str(mapStructDefs()\fields()\fieldType)
         result + ~",\"offset\":" + Str(mapStructDefs()\fields()\offset)
         result + ~",\"isArray\":" + Str(mapStructDefs()\fields()\isArray)
         result + ~",\"arraySize\":" + Str(mapStructDefs()\fields()\arraySize)
         result + ~",\"structType\":\"" + mapStructDefs()\fields()\structType + ~"\""
         result + "}"
      Next
      result + "]}"
   Next

   result + "}"
   ProcedureReturn result
EndProcedure

Procedure.s SerializeModulesToJSON()
   ; Convert mapModules to JSON for function metadata
   Protected result.s = "{"
   Protected first.b = #True

   ForEach mapModules()
      If Not first : result + "," : EndIf
      first = #False

      result + ~"\"" + MapKey(mapModules()) + ~"\":{"
      result + ~"\"function\":" + Str(mapModules()\function)
      result + ~",\"nParams\":" + Str(mapModules()\nParams)
      result + ~",\"nLocals\":" + Str(mapModules()\nLocals)
      result + ~",\"Index\":" + Str(mapModules()\Index)
      result + ~",\"returnType\":" + Str(mapModules()\returnType)
      result + ~",\"nRequiredParams\":" + Str(mapModules()\nRequiredParams)
      result + "}"
   Next

   result + "}"
   ProcedureReturn result
EndProcedure

Procedure.s EscapeJSONString(text.s)
   ; Escape special characters for JSON string
   Protected result.s = text
   result = ReplaceString(result, "\", "\\")
   result = ReplaceString(result, ~"\"", ~"\\\"")
   result = ReplaceString(result, Chr(10), "\n")
   result = ReplaceString(result, Chr(13), "\r")
   result = ReplaceString(result, Chr(9), "\t")
   ProcedureReturn result
EndProcedure

Procedure.s BuildHeaderJSON(sourceFile.s, includeSource.b, includeASM.b = #False)
   ; Build complete JSON header
   Protected json.s
   Protected timestamp.s = FormatDate("%yyyy-%mm-%dd %hh:%ii:%ss", Date())

   json = "{"
   json + ~"\"version\":\"" + #OD_VERSION$ + ~"\""
   json + ~",\"source\":\"" + EscapeJSONString(sourceFile) + ~"\""
   json + ~",\"compiled\":\"" + timestamp + ~"\""
   json + ~",\"pragmas\":" + SerializePragmasToJSON()
   json + ~",\"structDefs\":" + SerializeStructDefsToJSON()
   json + ~",\"modules\":" + SerializeModulesToJSON()
   json + ~",\"stats\":{"
   json + ~"\"codeSize\":" + Str(ArraySize(arCode()))
   json + ~",\"globalCount\":" + Str(ArraySize(gGlobalTemplate()))
   json + ~",\"funcCount\":" + Str(gnFuncTemplateCount)
   json + "}"

   ; Optional: include full source code
   If includeSource And gszOriginalSource > ""
      json + ~",\"sourceCode\":\"" + EscapeJSONString(gszOriginalSource) + ~"\""
   EndIf

   ; V1.039.12: Optional: include ASM listing (verbose mode)
   If includeASM
      Protected asmListing.s = ListCodeToString()
      json + ~",\"asmListing\":\"" + EscapeJSONString(asmListing) + ~"\""
   EndIf

   json + "}"
   ProcedureReturn json
EndProcedure

Procedure WriteVarTemplateBinary(file.i, *tpl.stVarTemplate)
   ; Write a single stVarTemplate in binary format
   ; Format: flags(4) + i(8) + f(8) + ptrtype(2) + arraySize(4) + paramOffset(4) + elementSize(4) + ssLen(4) + ss(N)

   WriteLong(file, *tpl\flags)
   WriteQuad(file, *tpl\i)
   WriteDouble(file, *tpl\f)
   WriteWord(file, *tpl\ptrtype)
   WriteLong(file, *tpl\arraySize)
   WriteLong(file, *tpl\paramOffset)
   WriteLong(file, *tpl\elementSize)

   ; Write string with length prefix
   Protected ssBytes.i = StringByteLength(*tpl\ss, #PB_UTF8)
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

   WriteLong(file, *ftpl\funcId)
   WriteLong(file, *ftpl\localCount)
   WriteLong(file, *ftpl\funcSlot)
   WriteLong(file, *ftpl\nParams)

   ; Write template array size and contents
   Protected templateCount.i = ArraySize(*ftpl\template())
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
   Protected codeCount.i = ArraySize(arCode())
   WriteLong(file, codeCount)
   For i = 0 To codeCount
      WriteCodeInsBinary(file, arCode(i))
   Next

   ; Write global templates
   Protected globalCount.i = ArraySize(gGlobalTemplate())
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

Procedure.s UnescapeJSONString(text.s)
   ; Unescape JSON string (basic implementation)
   Protected result.s = text
   result = ReplaceString(result, "\n", Chr(10))
   result = ReplaceString(result, "\r", Chr(13))
   result = ReplaceString(result, "\t", Chr(9))
   result = ReplaceString(result, ~"\\\"", ~"\"")
   result = ReplaceString(result, "\\", "\")
   ProcedureReturn result
EndProcedure

Procedure ReadVarTemplateBinary(file.i, *tpl.stVarTemplate)
   ; Read a single stVarTemplate from binary

   *tpl\flags = ReadLong(file)
   *tpl\i = ReadQuad(file)
   *tpl\f = ReadDouble(file)
   *tpl\ptrtype = ReadWord(file)
   *tpl\arraySize = ReadLong(file)
   *tpl\paramOffset = ReadLong(file)
   *tpl\elementSize = ReadLong(file)

   ; Read string with length prefix
   Protected ssBytes.i = ReadLong(file)
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

   *ftpl\funcId = ReadLong(file)
   *ftpl\localCount = ReadLong(file)
   *ftpl\funcSlot = ReadLong(file)
   *ftpl\nParams = ReadLong(file)

   ; Read template array
   Protected templateCount.i = ReadLong(file)
   ReDim *ftpl\template(templateCount)

   For i = 0 To templateCount
      ReadVarTemplateBinary(file, *ftpl\template(i))
   Next
EndProcedure

Procedure.s ExtractJSONValue(json.s, key.s)
   ; Simple JSON value extraction (for string values)
   Protected keyPos.i = FindString(json, ~"\"" + key + ~"\":")
   If keyPos = 0 : ProcedureReturn "" : EndIf

   Protected valueStart.i = keyPos + Len(key) + 3
   Protected char.s = Mid(json, valueStart, 1)

   If char = ~"\""
      ; String value - find closing quote (handle escapes)
      Protected valueEnd.i = valueStart + 1
      Protected escaped.b = #False
      While valueEnd <= Len(json)
         char = Mid(json, valueEnd, 1)
         If escaped
            escaped = #False
         ElseIf char = "\"
            escaped = #True
         ElseIf char = ~"\""
            Break
         EndIf
         valueEnd + 1
      Wend
      ProcedureReturn UnescapeJSONString(Mid(json, valueStart + 1, valueEnd - valueStart - 1))
   Else
      ; Numeric or other value - find next comma or brace
      Protected valueEnd2.i = valueStart
      While valueEnd2 <= Len(json)
         char = Mid(json, valueEnd2, 1)
         If char = "," Or char = "}" Or char = "]"
            Break
         EndIf
         valueEnd2 + 1
      Wend
      ProcedureReturn Trim(Mid(json, valueStart, valueEnd2 - valueStart))
   EndIf
EndProcedure

Procedure.i ExtractJSONInt(json.s, key.s)
   Protected value.s = ExtractJSONValue(json, key)
   ProcedureReturn Val(value)
EndProcedure

Procedure ParsePragmasFromJSON(json.s)
   ; Parse pragmas section and populate mapPragmas
   ; Simple parser for {"key":"value",...} format
   Protected pos.i = 1
   Protected key.s, value.s
   Protected inKey.b, inValue.b
   Protected char.s

   ClearMap(mapPragmas())

   While pos <= Len(json)
      char = Mid(json, pos, 1)

      If char = ~"\""
         ; Start of key or value
         Protected endQuote.i = FindString(json, ~"\"", pos + 1)
         If endQuote > 0
            Protected str.s = Mid(json, pos + 1, endQuote - pos - 1)
            If key = ""
               key = str
            Else
               value = UnescapeJSONString(str)
               mapPragmas(key) = value
               key = ""
               value = ""
            EndIf
            pos = endQuote
         EndIf
      EndIf
      pos + 1
   Wend
EndProcedure

Procedure.i LoadCompiledObject(filename.s)
   ; Load compiled bytecode and templates from .od file
   ; Returns 0 on success, -1 on error

   Protected file.i
   Protected magic.s
   Protected headerLen.i
   Protected headerJson.s
   Protected i.i

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
   Protected *headerMem = AllocateMemory(headerLen + 1)
   ReadData(file, *headerMem, headerLen)
   PokeB(*headerMem + headerLen, 0)  ; Null terminate
   headerJson = PeekS(*headerMem, -1, #PB_UTF8)
   FreeMemory(*headerMem)

   ; Parse header for configuration
   ; Extract pragmas section
   Protected pragmasStart.i = FindString(headerJson, ~"\"pragmas\":{")
   If pragmasStart > 0
      Protected pragmasEnd.i = FindString(headerJson, "}", pragmasStart + 11)
      If pragmasEnd > 0
         ParsePragmasFromJSON(Mid(headerJson, pragmasStart + 10, pragmasEnd - pragmasStart - 9))
      EndIf
   EndIf

   ; Read bytecode array
   Protected codeCount.i = ReadLong(file)
   ReDim arCode(codeCount)
   For i = 0 To codeCount
      ReadCodeInsBinary(file, arCode(i))
   Next

   ; Read global templates
   Protected globalCount.i = ReadLong(file)
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
