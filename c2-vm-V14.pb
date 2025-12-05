
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

;- =====================================
;- Virtual Machine
;- =====================================
DeclareModule C2VM
   EnableExplicit
   UseModule C2Common

   Declare           RunVM()
   Declare           vmClearRun()

   ; Batch mode output (always declared, only used when #C2_BATCH_MODE is enabled)
   Global            gBatchOutput.s
   Global            gModulename.s
EndDeclareModule

Module C2VM
   EnableExplicit
   UseModule C2Lang

   ;- GUI Enumerations
   Enumeration
      #MainWindow
      #BtnExit
      #BtnLoad
      #BtnRun
      #edConsole
      #lstExamples    ; V1.027.4: Examples listbox for quick testing
   EndEnumeration
   
   Structure stProfiler
      count.i
      time.i
   EndStructure

   Structure stVTSimple
      ss.s
      i.i
      f.d
      *ptr
      ptrtype.w         ; Pointer type tag (0=not pointer, 1=int, 2=float, 3=string, 4-6=array, 7=function)
   EndStructure

   Structure stVTArray
      size.l            ; Number of elements in array
      desc.s            ; Array description (for debugging)
      Array ar.stVTSimple(0)  ; Dynamic array of elements
   EndStructure

   Structure stVT
      ss.s
      i.i
      f.d
      *ptr
      ptrtype.w         ; Pointer type tag (0=not pointer, 1=int, 2=float, 3=string, 4-6=array, 7=function)
      dta.stVTArray
   EndStructure

   Structure stStack
      sp.l                     ; Saved stack pointer
      pc.l                     ; Saved program counter
      localSlotStart.l         ; First gVar[] slot allocated for this call's locals
      localSlotCount.l         ; Number of local variable slots allocated (params + locals)
      ; REMOVED: LocalInt/Float/String/Arrays - now using unified gVar[] array
      ; V1.18.0: All variables (global and local) use the same gVar[] array
   EndStructure

   ;- Globals
   Global               sp                   = 0           ; stack pointer
   Global               pc                   = 0           ; Process stack
   Global               cy                   = 0
   Global               cs                   = 0
   Global               gFunctionDepth       = 0       ; Fast function depth counter (avoids ListSize)
   Global               gStackDepth          = -1      ; Current stack frame index (-1 = no frames)
   Global               gCurrentMaxLocal     = 0       ; Highest gVar[] slot currently used by locals (V1.18.0)   
   Global               gDecs                = 3
   Global               gExitApplication     = 0   
   Global               gFunctionDepth       = 2048       ; Fast function depth counter (avoids ListSize)
   Global               gMaxStackSpace       = 2048
   Global               gMaxStackDepth       = 1024
   Global               gWidth.i             = 960,   ; V1.027.4: Wider for examples listbox
                        gHeight.i            = 340,
                        gWindowX             = #PB_Ignore, 
                        gWindowY             = #PB_Ignore
   
   Global               gShowModulename      = #False
   Global               gFastPrint.w         = #False
   Global               gListASM.w           = #False
   Global               gPasteToClipboard    = #False
   Global               gShowversion         = #False
   Global               gRunThreaded.w       = #True
   Global               gConsole.w           = #True
   
   Global               gFloatTolerance.d    = 0.00001
   Global               cline.s              = ""
   Global               gszAppname.s         = "Unnamed"
   Global               gSelectedExample.i   = 0       ; V1.027.6: Track selected example in listbox

   Global Dim           *ptrJumpTable(1)
   Global Dim           gVar.stVT(#C2MAXCONSTANTS)
   Global Dim           gStack.stStack(gMaxStackDepth - 1)
   
   ;- Macros
   Macro             vm_ConsoleOrGUI( mytext )
      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
         PrintN( mytext )
      CompilerElse
         AddGadgetItem( #edConsole, -1, mytext )
      CompilerEndIf
   EndMacro
   Macro             vm_Comparators( operator )
      sp - 1
      CompilerIf #DEBUG
         Protected cmpLeft.i = gVar(sp-1)\i
         Protected cmpRight.i = gVar(sp)\i
         Protected cmpResult.i
      CompilerEndIf
      If gVar(sp-1)\i operator gVar(sp)\i
         gVar(sp-1)\i = 1
         CompilerIf #DEBUG
            cmpResult = 1
         CompilerEndIf
      Else
         gVar(sp-1)\i = 0
         CompilerIf #DEBUG
            cmpResult = 0
         CompilerEndIf
      EndIf
      CompilerIf #DEBUG
         ; V1.020.090: Only debug when comparing with negative values
         ; V1.020.093: Disabled to reduce output noise
         ; V1.022.93: Enable for high recursion depth debugging (quicksort)
         If gStackDepth >= 6
            Debug "C2CMP: pc=" + Str(pc) + " left=" + Str(cmpLeft) + " right=" + Str(cmpRight) + " result=" + Str(cmpResult) + " sp=" + Str(sp) + " depth=" + Str(gStackDepth)
         EndIf
      CompilerEndIf
      pc + 1
   EndMacro
   Macro             vm_BitOperation( operand )
      sp - 1
      gVar(sp-1)\i = gVar(sp-1)\i operand gVar(sp)\i
      pc + 1
   EndMacro
   Macro             vm_FloatComparators( operator )
      sp - 1
      If gVar(sp - 1)\f operator gVar( sp )\f
         gVar(sp - 1)\i = 1
      Else
         gVar(sp - 1)\i = 0
      EndIf
      pc + 1
   EndMacro
   Macro             vm_FloatOperation( operand )
      sp - 1
      gVar(sp - 1)\f = gVar(sp - 1)\f operand gVar( sp )\f
      pc + 1
   EndMacro
   Macro             vm_DualAssign( pragma, param1, param2, psep )
      temp     = mapPragmas(pragma)
      
      If temp > ""
         param1   = Val( StringField(temp, 1, psep) )
         param2   = Val( StringField(temp, 2, psep) )
      EndIf
   EndMacro
   Macro             vm_SetGlobalFromPragma(reverse, pragma, gvariable)
      temp  = mapPragmas(pragma)       ; do I need an LCase here?
      
      CompilerIf reverse
         If temp = "off" Or temp = "0" Or temp = "false"
            gvariable = #False
         Else
            gvariable = #True
         EndIf
      CompilerElse
         If temp = "on" Or temp = "1" Or temp = "true"
            gvariable = #True
         Else
            gvariable = #False
         EndIf
      CompilerEndIf
   EndMacro
  
   XIncludeFile      "c2-vm-commands-v13.pb"
   ; Note: c2-pointers-v04.pbi and c2-collections-v01.pbi included via c2-vm-commands-v13.pb

   ;- Console GUI
   Procedure         MainWindow(name.s)
      Protected       dir, filename.s

      If OpenWindow( #MainWindow, #PB_Ignore, #PB_Ignore, 960, 680, name, #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_TitleBar )
         ButtonGadget( #BtnExit,    5,    3,  90,  29, "EXIT" )
         ButtonGadget( #BtnLoad,  100,    3,  90,  29, "Load/Compile" )
         ButtonGadget( #BtnRun,   200,    3,  90,  29, "Run" )

         ; V1.027.4: Examples listbox on the left side
         ListViewGadget( #lstExamples, 0, 35, 200, 640 )

         ; Populate listbox with *.lj files from Examples folder
         dir = ExamineDirectory(#PB_Any, ".\Examples\", "*.lj")
         If dir
            While NextDirectoryEntry(dir)
               If DirectoryEntryType(dir) = #PB_DirectoryEntry_File
                  filename = DirectoryEntryName(dir)
                  AddGadgetItem(#lstExamples, -1, filename)
               EndIf
            Wend
            FinishDirectory(dir)
         EndIf

         ; V1.027.6: Restore selection after repopulating listbox
         If gSelectedExample >= 0 And gSelectedExample < CountGadgetItems(#lstExamples)
            SetGadgetState(#lstExamples, gSelectedExample)
         EndIf

         ; V1.027.7: Set focus to listbox for keyboard navigation (arrows, pgup/pgdn, home/end)
         SetActiveGadget(#lstExamples)

         EditorGadget( #edConsole, 205,  35, 755, 640, #PB_Editor_ReadOnly )
         AddGadgetItem( #edConsole, -1, "" )
         ProcedureReturn 1
      EndIf

      ProcedureReturn 0
   EndProcedure

   Procedure         ResizeMain()
      Protected      x, y

      x = WindowWidth( #MainWindow )
      y = WindowHeight( #MainWindow )
      If x < 500 : x = 500 : EndIf
      If y < 230 : y = 230 : EndIf

      ResizeWindow( #MainWindow, #PB_Ignore, #PB_Ignore, x, y )
      ; V1.027.4: Resize listbox and console with proper layout
      ResizeGadget( #lstExamples, #PB_Ignore, #PB_Ignore, #PB_Ignore, y - 40 )
      ResizeGadget( #edConsole, #PB_Ignore, #PB_Ignore, x - 205, y - 40 )

   EndProcedure

   ;- VM components
   Procedure            vmInitVM()
      ReDim *ptrJumpTable( gnTotalTokens )

      *ptrJumpTable( #ljUNUSED )          = @C2HALT()  ; Treat UNUSED as HALT
      *ptrJumpTable( #ljFetch )           = @C2FetchPush()
      *ptrJumpTable( #ljPush )            = @C2FetchPush()
      *ptrJumpTable( #ljStore )           = @C2Store()
      *ptrJumpTable( #ljMov )             = @C2Mov()
      *ptrJumpTable( #ljMOVS )            = @C2MOVS()
      *ptrJumpTable( #ljMOVF )            = @C2MOVF()
      *ptrJumpTable( #ljFETCHS )          = @C2FETCHS()
      *ptrJumpTable( #ljFETCHF )          = @C2FETCHF()
      *ptrJumpTable( #ljSTORES )          = @C2STORES()
      *ptrJumpTable( #ljSTOREF )          = @C2STOREF()
      ; V1.026.0: Push slot index for collection functions
      *ptrJumpTable( #ljPUSH_SLOT )       = @C2PUSH_SLOT()
      ; Local variable opcodes (frame-relative)
      *ptrJumpTable( #ljLMOV )            = @C2LMOV()
      *ptrJumpTable( #ljLMOVS )           = @C2LMOVS()
      *ptrJumpTable( #ljLMOVF )           = @C2LMOVF()
      ; V1.022.31: Local-to-Global MOV opcodes
      *ptrJumpTable( #ljLGMOV )           = @C2LGMOV()
      *ptrJumpTable( #ljLGMOVS )          = @C2LGMOVS()
      *ptrJumpTable( #ljLGMOVF )          = @C2LGMOVF()
      ; V1.022.31: Local-to-Local MOV opcodes
      *ptrJumpTable( #ljLLMOV )           = @C2LLMOV()
      *ptrJumpTable( #ljLLMOVS )          = @C2LLMOVS()
      *ptrJumpTable( #ljLLMOVF )          = @C2LLMOVF()
      *ptrJumpTable( #ljLFETCH )          = @C2LFETCH()
      *ptrJumpTable( #ljLFETCHS )         = @C2LFETCHS()
      *ptrJumpTable( #ljLFETCHF )         = @C2LFETCHF()
      *ptrJumpTable( #ljLSTORE )          = @C2LSTORE()
      *ptrJumpTable( #ljLSTORES )         = @C2LSTORES()
      *ptrJumpTable( #ljLSTOREF )         = @C2LSTOREF()
      ; In-place increment/decrement opcodes (efficient, no multi-operation sequences)
      *ptrJumpTable( #ljINC_VAR )         = @C2INC_VAR()
      *ptrJumpTable( #ljDEC_VAR )         = @C2DEC_VAR()
      *ptrJumpTable( #ljINC_VAR_PRE )     = @C2INC_VAR_PRE()
      *ptrJumpTable( #ljDEC_VAR_PRE )     = @C2DEC_VAR_PRE()
      *ptrJumpTable( #ljINC_VAR_POST )    = @C2INC_VAR_POST()
      *ptrJumpTable( #ljDEC_VAR_POST )    = @C2DEC_VAR_POST()
      *ptrJumpTable( #ljLINC_VAR )        = @C2LINC_VAR()
      *ptrJumpTable( #ljLDEC_VAR )        = @C2LDEC_VAR()
      *ptrJumpTable( #ljLINC_VAR_PRE )    = @C2LINC_VAR_PRE()
      *ptrJumpTable( #ljLDEC_VAR_PRE )    = @C2LDEC_VAR_PRE()
      *ptrJumpTable( #ljLINC_VAR_POST )   = @C2LINC_VAR_POST()
      *ptrJumpTable( #ljLDEC_VAR_POST )   = @C2LDEC_VAR_POST()
      ; Pointer increment/decrement opcodes (V1.20.36)
      *ptrJumpTable( #ljPTRINC )          = @C2PTRINC()
      *ptrJumpTable( #ljPTRDEC )          = @C2PTRDEC()
      *ptrJumpTable( #ljPTRINC_PRE )      = @C2PTRINC_PRE()
      *ptrJumpTable( #ljPTRDEC_PRE )      = @C2PTRDEC_PRE()
      *ptrJumpTable( #ljPTRINC_POST )     = @C2PTRINC_POST()
      *ptrJumpTable( #ljPTRDEC_POST )     = @C2PTRDEC_POST()
      ; In-place compound assignment opcodes
      *ptrJumpTable( #ljADD_ASSIGN_VAR )  = @C2ADD_ASSIGN_VAR()
      *ptrJumpTable( #ljSUB_ASSIGN_VAR )  = @C2SUB_ASSIGN_VAR()
      *ptrJumpTable( #ljMUL_ASSIGN_VAR )  = @C2MUL_ASSIGN_VAR()
      *ptrJumpTable( #ljDIV_ASSIGN_VAR )  = @C2DIV_ASSIGN_VAR()
      *ptrJumpTable( #ljMOD_ASSIGN_VAR )  = @C2MOD_ASSIGN_VAR()
      *ptrJumpTable( #ljFLOATADD_ASSIGN_VAR ) = @C2FLOATADD_ASSIGN_VAR()
      *ptrJumpTable( #ljFLOATSUB_ASSIGN_VAR ) = @C2FLOATSUB_ASSIGN_VAR()
      *ptrJumpTable( #ljFLOATMUL_ASSIGN_VAR ) = @C2FLOATMUL_ASSIGN_VAR()
      *ptrJumpTable( #ljFLOATDIV_ASSIGN_VAR ) = @C2FLOATDIV_ASSIGN_VAR()
      *ptrJumpTable( #ljPTRADD_ASSIGN )       = @C2PTRADD_ASSIGN()
      *ptrJumpTable( #ljPTRSUB_ASSIGN )       = @C2PTRSUB_ASSIGN()
      ; Type conversion opcodes
      *ptrJumpTable( #ljITOF )            = @C2ITOF()
      ; Note: FTOI is set dynamically based on #pragma ftoi (see below)
      *ptrJumpTable( #ljJMP )             = @C2JMP()
      *ptrJumpTable( #ljJZ )              = @C2JZ()
      *ptrJumpTable( #ljTENIF )           = @C2TENIF()
      *ptrJumpTable( #ljTENELSE )         = @C2TENELSE()
      ; V1.024.0: New opcodes for switch statement
      *ptrJumpTable( #ljDUP )             = @C2DUP()
      *ptrJumpTable( #ljDUP_I )           = @C2DUP_I()
      *ptrJumpTable( #ljDUP_F )           = @C2DUP_F()
      *ptrJumpTable( #ljDUP_S )           = @C2DUP_S()
      *ptrJumpTable( #ljJNZ )             = @C2JNZ()
      *ptrJumpTable( #ljDROP )            = @C2DROP()
      *ptrJumpTable( #ljADD )             = @C2ADD()
      *ptrJumpTable( #ljSUBTRACT )        = @C2SUBTRACT()
      *ptrJumpTable( #ljGREATER )         = @C2GREATER()
      *ptrJumpTable( #ljLESS )            = @C2LESS()
      *ptrJumpTable( #ljLESSEQUAL )       = @C2LESSEQUAL()
      *ptrJumpTable( #ljGreaterEqual )    = @C2GREATEREQUAL()
      *ptrJumpTable( #ljNotEqual )        = @C2NOTEQUAL()
      *ptrJumpTable( #ljEQUAL )           = @C2EQUAL()
      ; V1.023.30: String comparison opcodes
      *ptrJumpTable( #ljSTREQ )           = @C2STREQ()
      *ptrJumpTable( #ljSTRNE )           = @C2STRNE()
      *ptrJumpTable( #ljMULTIPLY )        = @C2MULTIPLY()
      *ptrJumpTable( #ljAND )             = @C2AND()
      *ptrJumpTable( #ljOr )              = @C2OR()
      *ptrJumpTable( #ljXOR )             = @C2XOR()
      *ptrJumpTable( #ljNOT )             = @C2NOT()
      *ptrJumpTable( #ljNEGATE )          = @C2NEGATE()
      *ptrJumpTable( #ljDIVIDE )          = @C2DIVIDE()
      *ptrJumpTable( #ljMOD )             = @C2MOD()
      
      *ptrJumpTable( #ljPRTS )            = @C2PRTS()
      *ptrJumpTable( #ljPRTC )            = @C2PRTC()
      *ptrJumpTable( #ljPRTI )            = @C2PRTI()
      *ptrJumpTable( #ljPRTF )            = @C2PRTF()
      *ptrJumpTable( #ljPRTPTR )          = @C2PRTPTR()

      *ptrJumpTable( #ljFLOATNEG )        = @C2FLOATNEGATE()
      *ptrJumpTable( #ljFLOATDIV )        = @C2FLOATDIVIDE()
      *ptrJumpTable( #ljFLOATADD )        = @C2FLOATADD()
      *ptrJumpTable( #ljFLOATSUB )        = @C2FLOATSUB()
      *ptrJumpTable( #ljFLOATMUL )        = @C2FLOATMUL()
      
      *ptrJumpTable( #ljFLOATEQ )         = @C2FLOATEQUAL()
      *ptrJumpTable( #ljFLOATNE )         = @C2FLOATNOTEQUAL()
      *ptrJumpTable( #ljFLOATLE )         = @C2FLOATLESSEQUAL()
      *ptrJumpTable( #ljFLOATGE )         = @C2FLOATGREATEREQUAL()
      *ptrJumpTable( #ljFLOATGR )         = @C2FLOATGREATER()
      *ptrJumpTable( #ljFLOATLESS )       = @C2FLOATLESS()
      *ptrJumpTable( #ljSTRADD )          = @C2ADDSTR()
      *ptrJumpTable( #ljFTOS )            = @C2FTOS()
      *ptrJumpTable( #ljITOS )            = @C2ITOS()
      *ptrJumpTable( #ljITOF )            = @C2ITOF()
      *ptrJumpTable( #ljSTOF )            = @C2STOF()
      *ptrJumpTable( #ljSTOI )            = @C2STOI()
      ; FTOI is set dynamically in RunVM() based on #pragma ftoi

      *ptrJumpTable( #ljCall )            = @C2CALL()
      *ptrJumpTable( #ljreturn )          = @C2Return()
      *ptrJumpTable( #ljreturnF )         = @C2ReturnF()
      *ptrJumpTable( #ljreturnS )         = @C2ReturnS()
      *ptrJumpTable( #ljPOP )             = @C2POP()
      *ptrJumpTable( #ljPOPS )            = @C2POPS()
      *ptrJumpTable( #ljPOPF )            = @C2POPF()
      *ptrJumpTable( #ljPUSHS )           = @C2PUSHS()
      *ptrJumpTable( #ljPUSHF )           = @C2PUSHF()

      ; Built-in functions - direct opcode dispatch
      *ptrJumpTable( #ljBUILTIN_RANDOM )  = @C2BUILTIN_RANDOM()
      *ptrJumpTable( #ljBUILTIN_ABS )     = @C2BUILTIN_ABS()
      *ptrJumpTable( #ljBUILTIN_MIN )     = @C2BUILTIN_MIN()
      *ptrJumpTable( #ljBUILTIN_MAX )     = @C2BUILTIN_MAX()
      *ptrJumpTable( #ljBUILTIN_ASSERT_EQUAL )  = @C2BUILTIN_ASSERT_EQUAL()
      *ptrJumpTable( #ljBUILTIN_ASSERT_FLOAT )  = @C2BUILTIN_ASSERT_FLOAT()
      *ptrJumpTable( #ljBUILTIN_ASSERT_STRING ) = @C2BUILTIN_ASSERT_STRING()
      *ptrJumpTable( #ljBUILTIN_SQRT )    = @C2BUILTIN_SQRT()
      *ptrJumpTable( #ljBUILTIN_POW )     = @C2BUILTIN_POW()
      *ptrJumpTable( #ljBUILTIN_LEN )     = @C2BUILTIN_LEN()
      *ptrJumpTable( #ljBUILTIN_STRCMP )  = @C2BUILTIN_STRCMP()
      *ptrJumpTable( #ljBUILTIN_GETC )    = @C2BUILTIN_GETC()

      ; Array operations
      *ptrJumpTable( #ljARRAYINDEX )      = @C2ARRAYINDEX()
      *ptrJumpTable( #ljARRAYFETCH )      = @C2ARRAYFETCH()
      *ptrJumpTable( #ljARRAYSTORE )      = @C2ARRAYSTORE()

      ; Specialized array fetch operations (no runtime branching)
      *ptrJumpTable( #ljARRAYFETCH_INT_GLOBAL_OPT )     = @C2ARRAYFETCH_INT_GLOBAL_OPT()
      *ptrJumpTable( #ljARRAYFETCH_INT_GLOBAL_STACK )   = @C2ARRAYFETCH_INT_GLOBAL_STACK()
      *ptrJumpTable( #ljARRAYFETCH_INT_LOCAL_OPT )      = @C2ARRAYFETCH_INT_LOCAL_OPT()
      *ptrJumpTable( #ljARRAYFETCH_INT_LOCAL_STACK )    = @C2ARRAYFETCH_INT_LOCAL_STACK()
      *ptrJumpTable( #ljARRAYFETCH_FLOAT_GLOBAL_OPT )   = @C2ARRAYFETCH_FLOAT_GLOBAL_OPT()
      *ptrJumpTable( #ljARRAYFETCH_FLOAT_GLOBAL_STACK ) = @C2ARRAYFETCH_FLOAT_GLOBAL_STACK()
      *ptrJumpTable( #ljARRAYFETCH_FLOAT_LOCAL_OPT )    = @C2ARRAYFETCH_FLOAT_LOCAL_OPT()
      *ptrJumpTable( #ljARRAYFETCH_FLOAT_LOCAL_STACK )  = @C2ARRAYFETCH_FLOAT_LOCAL_STACK()
      *ptrJumpTable( #ljARRAYFETCH_STR_GLOBAL_OPT )     = @C2ARRAYFETCH_STR_GLOBAL_OPT()
      *ptrJumpTable( #ljARRAYFETCH_STR_GLOBAL_STACK )   = @C2ARRAYFETCH_STR_GLOBAL_STACK()
      *ptrJumpTable( #ljARRAYFETCH_STR_LOCAL_OPT )      = @C2ARRAYFETCH_STR_LOCAL_OPT()
      *ptrJumpTable( #ljARRAYFETCH_STR_LOCAL_STACK )    = @C2ARRAYFETCH_STR_LOCAL_STACK()

      ; V1.022.113: LOCAL_LOPT fetch operations (local array, local index variable)
      *ptrJumpTable( #ljARRAYFETCH_INT_LOCAL_LOPT )      = @C2ARRAYFETCH_INT_LOCAL_LOPT()
      *ptrJumpTable( #ljARRAYFETCH_FLOAT_LOCAL_LOPT )    = @C2ARRAYFETCH_FLOAT_LOCAL_LOPT()
      *ptrJumpTable( #ljARRAYFETCH_STR_LOCAL_LOPT )      = @C2ARRAYFETCH_STR_LOCAL_LOPT()
      ; V1.022.113: LOCAL_LOPT store operations (local array, local index variable)
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_LOPT_LOPT )     = @C2ARRAYSTORE_INT_LOCAL_LOPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_LOPT_OPT )      = @C2ARRAYSTORE_INT_LOCAL_LOPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_LOPT_STACK )    = @C2ARRAYSTORE_INT_LOCAL_LOPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT )   = @C2ARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_LOPT_OPT )    = @C2ARRAYSTORE_FLOAT_LOCAL_LOPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_LOPT_STACK )  = @C2ARRAYSTORE_FLOAT_LOCAL_LOPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_LOPT_LOPT )     = @C2ARRAYSTORE_STR_LOCAL_LOPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_LOPT_OPT )      = @C2ARRAYSTORE_STR_LOCAL_LOPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_LOPT_STACK )    = @C2ARRAYSTORE_STR_LOCAL_LOPT_STACK()

      ; Specialized array store operations (no runtime branching)
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_OPT_OPT )       = @C2ARRAYSTORE_INT_GLOBAL_OPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_OPT_STACK )     = @C2ARRAYSTORE_INT_GLOBAL_OPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_STACK_OPT )     = @C2ARRAYSTORE_INT_GLOBAL_STACK_OPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_STACK_STACK )   = @C2ARRAYSTORE_INT_GLOBAL_STACK_STACK()
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_OPT_OPT )        = @C2ARRAYSTORE_INT_LOCAL_OPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_OPT_STACK )      = @C2ARRAYSTORE_INT_LOCAL_OPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_STACK_OPT )      = @C2ARRAYSTORE_INT_LOCAL_STACK_OPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_STACK_STACK )    = @C2ARRAYSTORE_INT_LOCAL_STACK_STACK()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_OPT_OPT )     = @C2ARRAYSTORE_FLOAT_GLOBAL_OPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_OPT_STACK )   = @C2ARRAYSTORE_FLOAT_GLOBAL_OPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_STACK_OPT )   = @C2ARRAYSTORE_FLOAT_GLOBAL_STACK_OPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK ) = @C2ARRAYSTORE_FLOAT_GLOBAL_STACK_STACK()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_OPT_OPT )      = @C2ARRAYSTORE_FLOAT_LOCAL_OPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_OPT_STACK )    = @C2ARRAYSTORE_FLOAT_LOCAL_OPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_STACK_OPT )    = @C2ARRAYSTORE_FLOAT_LOCAL_STACK_OPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_STACK_STACK )  = @C2ARRAYSTORE_FLOAT_LOCAL_STACK_STACK()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_OPT_OPT )       = @C2ARRAYSTORE_STR_GLOBAL_OPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_OPT_STACK )     = @C2ARRAYSTORE_STR_GLOBAL_OPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_STACK_OPT )     = @C2ARRAYSTORE_STR_GLOBAL_STACK_OPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_STACK_STACK )   = @C2ARRAYSTORE_STR_GLOBAL_STACK_STACK()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_OPT_OPT )        = @C2ARRAYSTORE_STR_LOCAL_OPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_OPT_STACK )      = @C2ARRAYSTORE_STR_LOCAL_OPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_STACK_OPT )      = @C2ARRAYSTORE_STR_LOCAL_STACK_OPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_STACK_STACK )    = @C2ARRAYSTORE_STR_LOCAL_STACK_STACK()

      ; V1.022.86: Local-index array operations (for recursion-safe temp variables)
      *ptrJumpTable( #ljARRAYFETCH_INT_GLOBAL_LOPT )          = @C2ARRAYFETCH_INT_GLOBAL_LOPT()
      *ptrJumpTable( #ljARRAYFETCH_FLOAT_GLOBAL_LOPT )        = @C2ARRAYFETCH_FLOAT_GLOBAL_LOPT()
      *ptrJumpTable( #ljARRAYFETCH_STR_GLOBAL_LOPT )          = @C2ARRAYFETCH_STR_GLOBAL_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_LOPT_LOPT )     = @C2ARRAYSTORE_INT_GLOBAL_LOPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_LOPT_OPT )      = @C2ARRAYSTORE_INT_GLOBAL_LOPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_LOPT_STACK )    = @C2ARRAYSTORE_INT_GLOBAL_LOPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT )   = @C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT )    = @C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK )  = @C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_LOPT_LOPT )     = @C2ARRAYSTORE_STR_GLOBAL_LOPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_LOPT_OPT )      = @C2ARRAYSTORE_STR_GLOBAL_LOPT_OPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_LOPT_STACK )    = @C2ARRAYSTORE_STR_GLOBAL_LOPT_STACK()

      ; V1.022.114: Global-index, Local-value array operations (expression result in local temp)
      *ptrJumpTable( #ljARRAYSTORE_INT_GLOBAL_OPT_LOPT )      = @C2ARRAYSTORE_INT_GLOBAL_OPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT )    = @C2ARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_GLOBAL_OPT_LOPT )      = @C2ARRAYSTORE_STR_GLOBAL_OPT_LOPT()

      ; V1.022.115: Local array, Global-index, Local-value operations (expression result in local temp)
      *ptrJumpTable( #ljARRAYSTORE_INT_LOCAL_OPT_LOPT )       = @C2ARRAYSTORE_INT_LOCAL_OPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_FLOAT_LOCAL_OPT_LOPT )     = @C2ARRAYSTORE_FLOAT_LOCAL_OPT_LOPT()
      *ptrJumpTable( #ljARRAYSTORE_STR_LOCAL_OPT_LOPT )       = @C2ARRAYSTORE_STR_LOCAL_OPT_LOPT()

      ; Struct array field operations (V1.022.0: arrays inside structures)
      *ptrJumpTable( #ljSTRUCTARRAY_FETCH_INT )   = @C2STRUCTARRAY_FETCH_INT()
      *ptrJumpTable( #ljSTRUCTARRAY_FETCH_FLOAT ) = @C2STRUCTARRAY_FETCH_FLOAT()
      *ptrJumpTable( #ljSTRUCTARRAY_FETCH_STR )   = @C2STRUCTARRAY_FETCH_STR()
      *ptrJumpTable( #ljSTRUCTARRAY_STORE_INT )   = @C2STRUCTARRAY_STORE_INT()
      *ptrJumpTable( #ljSTRUCTARRAY_STORE_FLOAT ) = @C2STRUCTARRAY_STORE_FLOAT()
      *ptrJumpTable( #ljSTRUCTARRAY_STORE_STR )   = @C2STRUCTARRAY_STORE_STR()

      ; V1.022.44: Array of structs operations (array arr.StructType[n])
      *ptrJumpTable( #ljARRAYOFSTRUCT_FETCH_INT )   = @C2ARRAYOFSTRUCT_FETCH_INT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_FETCH_FLOAT ) = @C2ARRAYOFSTRUCT_FETCH_FLOAT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_FETCH_STR )   = @C2ARRAYOFSTRUCT_FETCH_STR()
      *ptrJumpTable( #ljARRAYOFSTRUCT_STORE_INT )   = @C2ARRAYOFSTRUCT_STORE_INT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_STORE_FLOAT ) = @C2ARRAYOFSTRUCT_STORE_FLOAT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_STORE_STR )   = @C2ARRAYOFSTRUCT_STORE_STR()

      ; V1.022.118: ARRAYOFSTRUCT LOPT variants (index from local slot)
      *ptrJumpTable( #ljARRAYOFSTRUCT_FETCH_INT_LOPT )   = @C2ARRAYOFSTRUCT_FETCH_INT_LOPT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_FETCH_FLOAT_LOPT ) = @C2ARRAYOFSTRUCT_FETCH_FLOAT_LOPT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_FETCH_STR_LOPT )   = @C2ARRAYOFSTRUCT_FETCH_STR_LOPT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_STORE_INT_LOPT )   = @C2ARRAYOFSTRUCT_STORE_INT_LOPT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_STORE_FLOAT_LOPT ) = @C2ARRAYOFSTRUCT_STORE_FLOAT_LOPT()
      *ptrJumpTable( #ljARRAYOFSTRUCT_STORE_STR_LOPT )   = @C2ARRAYOFSTRUCT_STORE_STR_LOPT()

      ; V1.022.54: Struct pointer operations (ptr = &struct, ptr\field)
      *ptrJumpTable( #ljGETSTRUCTADDR )         = @C2GETSTRUCTADDR()
      *ptrJumpTable( #ljPTRSTRUCTFETCH_INT )    = @C2PTRSTRUCTFETCH_INT()
      *ptrJumpTable( #ljPTRSTRUCTFETCH_FLOAT )  = @C2PTRSTRUCTFETCH_FLOAT()
      *ptrJumpTable( #ljPTRSTRUCTFETCH_STR )    = @C2PTRSTRUCTFETCH_STR()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_INT )    = @C2PTRSTRUCTSTORE_INT()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_FLOAT )  = @C2PTRSTRUCTSTORE_FLOAT()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_STR )    = @C2PTRSTRUCTSTORE_STR()

      ; V1.022.117: PTRSTRUCTSTORE LOPT variants (value from local slot)
      *ptrJumpTable( #ljPTRSTRUCTSTORE_INT_LOPT )   = @C2PTRSTRUCTSTORE_INT_LOPT()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_FLOAT_LOPT ) = @C2PTRSTRUCTSTORE_FLOAT_LOPT()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_STR_LOPT )   = @C2PTRSTRUCTSTORE_STR_LOPT()

      ; V1.022.119: PTRSTRUCTFETCH LPTR variants (pointer from local slot)
      *ptrJumpTable( #ljPTRSTRUCTFETCH_INT_LPTR )   = @C2PTRSTRUCTFETCH_INT_LPTR()
      *ptrJumpTable( #ljPTRSTRUCTFETCH_FLOAT_LPTR ) = @C2PTRSTRUCTFETCH_FLOAT_LPTR()
      *ptrJumpTable( #ljPTRSTRUCTFETCH_STR_LPTR )   = @C2PTRSTRUCTFETCH_STR_LPTR()

      ; V1.022.119: PTRSTRUCTSTORE LPTR variants (pointer from local slot)
      *ptrJumpTable( #ljPTRSTRUCTSTORE_INT_LPTR )   = @C2PTRSTRUCTSTORE_INT_LPTR()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_FLOAT_LPTR ) = @C2PTRSTRUCTSTORE_FLOAT_LPTR()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_STR_LPTR )   = @C2PTRSTRUCTSTORE_STR_LPTR()

      ; V1.022.119: PTRSTRUCTSTORE LPTR_LOPT variants (both pointer and value from local)
      *ptrJumpTable( #ljPTRSTRUCTSTORE_INT_LPTR_LOPT )   = @C2PTRSTRUCTSTORE_INT_LPTR_LOPT()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_FLOAT_LPTR_LOPT ) = @C2PTRSTRUCTSTORE_FLOAT_LPTR_LOPT()
      *ptrJumpTable( #ljPTRSTRUCTSTORE_STR_LPTR_LOPT )   = @C2PTRSTRUCTSTORE_STR_LPTR_LOPT()

      ; V1.022.64: Array resize operation
      *ptrJumpTable( #ljARRAYRESIZE )           = @C2ARRAYRESIZE()

      ; V1.022.65: Struct copy operation
      *ptrJumpTable( #ljSTRUCTCOPY )            = @C2STRUCTCOPY()

      ; V1.026.0: List operations (NEW uses \i for slot assignment)
      *ptrJumpTable( #ljLIST_NEW )              = @C2LIST_NEW()
      ; V1.026.8: Non-value operations use _T versions (pool slot from stack via FETCH/LFETCH)
      *ptrJumpTable( #ljLIST_ADD )              = @C2LIST_ADD()     ; Generic - shouldn't reach VM (postprocessor converts)
      *ptrJumpTable( #ljLIST_INSERT )           = @C2LIST_INSERT()  ; Generic - shouldn't reach VM
      *ptrJumpTable( #ljLIST_DELETE )           = @C2LIST_DELETE_T()
      *ptrJumpTable( #ljLIST_CLEAR )            = @C2LIST_CLEAR_T()
      *ptrJumpTable( #ljLIST_SIZE )             = @C2LIST_SIZE_T()
      *ptrJumpTable( #ljLIST_FIRST )            = @C2LIST_FIRST_T()
      *ptrJumpTable( #ljLIST_LAST )             = @C2LIST_LAST_T()
      *ptrJumpTable( #ljLIST_NEXT )             = @C2LIST_NEXT_T()
      *ptrJumpTable( #ljLIST_PREV )             = @C2LIST_PREV_T()
      *ptrJumpTable( #ljLIST_SELECT )           = @C2LIST_SELECT_T()
      *ptrJumpTable( #ljLIST_INDEX )            = @C2LIST_INDEX_T()
      *ptrJumpTable( #ljLIST_GET )              = @C2LIST_GET()     ; Generic - shouldn't reach VM
      *ptrJumpTable( #ljLIST_SET )              = @C2LIST_SET()     ; Generic - shouldn't reach VM
      *ptrJumpTable( #ljLIST_RESET )            = @C2LIST_RESET_T()
      *ptrJumpTable( #ljLIST_SORT )             = @C2LIST_SORT_T()

      ; V1.026.8: Typed list value operations
      *ptrJumpTable( #ljLIST_ADD_INT )          = @C2LIST_ADD_INT()
      *ptrJumpTable( #ljLIST_ADD_FLOAT )        = @C2LIST_ADD_FLOAT()
      *ptrJumpTable( #ljLIST_ADD_STR )          = @C2LIST_ADD_STR()
      *ptrJumpTable( #ljLIST_INSERT_INT )       = @C2LIST_INSERT_INT()
      *ptrJumpTable( #ljLIST_INSERT_FLOAT )     = @C2LIST_INSERT_FLOAT()
      *ptrJumpTable( #ljLIST_INSERT_STR )       = @C2LIST_INSERT_STR()
      *ptrJumpTable( #ljLIST_GET_INT )          = @C2LIST_GET_INT()
      *ptrJumpTable( #ljLIST_GET_FLOAT )        = @C2LIST_GET_FLOAT()
      *ptrJumpTable( #ljLIST_GET_STR )          = @C2LIST_GET_STR()
      *ptrJumpTable( #ljLIST_SET_INT )          = @C2LIST_SET_INT()
      *ptrJumpTable( #ljLIST_SET_FLOAT )        = @C2LIST_SET_FLOAT()
      *ptrJumpTable( #ljLIST_SET_STR )          = @C2LIST_SET_STR()

      ; V1.026.0: Map operations (NEW uses \i for slot assignment)
      *ptrJumpTable( #ljMAP_NEW )               = @C2MAP_NEW()
      ; V1.026.8: Non-value operations use _T versions (pool slot from stack via FETCH/LFETCH)
      *ptrJumpTable( #ljMAP_PUT )               = @C2MAP_PUT()      ; Generic - shouldn't reach VM (postprocessor converts)
      *ptrJumpTable( #ljMAP_GET )               = @C2MAP_GET()      ; Generic - shouldn't reach VM
      *ptrJumpTable( #ljMAP_DELETE )            = @C2MAP_DELETE_T()
      *ptrJumpTable( #ljMAP_CLEAR )             = @C2MAP_CLEAR_T()
      *ptrJumpTable( #ljMAP_SIZE )              = @C2MAP_SIZE_T()
      *ptrJumpTable( #ljMAP_CONTAINS )          = @C2MAP_CONTAINS_T()
      *ptrJumpTable( #ljMAP_RESET )             = @C2MAP_RESET_T()
      *ptrJumpTable( #ljMAP_NEXT )              = @C2MAP_NEXT_T()
      *ptrJumpTable( #ljMAP_KEY )               = @C2MAP_KEY_T()
      *ptrJumpTable( #ljMAP_VALUE )             = @C2MAP_VALUE()    ; Generic - shouldn't reach VM

      ; V1.026.8: Typed map value operations
      *ptrJumpTable( #ljMAP_PUT_INT )           = @C2MAP_PUT_INT()
      *ptrJumpTable( #ljMAP_PUT_FLOAT )         = @C2MAP_PUT_FLOAT()
      *ptrJumpTable( #ljMAP_PUT_STR )           = @C2MAP_PUT_STR()
      *ptrJumpTable( #ljMAP_GET_INT )           = @C2MAP_GET_INT()
      *ptrJumpTable( #ljMAP_GET_FLOAT )         = @C2MAP_GET_FLOAT()
      *ptrJumpTable( #ljMAP_GET_STR )           = @C2MAP_GET_STR()
      *ptrJumpTable( #ljMAP_VALUE_INT )         = @C2MAP_VALUE_INT()
      *ptrJumpTable( #ljMAP_VALUE_FLOAT )       = @C2MAP_VALUE_FLOAT()
      *ptrJumpTable( #ljMAP_VALUE_STR )         = @C2MAP_VALUE_STR()

      ; Pointer operations
      *ptrJumpTable( #ljGETADDR )         = @C2GETADDR()
      *ptrJumpTable( #ljGETADDRF )        = @C2GETADDRF()
      *ptrJumpTable( #ljGETADDRS )        = @C2GETADDRS()
      ; V1.027.2: Local variable address operations
      *ptrJumpTable( #ljGETLOCALADDR )    = @C2GETLOCALADDR()
      *ptrJumpTable( #ljGETLOCALADDRF )   = @C2GETLOCALADDRF()
      *ptrJumpTable( #ljGETLOCALADDRS )   = @C2GETLOCALADDRS()
      *ptrJumpTable( #ljPTRFETCH )        = @C2PTRFETCH()
      *ptrJumpTable( #ljPTRFETCH_INT )    = @C2PTRFETCH_INT()
      *ptrJumpTable( #ljPTRFETCH_FLOAT )  = @C2PTRFETCH_FLOAT()
      *ptrJumpTable( #ljPTRFETCH_STR )    = @C2PTRFETCH_STR()
      *ptrJumpTable( #ljPTRSTORE )        = @C2PTRSTORE()
      *ptrJumpTable( #ljPTRSTORE_INT )    = @C2PTRSTORE_INT()
      *ptrJumpTable( #ljPTRSTORE_FLOAT )  = @C2PTRSTORE_FLOAT()
      *ptrJumpTable( #ljPTRSTORE_STR )    = @C2PTRSTORE_STR()
      *ptrJumpTable( #ljPTRADD )          = @C2PTRADD()
      *ptrJumpTable( #ljPTRSUB )          = @C2PTRSUB()
      *ptrJumpTable( #ljGETFUNCADDR )     = @C2GETFUNCADDR()
      *ptrJumpTable( #ljCALLFUNCPTR )     = @C2CALLFUNCPTR()
      
      *ptrJumpTable(#ljPMOV) = @C2PMOV()
      *ptrJumpTable(#ljPFETCH) = @C2PFETCH()
      *ptrJumpTable(#ljPSTORE) = @C2PSTORE()
      *ptrJumpTable(#ljPPOP) = @C2PPOP()
      *ptrJumpTable(#ljPLFETCH) = @C2PLFETCH()
      *ptrJumpTable(#ljPLSTORE) = @C2PLSTORE()
      *ptrJumpTable(#ljPLMOV) = @C2PLMOV()

      ; Array pointer opcodes
      *ptrJumpTable( #ljGETARRAYADDR )    = @C2GETARRAYADDR()
      *ptrJumpTable( #ljGETARRAYADDRF )   = @C2GETARRAYADDRF()
      *ptrJumpTable( #ljGETARRAYADDRS )   = @C2GETARRAYADDRS()
      ; V1.027.2: Local array pointer opcodes
      *ptrJumpTable( #ljGETLOCALARRAYADDR )  = @C2GETLOCALARRAYADDR()
      *ptrJumpTable( #ljGETLOCALARRAYADDRF ) = @C2GETLOCALARRAYADDRF()
      *ptrJumpTable( #ljGETLOCALARRAYADDRS ) = @C2GETLOCALARRAYADDRS()

      ; V1.027.0: Type-specialized pointer opcodes (no runtime type dispatch)
      ; Typed print pointer opcodes
      *ptrJumpTable( #ljPRTPTR_INT )          = @C2PRTPTR_INT()
      *ptrJumpTable( #ljPRTPTR_FLOAT )        = @C2PRTPTR_FLOAT()
      *ptrJumpTable( #ljPRTPTR_STR )          = @C2PRTPTR_STR()
      *ptrJumpTable( #ljPRTPTR_ARRAY_INT )    = @C2PRTPTR_ARRAY_INT()
      *ptrJumpTable( #ljPRTPTR_ARRAY_FLOAT )  = @C2PRTPTR_ARRAY_FLOAT()
      *ptrJumpTable( #ljPRTPTR_ARRAY_STR )    = @C2PRTPTR_ARRAY_STR()
      ; Typed simple variable pointer FETCH
      *ptrJumpTable( #ljPTRFETCH_VAR_INT )    = @C2PTRFETCH_VAR_INT()
      *ptrJumpTable( #ljPTRFETCH_VAR_FLOAT )  = @C2PTRFETCH_VAR_FLOAT()
      *ptrJumpTable( #ljPTRFETCH_VAR_STR )    = @C2PTRFETCH_VAR_STR()
      ; Typed array element pointer FETCH
      *ptrJumpTable( #ljPTRFETCH_ARREL_INT )  = @C2PTRFETCH_ARREL_INT()
      *ptrJumpTable( #ljPTRFETCH_ARREL_FLOAT )= @C2PTRFETCH_ARREL_FLOAT()
      *ptrJumpTable( #ljPTRFETCH_ARREL_STR )  = @C2PTRFETCH_ARREL_STR()
      ; Typed simple variable pointer STORE
      *ptrJumpTable( #ljPTRSTORE_VAR_INT )    = @C2PTRSTORE_VAR_INT()
      *ptrJumpTable( #ljPTRSTORE_VAR_FLOAT )  = @C2PTRSTORE_VAR_FLOAT()
      *ptrJumpTable( #ljPTRSTORE_VAR_STR )    = @C2PTRSTORE_VAR_STR()
      ; Typed array element pointer STORE
      *ptrJumpTable( #ljPTRSTORE_ARREL_INT )  = @C2PTRSTORE_ARREL_INT()
      *ptrJumpTable( #ljPTRSTORE_ARREL_FLOAT )= @C2PTRSTORE_ARREL_FLOAT()
      *ptrJumpTable( #ljPTRSTORE_ARREL_STR )  = @C2PTRSTORE_ARREL_STR()
      ; Typed pointer arithmetic
      *ptrJumpTable( #ljPTRADD_INT )          = @C2PTRADD_INT()
      *ptrJumpTable( #ljPTRADD_FLOAT )        = @C2PTRADD_FLOAT()
      *ptrJumpTable( #ljPTRADD_STRING )       = @C2PTRADD_STRING()
      *ptrJumpTable( #ljPTRADD_ARRAY )        = @C2PTRADD_ARRAY()
      *ptrJumpTable( #ljPTRSUB_INT )          = @C2PTRSUB_INT()
      *ptrJumpTable( #ljPTRSUB_FLOAT )        = @C2PTRSUB_FLOAT()
      *ptrJumpTable( #ljPTRSUB_STRING )       = @C2PTRSUB_STRING()
      *ptrJumpTable( #ljPTRSUB_ARRAY )        = @C2PTRSUB_ARRAY()
      ; Typed pointer increment/decrement
      *ptrJumpTable( #ljPTRINC_INT )          = @C2PTRINC_INT()
      *ptrJumpTable( #ljPTRINC_FLOAT )        = @C2PTRINC_FLOAT()
      *ptrJumpTable( #ljPTRINC_STRING )       = @C2PTRINC_STRING()
      *ptrJumpTable( #ljPTRINC_ARRAY )        = @C2PTRINC_ARRAY()
      *ptrJumpTable( #ljPTRDEC_INT )          = @C2PTRDEC_INT()
      *ptrJumpTable( #ljPTRDEC_FLOAT )        = @C2PTRDEC_FLOAT()
      *ptrJumpTable( #ljPTRDEC_STRING )       = @C2PTRDEC_STRING()
      *ptrJumpTable( #ljPTRDEC_ARRAY )        = @C2PTRDEC_ARRAY()
      ; Typed pointer pre-increment/decrement
      *ptrJumpTable( #ljPTRINC_PRE_INT )      = @C2PTRINC_PRE_INT()
      *ptrJumpTable( #ljPTRINC_PRE_FLOAT )    = @C2PTRINC_PRE_FLOAT()
      *ptrJumpTable( #ljPTRINC_PRE_STRING )   = @C2PTRINC_PRE_STRING()
      *ptrJumpTable( #ljPTRINC_PRE_ARRAY )    = @C2PTRINC_PRE_ARRAY()
      *ptrJumpTable( #ljPTRDEC_PRE_INT )      = @C2PTRDEC_PRE_INT()
      *ptrJumpTable( #ljPTRDEC_PRE_FLOAT )    = @C2PTRDEC_PRE_FLOAT()
      *ptrJumpTable( #ljPTRDEC_PRE_STRING )   = @C2PTRDEC_PRE_STRING()
      *ptrJumpTable( #ljPTRDEC_PRE_ARRAY )    = @C2PTRDEC_PRE_ARRAY()
      ; Typed pointer post-increment/decrement
      *ptrJumpTable( #ljPTRINC_POST_INT )     = @C2PTRINC_POST_INT()
      *ptrJumpTable( #ljPTRINC_POST_FLOAT )   = @C2PTRINC_POST_FLOAT()
      *ptrJumpTable( #ljPTRINC_POST_STRING )  = @C2PTRINC_POST_STRING()
      *ptrJumpTable( #ljPTRINC_POST_ARRAY )   = @C2PTRINC_POST_ARRAY()
      *ptrJumpTable( #ljPTRDEC_POST_INT )     = @C2PTRDEC_POST_INT()
      *ptrJumpTable( #ljPTRDEC_POST_FLOAT )   = @C2PTRDEC_POST_FLOAT()
      *ptrJumpTable( #ljPTRDEC_POST_STRING )  = @C2PTRDEC_POST_STRING()
      *ptrJumpTable( #ljPTRDEC_POST_ARRAY )   = @C2PTRDEC_POST_ARRAY()
      ; Typed pointer compound assignment
      *ptrJumpTable( #ljPTRADD_ASSIGN_INT )   = @C2PTRADD_ASSIGN_INT()
      *ptrJumpTable( #ljPTRADD_ASSIGN_FLOAT ) = @C2PTRADD_ASSIGN_FLOAT()
      *ptrJumpTable( #ljPTRADD_ASSIGN_STRING )= @C2PTRADD_ASSIGN_STRING()
      *ptrJumpTable( #ljPTRADD_ASSIGN_ARRAY ) = @C2PTRADD_ASSIGN_ARRAY()
      *ptrJumpTable( #ljPTRSUB_ASSIGN_INT )   = @C2PTRSUB_ASSIGN_INT()
      *ptrJumpTable( #ljPTRSUB_ASSIGN_FLOAT ) = @C2PTRSUB_ASSIGN_FLOAT()
      *ptrJumpTable( #ljPTRSUB_ASSIGN_STRING )= @C2PTRSUB_ASSIGN_STRING()
      *ptrJumpTable( #ljPTRSUB_ASSIGN_ARRAY ) = @C2PTRSUB_ASSIGN_ARRAY()

      *ptrJumpTable( #ljNOOP )            = @C2NOOP()
      *ptrJumpTable( #ljNOOPIF )          = @C2NOOP()
      *ptrJumpTable( #ljfunction )        = @C2NOOP()  ; Function marker - no-op at runtime
      *ptrJumpTable( #ljHALT )            = @C2HALT()

      ; Initialize pointer function pointers for performance
      InitPointerFunctions()

      ; V1.026.4: Initialize collection pools for lists and maps
      InitListPool()
      InitMapPool()

   EndProcedure

   Procedure            vmTransferMetaToRuntime()
      ; V1.023.0: Transfer compile-time data to runtime using templates
      ; Global variables: use gGlobalTemplate (preloaded values)
      ; Constants: still transfer from gVarMeta
      ; Arrays: still need ReDim for element allocation
      Protected i

      CompilerIf #DEBUG
         Debug "=== vmTransferMetaToRuntime: Transferring " + Str(gnLastVariable) + " variables ==="
         Debug "  gnGlobalVariables=" + Str(gnGlobalVariables) + " gnLastVariable=" + Str(gnLastVariable)
      CompilerEndIf

      ; V1.023.17: Single loop through all slots - check flags to determine source
      ; Slots aren't allocated in order (constants before variables)
      For i = 0 To gnLastVariable - 1
         If gVarMeta(i)\flags & #C2FLAG_CONST
            ; This is a constant - transfer from gVarMeta
            gVar(i)\i = gVarMeta(i)\valueInt
            gVar(i)\f = gVarMeta(i)\valueFloat
            gVar(i)\ss = gVarMeta(i)\valueString

            CompilerIf #DEBUG
               Debug "  Transfer constant [" + Str(i) + "]: i=" + Str(gVarMeta(i)\valueInt) + " f=" + StrD(gVarMeta(i)\valueFloat, 6) + " ss='" + gVarMeta(i)\valueString + "'"
            CompilerEndIf
         Else
            ; This is a variable - use gGlobalTemplate (preloaded values)
            gVar(i)\i = gGlobalTemplate(i)\i
            gVar(i)\f = gGlobalTemplate(i)\f
            gVar(i)\ss = gGlobalTemplate(i)\ss
            gVar(i)\ptr = gGlobalTemplate(i)\ptr
            gVar(i)\ptrtype = gGlobalTemplate(i)\ptrtype

            CompilerIf #DEBUG
               If gGlobalTemplate(i)\i <> 0 Or gGlobalTemplate(i)\f <> 0 Or gGlobalTemplate(i)\ss <> ""
                  Debug "  Preload global [" + Str(i) + "]: i=" + Str(gGlobalTemplate(i)\i) + " f=" + StrD(gGlobalTemplate(i)\f, 6) + " ss='" + gGlobalTemplate(i)\ss + "'"
               EndIf
            CompilerEndIf
         EndIf

         ; Allocate array storage if this is an array variable
         If gVarMeta(i)\flags & #C2FLAG_ARRAY And gVarMeta(i)\arraySize > 0
            ReDim gVar(i)\dta\ar(gVarMeta(i)\arraySize - 1)  ; 0-based indexing
            gVar(i)\dta\size = gVarMeta(i)\arraySize  ; Store size in structure
         EndIf
      Next
   EndProcedure

   Procedure            vmClearRun()
      Protected         i

      ; Clear runtime values but preserve compilation metadata AND constants
      ; IMPORTANT: Don't clear flags or paramOffset - they're set during compilation!
      ; V1.020.062: Only clear runtime globals (0 to gnGlobalVariables-1), NOT compile-time constants
      For i = 0 To gnGlobalVariables - 1
         gVar( i )\f = 0
         gVar( i )\ss = ""
         gVar( i )\i = 0
      Next

      ; Clear the call stack
      gStackDepth = -1
      gFunctionDepth = 0
      gCurrentMaxLocal = gnLastVariable  ; V1.020.065: Reset to start after all compile-time allocations

      ; Stop any running code by resetting pc and putting HALT at start
      pc = 0
      arCode(0)\code = #ljHALT
      arCode(0)\i = 0
      arCode(0)\j = 0

      ; V1.026.4: Reset collection pools between runs
      ResetCollections()

   EndProcedure

   Procedure         vmListCode()
      Protected      i
      Protected      flag
      Protected.s    temp, line
      
      While arCode( i )\code <> #ljEOF
         ASMLine( arCode( i ), 1 )
         vm_ConsoleOrGUI( line )
         i + 1
      Wend
      
      vm_ConsoleOrGUI( "" )
   EndProcedure
   
   Procedure         vmExecute(*p = 0)
      Protected      i, j
      Protected      t, t1
      Protected      flag
      Protected      verFile
      Protected.s    temp, name, line, verString, endline
      Protected      opcode.w        ; Cached opcode (VM optimization)
      Protected      *opcodeHandler  ; Cached handler pointer (VM optimization)
      Dim            arProfiler.stProfiler(1)

      ; Transfer compile-time metadata to runtime values
      ; In the future, this will load from JSON/XML instead of gVarMeta
      vmTransferMetaToRuntime()

      t     = ElapsedMilliseconds()
      sp    = gnLastVariable  ; V1.020.065: Use gnLastVariable (all allocations) to prevent locals from overwriting constants in slots 64-75
      gCurrentMaxLocal = gnLastVariable  ; V1.020.065: Start local allocator after all compile-time allocations
      cy    = 0
      pc    = 0
      ReDim arProfiler( gnTotalTokens )

      ; Optimized VM loop: cache opcode and handler pointer
      opcode = CPC()
      While opcode <> #ljHALT And Not gExitApplication
         CompilerIf #C2PROFILER > 0
            arProfiler(opcode)\count + 1
            t1 = ElapsedMilliseconds()
         CompilerEndIf

         *opcodeHandler = *ptrJumpTable(opcode)

         ; Debug opcode execution
         ;If *opcodeHandler = 0
         ;   Debug "ERROR: NULL jump table entry for opcode " + Str(opcode) + " (" + gszATR(opcode)\s + ") at pc=" + Str(pc)
         ;   Break
         ;EndIf

         CallFunctionFast(*opcodeHandler)

         CompilerIf #C2PROFILER > 0
            arProfiler(opcode)\time + (ElapsedMilliseconds() - t1)
         CompilerEndIf

         ; Debug: Track pc values in critical depth range (disabled - too verbose)
         ;If gStackDepth >= 98 And (pc >= 280 And pc <= 320)
         ;   Debug "VM LOOP: After opcode " + Str(opcode) + " (" + gszATR(opcode)\s + "), pc=" + Str(pc) + " gStackDepth=" + Str(gStackDepth)
         ;EndIf

         ; Cache next opcode at end of loop (VM optimization)
         opcode = CPC()
      Wend
      
      endline  = "Runtime: " + FormatNumber( (ElapsedMilliseconds() - t ) / 1000 ) + " seconds. Stack=" + Str(sp - gnLastVariable) + " (sp=" + Str(sp) + " gnLastVariable=" + Str(gnLastVariable) + ")"

      ; V1.020.065: Debug leaked stack values (stack should be empty: sp == gnLastVariable)
      If sp <> gnLastVariable
         CompilerIf #DEBUG
            Debug "*** STACK IMBALANCE DETECTED ***"
            Debug "Expected sp=" + Str(gnLastVariable) + ", actual sp=" + Str(sp)
            If sp > gnLastVariable
               Debug "Leaked values on stack:"
               For i = gnLastVariable To sp - 1
                  Debug "  stack[" + Str(i) + "]: i=" + Str(gVar(i)\i) + " f=" + StrD(gVar(i)\f, 6) + " ss='" + gVar(i)\ss + "'"
               Next
            EndIf
         CompilerEndIf
      EndIf

      If gShowversion
         verFile = ReadFile(#PB_Any, "_lj2.ver")
         If verFile
            verString = ReadString(verFile)
            CloseFile(verFile)
            line =  "LJ2 Compiler Version: " + verString
         Else
            line =  "LJ2 Compiler Version: unknown"
         EndIf

         Debug line
      Else
         line = ""
      EndIf
      
      If gShowModulename
         line + #CRLF$ + "Module: " + gModulename
      EndIf
      
      vm_ConsoleOrGUI( endline )
      vm_ConsoleOrGUI( line )
      vm_ConsoleOrGUI( "" )
      
      If gListASM
         vmListCode()
      EndIf
      
      CompilerIf #C2PROFILER > 0
         vm_ConsoleOrGUI( "====[Stats]=======================================" )
         For i = 0 To gnTotalTokens
            If arProfiler(i)\count > 0
               vm_ConsoleOrGUI( LSet(gszATR(i)\s,20) + RSet(FormatNumber(arProfiler(i)\count,0),16) + RSet( FormatNumber( arProfiler(i)\time/1000,3,".","," ), 12) + " total" + RSet( FormatNumber( arProfiler(i)\time / arProfiler(i)\count,3,".","," ), 16) )
               arProfiler(i)\count = 0
               arProfiler(i)\time  = 0
            EndIf
         Next
         vm_ConsoleOrGUI( "==================================================" )
      CompilerEndIf
      
      
      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Executable
         If gPasteToClipboard
            vm_ConsoleOrGUI( "" )
            SetClipboardText( GetGadgetText(#edConsole) )
         EndIf
      CompilerEndIf
   EndProcedure
   Procedure            vmPragmaSet()
      Protected.s       temp, name
      Protected         n
      
      vm_SetGlobalFromPragma( 1, "runthreaded", gRunThreaded )
      vm_SetGlobalFromPragma( 1, "console", gConsole )
      vm_SetGlobalFromPragma( 0, "version", gShowversion )      
      vm_SetGlobalFromPragma( 0, "fastprint", gFastPrint )
      vm_SetGlobalFromPragma( 0, "listasm", gListASM )
      vm_SetGlobalFromPragma( 0, "pastetoclipboard", gPasteToClipboard )      
      vm_SetGlobalFromPragma( 0, "modulename", gShowModulename )
      
      temp  = mapPragmas("decimals")
      If temp <> ""
         gDecs = Val( temp )
      EndIf
      
      ;Function stack depth
      temp  = mapPragmas("stackdepth")
      If temp <> ""
         gMaxStackDepth       = Val( temp )
         gFunctionDepth    = gMaxStackDepth - 1
         ReDim gVar( gMaxStackDepth + 1 )
      EndIf
      
      ;variable stack
      temp  = mapPragmas("stackspace")
      If temp <> ""
         gMaxStackSpace = Val( temp )
         ReDim gStack( gMaxStackSpace + 1 )
      EndIf

      If mapPragmas("floattolerance")
         temp = mapPragmas("floattolerance")
         gFloatTolerance = ValD(temp)
      EndIf

      ; Float to integer conversion mode - set jump table pointer
      temp = mapPragmas("ftoi")
      If temp = "truncate"
         *ptrJumpTable( #ljFTOI ) = @C2FTOI_TRUNCATE()
      Else
         *ptrJumpTable( #ljFTOI ) = @C2FTOI_ROUND()  ; Default
      EndIf

      temp     = mapPragmas("appname")
      If temp > "" : gszAppname = temp : EndIf

      vm_DualAssign( "consolesize", gWidth, gHeight, "x" )
      vm_DualAssign( "consoleposition", gWindowX, gWindowY, "," )      
      
   EndProcedure
   
   ; Execute the code list
   Procedure            RunVM()
      Protected         i, j, e
      Protected         err
      Protected         x, y
      Protected.s       temp, filename
      Protected         win, Event
      Protected         thRun
      Protected         verFile.i, verString.s

      vmInitVM()
      cs = ArraySize( ArCode() )      
      vmPragmaSet()

      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console    
         ; Batch mode - just execute directly
         vmExecute()
      CompilerElse
         If gConsole = #True
            win = MainWindow( gszAppName )
            ResizeWindow( #MainWindow, gWindowX, gWindowY, gWidth, gHeight )
         EndIf

         cs = ArraySize( ArCode() )

         If win
            If gRunThreaded = #True
               Debug " -- Running threaded."
               thRun = CreateThread(@vmExecute(), 0 )
            Else
               Debug " -- Running full steam."
               vmExecute()
            EndIf
            
            Repeat
               If IsWindow(#MainWindow)
                  Event = WaitWindowEvent(32)

                  Select Event
                     Case #PB_Event_CloseWindow
                        gExitApplication = #True

                     Case #PB_Event_SizeWindow
                        ResizeMain()

                     Case #PB_Event_Gadget
                        e = EventGadget()

                        If e = #BtnExit
                           gExitApplication = #True
                        ElseIf e = #BtnLoad
                           filename = OpenFileRequester( "Please choose source", ".\Examples\", "LJ Files|*.lj", 0 )

                           ; Always clear VM state before loading new file
                           vmClearRun()

                           If gRunThreaded = #True And IsThread( thRun )
                              KillThread( thRun)
                           EndIf

                           If filename > ""
                              DebugShowFilename()
                              gModuleName = filename

                              If C2Lang::LoadLJ( filename )
                                 Debug "Error: " + C2Lang::Error( @err )
                              Else
                                 C2Lang::Compile()
                              EndIf
                           EndIf

                        ElseIf e = #BtnRun
                           CloseWindow( #MainWindow )
                           C2VM::RunVM()

                        ; V1.027.4: Examples listbox - auto compile & run on selection
                        ElseIf e = #lstExamples
                           i = GetGadgetState(#lstExamples)
                           If i >= 0
                              gSelectedExample = i  ; V1.027.6: Remember selection for next window
                              filename = ".\Examples\" + GetGadgetItemText(#lstExamples, i)

                              ; Clear console
                              ClearGadgetItems(#edConsole)
                              ClearDebugOutput()

                              ; Clear VM state
                              vmClearRun()

                              If gRunThreaded = #True And IsThread( thRun )
                                 KillThread( thRun)
                              EndIf

                              gModuleName = filename
                              AddGadgetItem(#edConsole, -1, "Loading: " + filename)

                              If C2Lang::LoadLJ( filename )
                                 AddGadgetItem(#edConsole, -1, "Error: " + C2Lang::Error( @err ))
                              Else
                                 If C2Lang::Compile() = 0
                                    ; Compile passed - run it
                                    AddGadgetItem(#edConsole, -1, "Compile OK - Running...")
                                    AddGadgetItem(#edConsole, -1, "")
                                    CloseWindow( #MainWindow )
                                    C2VM::RunVM()
                                 Else
                                    AddGadgetItem(#edConsole, -1, "Compile failed")
                                 EndIf
                              EndIf
                           EndIf
                        EndIf
                  EndSelect
               Else
                  Delay(64)
               EndIf
            Until gExitApplication

            ; Wait for vmExecute thread to finish before destroying window
            If gRunThreaded = #True And IsThread(thRun)
               Debug "Waiting for VM thread to complete..."
               WaitThread(thRun)
               Debug "VM thread completed"
            EndIf
         Else
            ; Window creation failed - can't execute without console gadget
            Debug "ERROR: Failed to create console window. Cannot execute program."
         EndIf
      CompilerEndIf
   EndProcedure
EndModule

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 1057
; FirstLine = 1042
; Folding = -----
; EnableAsm
; EnableThread
; EnableXP
; SharedUCRT
; CPU = 1
; EnablePurifier
; EnableCompileCount = 182
; EnableBuildCount = 0
; EnableExeConstant