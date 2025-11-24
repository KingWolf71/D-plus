
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
   Global               gWidth.i             = 640,
                        gHeight.i            = 340   
   
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
         ;If cmpLeft < 0 Or cmpRight < 0
         ;   Debug "C2CMP: pc=" + Str(pc) + " left=" + Str(cmpLeft) + " right=" + Str(cmpRight) + " result=" + Str(cmpResult) + " sp=" + Str(sp) + " depth=" + Str(gStackDepth)
         ;EndIf
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
  
   XIncludeFile      "c2-vm-commands-v09.pb"
   XIncludeFile      "c2-pointers-v01.pbi"

   ;- Console GUI
   Procedure         MainWindow(name.s)

      If OpenWindow( #MainWindow, #PB_Ignore, #PB_Ignore, 760, 680, name, #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_TitleBar )
         ButtonGadget( #BtnExit,    5,    3,  90,  29, "EXIT" )
         ButtonGadget( #BtnLoad,  100,    3,  90,  29, "Load/Compile" )
         ButtonGadget( #BtnRun,   200,    3,  90,  29, "Run" )

         EditorGadget( #edConsole, 0,  35, 760, 650, #PB_Editor_ReadOnly )
         AddGadgetItem( #edConsole, -1, "" )
         ProcedureReturn 1
      EndIf

      ProcedureReturn 0
   EndProcedure

   Procedure         ResizeMain()
      Protected      x, y

      x = WindowWidth( #MainWindow )
      y = WindowHeight( #MainWindow )
      If x < 300 : x = 300 : EndIf
      If y < 230 : y = 230 : EndIf

      ResizeWindow( #MainWindow, #PB_Ignore, #PB_Ignore, x, y )
      ResizeGadget( #edConsole, #PB_Ignore, #PB_Ignore, x, y - 30 )

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
      ; Local variable opcodes (frame-relative)
      *ptrJumpTable( #ljLMOV )            = @C2LMOV()
      *ptrJumpTable( #ljLMOVS )           = @C2LMOVS()
      *ptrJumpTable( #ljLMOVF )           = @C2LMOVF()
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
      *ptrJumpTable( #ljADD )             = @C2ADD()
      *ptrJumpTable( #ljSUBTRACT )        = @C2SUBTRACT()
      *ptrJumpTable( #ljGREATER )         = @C2GREATER()
      *ptrJumpTable( #ljLESS )            = @C2LESS()
      *ptrJumpTable( #ljLESSEQUAL )       = @C2LESSEQUAL()
      *ptrJumpTable( #ljGreaterEqual )    = @C2GREATEREQUAL()
      *ptrJumpTable( #ljNotEqual )        = @C2NOTEQUAL()
      *ptrJumpTable( #ljEQUAL )           = @C2EQUAL()
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

      ; Pointer operations
      *ptrJumpTable( #ljGETADDR )         = @C2GETADDR()
      *ptrJumpTable( #ljGETADDRF )        = @C2GETADDRF()
      *ptrJumpTable( #ljGETADDRS )        = @C2GETADDRS()
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

      *ptrJumpTable( #ljNOOP )            = @C2NOOP()
      *ptrJumpTable( #ljNOOPIF )          = @C2NOOP()
      *ptrJumpTable( #ljfunction )        = @C2NOOP()  ; Function marker - no-op at runtime
      *ptrJumpTable( #ljHALT )            = @C2HALT()

      ; Initialize pointer function pointers for performance
      InitPointerFunctions()

   EndProcedure

   Procedure            vmTransferMetaToRuntime()
      ; Transfer gVarMeta (compile-time) to gVar (runtime)
      ; This allows compiler and VM to be separate in the future
      ; In the future, this will read from JSON/XML instead of gVarMeta
      Protected i

      CompilerIf #DEBUG
         Debug "=== vmTransferMetaToRuntime: Transferring " + Str(gnLastVariable) + " variables ==="
      CompilerEndIf

      For i = 0 To gnLastVariable - 1
         gVar(i)\i = gVarMeta(i)\valueInt
         gVar(i)\f = gVarMeta(i)\valueFloat
         gVar(i)\ss = gVarMeta(i)\valueString

         ; V1.020.064: Debug constant transfers
         CompilerIf #DEBUG
            If gVarMeta(i)\flags & #C2FLAG_CONST And i >= gnGlobalVariables
               Debug "  Transfer constant [" + Str(i) + "]: i=" + Str(gVarMeta(i)\valueInt) + " f=" + StrD(gVarMeta(i)\valueFloat, 6) + " ss='" + gVarMeta(i)\valueString + "'"
            EndIf
         CompilerEndIf

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

      temp     = mapPragmas("consolesize")
      
      If temp > ""
         gWidth   = Val( StringField(temp, 1, "x") )
         gHeight  = Val( StringField(temp, 2, "x") )
      EndIf
   
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
            ResizeWindow( #MainWindow, #PB_Ignore, #PB_Ignore, gWidth, gHeight )
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
; CursorPosition = 526
; FirstLine = 519
; Folding = ----
; EnableAsm
; EnableThread
; EnableXP
; SharedUCRT
; CPU = 1
; EnablePurifier
; EnableCompileCount = 182
; EnableBuildCount = 0
; EnableExeConstant