
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

   Structure stStack
      sp.l
      pc.l
   EndStructure

   ;- Globals
   Global            sp = 0           ; stack pointer
   Global            pc = 0           ; Process stack
   Global            cy = 0
   Global            cs = 0
   Global            gExitApplication
   Global            cline.s
   Global            gDecs = 3
   Global            gFunctionDepth = 0       ; Fast function depth counter (avoids ListSize)

   ; gBatchOutput declared in DeclareModule, initialized here
   gBatchOutput = ""

   Global Dim        *ptrJumpTable(1)
   Global NewList    llStack.stStack()
   
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
      If gVar(sp-1)\i operator gVar(sp)\i
         gVar(sp-1)\i = 1
      Else
         gVar(sp-1)\i = 0
      EndIf
      pc + 1
   EndMacro
   Macro             vm_BitOperation( operand )
      sp - 1
      gVar(sp-1)\i = gVar(sp-1)\i operand gVar(sp)\i
      pc + 1
   EndMacro
   Macro             vm_FloatComparators( operator )
      sp - 1
      If gVar(sp-1)\f operator gVar(sp)\f
         gVar(sp-1)\i = 1
      Else
         gVar(sp-1)\i = 0
      EndIf
      pc + 1
   EndMacro
   Macro             vm_FloatOperation( operand )
      sp - 1
      gVar(sp-1)\f = gVar(sp-1)\f operand gVar(sp)\f
      pc + 1
   EndMacro
  
   
   XIncludeFile      "c2-vm-commands-v03.pb"

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
      *ptrJumpTable( #ljJMP )             = @C2JMP()
      *ptrJumpTable( #ljJZ )              = @C2JZ()
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

      *ptrJumpTable( #ljCALL )            = @C2CALL()
      *ptrJumpTable( #ljReturn )          = @C2Return()
      *ptrJumpTable( #ljReturnF )         = @C2ReturnF()
      *ptrJumpTable( #ljReturnS )         = @C2ReturnS()
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

      *ptrJumpTable( #ljHALT )            = @C2HALT()

   EndProcedure
   
   Procedure            vmClearRun()
      Protected         i

      ; Clear all variables to prevent state leakage between runs
      For i = 0 To #C2MAXCONSTANTS
         gVar(i)\name = ""
         gVar(i)\ss = ""
         gVar(i)\p = 0
         gVar(i)\i = 0
         gVar(i)\f = 0.0
         gVar(i)\flags = 0
         gVar(i)\paramOffset = 0
      Next

      ; Clear the call stack
      ClearList(llStack())
      gFunctionDepth = 0

      ; Stop any running code by resetting pc and putting HALT at start
      pc = 0
      arCode(0)\code = #ljHALT
      arCode(0)\i = 0
      arCode(0)\j = 0

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

      t     = ElapsedMilliseconds()
      sp    = gnLastVariable
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

         ; Cache next opcode at end of loop (VM optimization)
         opcode = CPC()
      Wend
      
      endline  = "Runtime: " + FormatNumber( (ElapsedMilliseconds() - t ) / 1000 ) + " seconds. Stack=" + Str(sp - gnLastVariable)
      
      If mapPragmas("version")
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
      
      vm_ConsoleOrGUI( endline )
      vm_ConsoleOrGUI( line )
      vm_ConsoleOrGUI( "" )
      
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
   EndProcedure
   
   ; Execute the code list
   Procedure            RunVM()
      Protected      i, j, e
      Protected      err
      Protected      x, y
      Protected.s    temp, name, filename
      Protected      win, Event
      Protected      thRun
      Protected      verFile.i, verString.s

      Debug "******** RunVM() called ********"
      vmInitVM()
      cs = ArraySize( ArCode() )      
   
      ;Execute #pragmas first
      temp  = mapPragmas("decimals")
      If temp <> ""
         gDecs = Val( temp )
      EndIf

      name  = mapPragmas("appname")
      temp  = mapPragmas("console")
      temp  = LCase(temp)

      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console    
         ; Batch mode - just execute directly
         vmExecute()
      CompilerElse
         ; GUI mode
         If temp = "on"
            win = MainWindow( name )
            temp = mapPragmas("consolesize")
            x = Val( StringField(temp, 1, "x") )
            y = Val( StringField(temp, 2, "x") )
            ResizeWindow( #MainWindow, #PB_Ignore, #PB_Ignore, x, y )
         EndIf

         cs = ArraySize( ArCode() )

         If win
            thRun = CreateThread(@vmExecute(), 0 )

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
                           Debug ">>>>>> BtnLoad clicked <<<<<<"
                           filename = OpenFileRequester( "Please choose source", ".\Examples\", "LJ Files|*.lj", 0 )

                           ; Always clear VM state before loading new file
                           vmClearRun()

                           If IsThread( thRun )
                              KillThread( thRun)
                           EndIf

                           If filename > ""
                              If C2Lang::LoadLJ( filename )
                                 Debug "Error: " + C2Lang::Error( @err )
                              Else
                                 C2Lang::Compile()
                                 ;C2Lang::ListCode()
                              EndIf
                           EndIf

                        ElseIf e = #BtnRun
                           Debug ">>>>>> BtnRun clicked <<<<<<"
                           CloseWindow( #MainWindow )
                           C2VM::RunVM()
                        EndIf
                  EndSelect
               Else
                  Delay( 64)
               EndIf
            Until gExitApplication
         Else
            vmExecute()
         EndIf
      CompilerEndIf
   EndProcedure
EndModule

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 70
; FirstLine = 62
; Folding = ---
; Markers = 14
; EnableAsm
; EnableThread
; EnableXP
; SharedUCRT
; CPU = 1
; EnablePurifier
; EnableCompileCount = 182
; EnableBuildCount = 0
; EnableExeConstant