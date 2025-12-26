
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
   ; V1.031.106: Console line buffer for logging in console mode
   Global            gConsoleLine.s
   ; V1.031.117: Test mode - run without GUI, output to stdout
   Global            gTestMode.w
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
      ; V1.028.0: Unified collections - List and Map directly in gVar
      List ll.stVTSimple()     ; LinkedList (empty by default, PB manages memory)
      Map Map.stVTSimple()     ; Map with string keys (empty by default)
   EndStructure

   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   ; Each slot (global or function) has its own stVar with embedded var() array
   Structure stVar
      Array var.stVT(1)
   EndStructure

   Structure stStack
      sp.l                     ; Saved eval stack pointer
      pc.l                     ; Saved program counter
      funcSlot.l               ; V1.035.0: Which function slot this frame belongs to
      *savedFrame.stVar        ; V1.035.0: Original gVar pointer (to restore on return)
      localCount.l             ; Number of local slots (params + locals)
      isAllocated.b            ; V1.035.0: True if frame was AllocateStructure'd (needs FreeStructure)
      isPooled.b               ; V1.034.64: True if frame from pool (return to pool, don't free)
      ; V1.035.0: POINTER ARRAY ARCHITECTURE
      ; On recursion: allocate new frame, swap pointer in *gVar(funcSlot)
      ; On return: restore original pointer, FreeStructure if allocated
   EndStructure

   ;- Globals
   Global               sp                   = 0           ; stack pointer
   Global               pc                   = 0           ; Process stack
   Global               cy                   = 0
   Global               cs                   = 0
   Global               gFunctionDepth       = 0       ; Fast function depth counter (avoids ListSize)
   Global               gStackDepth          = -1      ; Current stack frame index (-1 = no frames)
   Global               gDecs                = 3
   Global               gExitApplication     = 0
   Global               gCall0Count          = 0       ; V1.034.73: Debug counter for CALL0
   Global               gCallCount           = 0       ; V1.034.73: Debug counter for CALL
   Global               gStopVMThread        = 0       ; V1.031.41: Graceful thread stop for Linux   
   Global               gVMThreadFinished    = 0       ; V1.031.46: Simple flag set when VM thread finishes
   Global               gGlobalStack         = 2048
   Global               gFunctionStack       = 256
   Global               gMaxEvalStack        = 1024
   ; V1.035.0: gCurrentFuncSlot tracks current function for local access
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
   ; V1.031.104: Linux GTK threading broken - force non-threaded
   CompilerIf #PB_Compiler_OS = #PB_OS_Linux
      gRunThreaded = #False
   CompilerEndIf
   Global               gthRun.i             = 0
   
   Global               gConsole.w           = #True
   
   Global               gFloatTolerance.d    = 0.00001
   Global               cline.s              = ""
   Global               gszAppname.s         = "Unnamed"
   Global               gDefFPS              = 16
   Global               gFPSWait             = gDefFPS * 4
   Global               gFPSFast             = gDefFPS / 2
   Global               gThreadKillWait      = 2000
   Global               gAutoclose           = 0            ; 0 = off, or seconds to wait
   Global               gAbortAutoclose      = 0            ; V1.031.108: Set to abort countdown
   Global               gCreateLog           = 0
   Global               szLogname.s          = "[default]"   ;"+" infront of name = append

   Global               gSelectedExample.i   = 0       ; V1.027.6: Track selected example in listbox

   Global Dim           *ptrJumpTable(1)
   Global Dim           gStack.stStack(gFunctionStack)   ; Call stack (function frames)

   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   ; *gVar(slot) points to stVar structure containing var() array
   ; - Globals: *gVar(0) to *gVar(n) each hold one value in \var(0)
   ; - Functions: *gVar(funcSlot)\var(0..nLocals-1) holds params + locals
   ; - Recursion: swap pointer to AllocateStructure'd frame, restore on return
   Global Dim           *gVar.stVar(gGlobalStack)        ; Pointer array for globals + functions

   ; V1.035.0: Separate eval stack for expression evaluation (push/pop)
   Global Dim           gEvalStack.stVT(gMaxEvalStack)   ; Evaluation stack

   ; V1.035.0: Track which functions have active frames (for recursion detection)
   Global Dim           gFuncActive.b(gGlobalStack)      ; True if function's base frame is in use

   ; V1.035.0: Current function slot for local variable access
   ; Updated by CALL/RETURN - opcodes use *gVar(gCurrentFuncSlot)\var(idx)
   Global               gCurrentFuncSlot.l = 0

   ; V1.034.65: Frame pool for fast recursive frame allocation
   ; Pool size configurable via #pragma RecursionFrame (default 1024)
   #FRAME_VAR_SIZE = 32          ; Max vars per pooled frame
   Global               gRecursionFrame.l = 1024   ; Max recursion depth (configurable via pragma)
   Global Dim           *gFramePool.stVar(1024)    ; Will be ReDim'd in vmPragmaSet
   Global               gFramePoolTop.l = 0        ; Next available pool slot

   Global               gLogfn.i                             ; Log Filenumber

   ; V1.031.96: Flag for pending RunVM - checked in main loop, not in bound callback
   Global               gRunVMPending.i  = #False

   ; V1.031.101: GUI message queue for thread-safe GUI updates on Linux
   Enumeration
      #MSG_SET_TEXT
      #MSG_ADD_LINE
   EndEnumeration

   Structure stGUIMessage
      msgType.i
      gadgetID.i
      lineNum.i
      text.s
   EndStructure

   Global NewList       gGUIQueue.stGUIMessage()
   Global               gGUIQueueMutex.i = CreateMutex()

   ;- Macros
   ; V1.031.101: Queue-based threading for GUI
   ; V1.031.106: Added logging support for console mode
   ; V1.033.13: Fixed test mode - use PrintN when gTestMode is set
   Macro             vm_ConsoleOrGUI( mytext )
      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
         PrintN( mytext )
         If gCreateLog
            WriteStringN(gLogfn, mytext)
         EndIf
      CompilerElse
         If gTestMode = #True
            PrintN( mytext )
         ElseIf gRunThreaded
            vmQueueGUIMessage(#MSG_ADD_LINE, #edConsole, 0, mytext)
         Else
            AddGadgetItem( #edConsole, -1, mytext )
         EndIf
         If gCreateLog
            WriteStringN(gLogfn, mytext)
         EndIf
      CompilerEndIf
   EndMacro

   ; V1.031.101: Queue-based threading for GUI - SetGadgetItemText
   ; V1.031.106: Use WriteStringN for proper log formatting
   Macro             vm_SetGadgetText(gadgetID, lineNum, text)
      If gRunThreaded
         vmQueueGUIMessage(#MSG_SET_TEXT, gadgetID, lineNum, text)
      Else
         SetGadgetItemText(gadgetID, lineNum, text)
      EndIf

      If gCreateLog
         WriteStringN(gLogfn, text)
      EndIf
   EndMacro

   ; V1.031.101: Queue-based threading for GUI - AddGadgetItem
   Macro             vm_AddGadgetLine(gadgetID, text)
      If gRunThreaded
         vmQueueGUIMessage(#MSG_ADD_LINE, gadgetID, 0, text)
      Else
         AddGadgetItem(gadgetID, -1, text)
      EndIf
   EndMacro

   ; V1.031.101: No-op for scroll
   Macro             vm_ScrollGadget(gadgetID)
   EndMacro

   Macro             vm_ProperCloseWindow()

      If IsWindow( #MainWindow )
         ; V1.031.104: Remove timer before closing
         RemoveWindowTimer(#MainWindow, #C2VM_QUEUE_TIMER)
         UnbindEvent(#PB_Event_Timer, @vmTimerCallback())
         UnbindEvent( #PB_Event_SizeWindow, @ResizeMain() )
         UnbindEvent( #PB_Event_CloseWindow, @vmCloseWindow() )
         UnbindGadgetEvent( #lstExamples, @vmListExamples() )
         CloseWindow( #MainWindow )
      EndIf
      Delay(32)
   EndMacro


   ; V1.035.0: Updated macros for Pointer Array Architecture (use gEvalStack[])
   Macro             vm_Comparators( operator )
      sp - 1
      CompilerIf #DEBUG
         Protected cmpLeft.i = gEvalStack(sp-1)\i
         Protected cmpRight.i = gEvalStack(sp)\i
         Protected cmpResult.i
      CompilerEndIf
      If gEvalStack(sp-1)\i operator gEvalStack(sp)\i
         gEvalStack(sp-1)\i = 1
         CompilerIf #DEBUG
            cmpResult = 1
         CompilerEndIf
      Else
         gEvalStack(sp-1)\i = 0
         CompilerIf #DEBUG
            cmpResult = 0
         CompilerEndIf
      EndIf
      pc + 1
   EndMacro
   Macro             vm_BitOperation( operand )
      sp - 1
      gEvalStack(sp-1)\i = gEvalStack(sp-1)\i operand gEvalStack(sp)\i
      pc + 1
   EndMacro
   Macro             vm_FloatComparators( operator )
      sp - 1
      If gEvalStack(sp - 1)\f operator gEvalStack(sp)\f
         gEvalStack(sp - 1)\i = 1
      Else
         gEvalStack(sp - 1)\i = 0
      EndIf
      pc + 1
   EndMacro
   Macro             vm_FloatOperation( operand )
      sp - 1
      gEvalStack(sp - 1)\f = gEvalStack(sp - 1)\f operand gEvalStack(sp)\f
      pc + 1
   EndMacro

   ; V1.035.0: Inline hot opcode macros for VM loop optimization
   ; Updated for Pointer Array Architecture
   ; These eliminate procedure call overhead for the most frequently executed opcodes
   CompilerIf #VM_INLINE_HOT > 0
      Macro vm_InlineLFETCH()
         gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(arCode(pc)\i)\i
         sp + 1 : pc + 1
      EndMacro
      Macro vm_InlinePUSH()
         gEvalStack(sp)\i = *gVar(arCode(pc)\i)\var(0)\i
         sp + 1 : pc + 1
      EndMacro
      Macro vm_InlineLSTORE()
         sp - 1
         *gVar(gCurrentFuncSlot)\var(arCode(pc)\i)\i = gEvalStack(sp)\i
         pc + 1
      EndMacro
      Macro vm_InlineADD()
         sp - 1
         gEvalStack(sp-1)\i = gEvalStack(sp-1)\i + gEvalStack(sp)\i
         pc + 1
      EndMacro
      ; V1.031.113: Push immediate value (no gVar lookup)
      Macro vm_InlinePUSH_IMM()
         gEvalStack(sp)\i = arCode(pc)\i
         sp + 1 : pc + 1
      EndMacro
      ; V1.033.15: Additional hot opcodes from benchmark analysis
      Macro vm_InlineLFETCHS()
         gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(arCode(pc)\i)\ss
         sp + 1 : pc + 1
      EndMacro
      Macro vm_InlineSTORE()
         sp - 1
         *gVar(arCode(pc)\i)\var(0)\i = gEvalStack(sp)\i
         pc + 1
      EndMacro
      Macro vm_InlineLSTORES()
         sp - 1
         *gVar(gCurrentFuncSlot)\var(arCode(pc)\i)\ss = gEvalStack(sp)\ss
         pc + 1
      EndMacro
      Macro vm_InlineSUB()
         sp - 1
         gEvalStack(sp-1)\i = gEvalStack(sp-1)\i - gEvalStack(sp)\i
         pc + 1
      EndMacro
      Macro vm_InlineJMP()
         pc + arCode(pc)\i
      EndMacro
      Macro vm_InlineNEG()
         gEvalStack(sp-1)\i = -gEvalStack(sp-1)\i
         pc + 1
      EndMacro
   CompilerEndIf

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
   Macro             vm_SetArrayFromPragma(pragma, garray, gvariable)
      temp  = mapPragmas(pragma)
      If temp <> ""
         gvariable       = Val( temp )
         ReDim garray( gvariable )
      EndIf
   EndMacro
   Macro             vm_SetIntFromPragma(pragma,gvariable)
      temp  = mapPragmas(pragma)
      If temp <> ""
         gvariable = Val( temp )
         If gvariable < 0 : gvariable = -gvariable : EndIf
      EndIf
   EndMacro
   ; V1.031.108: VM initialization macro - used before vmExecute()
   Macro             vm_InitializeVM()
      gExitApplication = 0
      gStopVMThread = 0
      gVMThreadFinished = 0
      vmInitVM()
      cs = ArraySize(ArCode())
      vmPragmaSet()
   EndMacro
   ; V1.035.0: Struct pointer macros - unified struct field access via \ptr
   ; All struct variables store data in *gVar(slot)\var(0)\ptr as contiguous memory
   ; Field offset = field_index * 8 (8 bytes per field)
   Macro StructGetInt(slot, offset)
      PeekQ(*gVar(slot)\var(0)\ptr + offset)
   EndMacro
   Macro StructGetFloat(slot, offset)
      PeekD(*gVar(slot)\var(0)\ptr + offset)
   EndMacro
   Macro StructSetInt(slot, offset, value)
      PokeQ(*gVar(slot)\var(0)\ptr + offset, value)
   EndMacro
   Macro StructSetFloat(slot, offset, value)
      PokeD(*gVar(slot)\var(0)\ptr + offset, value)
   EndMacro
   ; V1.029.55: String struct field macros
   ; Strings stored as pointers to dynamically allocated string memory
   Macro StructGetStr(slot, offset)
      PeekS(PeekQ(*gVar(slot)\var(0)\ptr + offset))
   EndMacro
   ; Note: StructSetStr is a procedure, not macro, due to memory management
   Macro StructAlloc(slot, byteSize)
      If *gVar(slot)\var(0)\ptr : FreeMemory(*gVar(slot)\var(0)\ptr) : EndIf
      *gVar(slot)\var(0)\ptr = AllocateMemory(byteSize)
   EndMacro
   Macro StructCopy(srcPtr, destPtr, byteSize)
      CopyMemory(srcPtr, destPtr, byteSize)
   EndMacro
   ; V1.035.0: LOCAL struct field macros - use *gVar(gCurrentFuncSlot)\var(localIdx)
   Macro StructGetIntLocal(localIdx, offset)
      PeekQ(*gVar(gCurrentFuncSlot)\var(localIdx)\ptr + offset)
   EndMacro
   Macro StructGetFloatLocal(localIdx, offset)
      PeekD(*gVar(gCurrentFuncSlot)\var(localIdx)\ptr + offset)
   EndMacro
   Macro StructSetIntLocal(localIdx, offset, value)
      PokeQ(*gVar(gCurrentFuncSlot)\var(localIdx)\ptr + offset, value)
   EndMacro
   Macro StructSetFloatLocal(localIdx, offset, value)
      PokeD(*gVar(gCurrentFuncSlot)\var(localIdx)\ptr + offset, value)
   EndMacro
   Macro StructGetStrLocal(localIdx, offset)
      PeekS(PeekQ(*gVar(gCurrentFuncSlot)\var(localIdx)\ptr + offset))
   EndMacro
   ; V1.035.0: LOCAL struct allocation macro
   Macro StructAllocLocal(localIdx, byteSize)
      If *gVar(gCurrentFuncSlot)\var(localIdx)\ptr : FreeMemory(*gVar(gCurrentFuncSlot)\var(localIdx)\ptr) : EndIf
      *gVar(gCurrentFuncSlot)\var(localIdx)\ptr = AllocateMemory(byteSize)
   EndMacro

   ; V1.031.101: Queue GUI message from worker thread
   Procedure vmQueueGUIMessage(msgType.i, gadgetID.i, lineNum.i, text.s)
      LockMutex(gGUIQueueMutex)
      AddElement(gGUIQueue())
      gGUIQueue()\msgType = msgType
      gGUIQueue()\gadgetID = gadgetID
      gGUIQueue()\lineNum = lineNum
      gGUIQueue()\text = text
      UnlockMutex(gGUIQueueMutex)
   EndProcedure

   ; V1.031.101: Process queued GUI messages on main thread
   ; V1.031.104: TryLockMutex - don't block if worker thread is adding messages
   Procedure vmProcessGUIQueue()
      Protected count.i = 0
      If TryLockMutex(gGUIQueueMutex)
         ForEach gGUIQueue()
            Select gGUIQueue()\msgType
               Case #MSG_SET_TEXT
                  SetGadgetItemText(gGUIQueue()\gadgetID, gGUIQueue()\lineNum, gGUIQueue()\text)
               Case #MSG_ADD_LINE
                  AddGadgetItem(gGUIQueue()\gadgetID, -1, gGUIQueue()\text)
            EndSelect
            count + 1
         Next
         ClearList(gGUIQueue())
         UnlockMutex(gGUIQueueMutex)
      EndIf
      ProcedureReturn count
   EndProcedure

   ; V1.031.41: Graceful thread shutdown for Linux (avoid KillThread deadlocks)
   Procedure vmStopVMThread(thread.i, timeoutMs.i = 500)
      Protected startTime.i, elapsed.i

      If thread = 0 Or Not IsThread(thread)
         ProcedureReturn #True
      EndIf

      ; Signal the thread to stop
      gStopVMThread = #True

      ; Wait for thread to exit gracefully with timeout
      startTime = ElapsedMilliseconds()
      While IsThread(thread)
         elapsed = ElapsedMilliseconds() - startTime
         If elapsed > timeoutMs          
               KillThread(thread)
               ProcedureReturn #True
         EndIf
         Delay(16)
      Wend

      ; Thread stopped gracefully
      gStopVMThread = #False
      ProcedureReturn #True
   EndProcedure

   XIncludeFile      "c2-vm-commands-v15.pb"
   ; Note: c2-pointers-v06.pbi and c2-collections-v04.pbi included via c2-vm-commands-v15.pb
   ; V1.028.0: Collections (lists/maps) now unified in gVar\ll() and gVar\map()

   ;- Console GUI
   Procedure         MainWindow(name.s)
      Protected       dir, filename.s

      ; V1.031.72: Added SystemMenu flag for Linux compatibility
      If OpenWindow( #MainWindow, #PB_Ignore, #PB_Ignore, 960, 680, name, #PB_Window_SystemMenu | #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_TitleBar )
         ButtonGadget( #BtnExit,    5,    3,  90,  29, "EXIT" )
         ButtonGadget( #BtnLoad,  100,    3,  90,  29, "Load/Compile" )
         ButtonGadget( #BtnRun,   200,    3,  90,  29, "Run" )

         ; V1.027.4: Examples listbox on the left side
         ListViewGadget( #lstExamples, 0, 35, 200, 640 )
         EditorGadget( #edConsole, 205,  35, 755, 640 )
         ; V1.031.101: Add initial line so cy=0 has a line to update
         AddGadgetItem( #edConsole, -1, "" )

         ; Populate listbox with *.lj files from Examples folder
         ; V1.031.30: Cross-platform path
         CompilerIf #PB_Compiler_OS = #PB_OS_Windows
            dir = ExamineDirectory(#PB_Any, ".\Examples\", "*.lj")
         CompilerElse
            dir = ExamineDirectory(#PB_Any, "./Examples/", "*.lj")
         CompilerEndIf
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

         ProcedureReturn 1
      EndIf

      ProcedureReturn 0
   EndProcedure

   Procedure         ResizeMain()
      Protected      x, y

      x = WindowWidth( #MainWindow )
      y = WindowHeight( #MainWindow )

      ; V1.031.100: Only enforce minimums and resize gadgets - don't call ResizeWindow from callback
      ; On Linux/GTK, calling ResizeWindow from resize event callback can cause issues
      If x < 500 : x = 500 : EndIf
      If y < 230 : y = 230 : EndIf

      ; V1.027.4: Resize listbox and console with proper layout
      ResizeGadget( #lstExamples, #PB_Ignore, #PB_Ignore, #PB_Ignore, y - 40 )
      ResizeGadget( #edConsole, #PB_Ignore, #PB_Ignore, x - 205, y - 40 )
      Delay(gFPSFast)
      
   EndProcedure

   ; V1.031.104: Timer callback for processing GUI queue (Linux threading support)
   Procedure vmTimerCallback()
      vmProcessGUIQueue()
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
      *ptrJumpTable( #ljLLPMOV )          = @C2LLPMOV()  ; V1.033.41: Pointer variant
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
      *ptrJumpTable( #ljSTORE_STRUCT )    = @C2STORE_STRUCT()  ; V1.029.84: Store struct (copies \i and \ptr)
      *ptrJumpTable( #ljLSTORE_STRUCT )   = @C2LSTORE_STRUCT() ; V1.031.32: Local struct store
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
      ; V1.035.16: Fused comparison-jump opcodes
      *ptrJumpTable( #ljJGE_VAR_IMM )     = @C2JGE_VAR_IMM()
      *ptrJumpTable( #ljJGT_VAR_IMM )     = @C2JGT_VAR_IMM()
      *ptrJumpTable( #ljJLE_VAR_IMM )     = @C2JLE_VAR_IMM()
      *ptrJumpTable( #ljJLT_VAR_IMM )     = @C2JLT_VAR_IMM()
      *ptrJumpTable( #ljJEQ_VAR_IMM )     = @C2JEQ_VAR_IMM()
      *ptrJumpTable( #ljJNE_VAR_IMM )     = @C2JNE_VAR_IMM()
      *ptrJumpTable( #ljJGE_LVAR_IMM )    = @C2JGE_LVAR_IMM()
      *ptrJumpTable( #ljJGT_LVAR_IMM )    = @C2JGT_LVAR_IMM()
      *ptrJumpTable( #ljJLE_LVAR_IMM )    = @C2JLE_LVAR_IMM()
      *ptrJumpTable( #ljJLT_LVAR_IMM )    = @C2JLT_LVAR_IMM()
      *ptrJumpTable( #ljJEQ_LVAR_IMM )    = @C2JEQ_LVAR_IMM()
      *ptrJumpTable( #ljJNE_LVAR_IMM )    = @C2JNE_LVAR_IMM()
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
      *ptrJumpTable( #ljSHL )             = @C2SHL()    ; V1.034.30: Bit shift left
      *ptrJumpTable( #ljSHR )             = @C2SHR()    ; V1.034.30: Bit shift right
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
      *ptrJumpTable( #ljCALL0 )           = @C2CALL0()   ; V1.033.12: 0 params
      *ptrJumpTable( #ljCALL1 )           = @C2CALL1()   ; V1.033.12: 1 param
      *ptrJumpTable( #ljCALL2 )           = @C2CALL2()   ; V1.033.12: 2 params
      *ptrJumpTable( #ljCALL_REC )        = @C2CALL_REC()  ; V1.034.65: Recursive call (uses frame pool)
      *ptrJumpTable( #ljreturn )          = @C2Return()
      *ptrJumpTable( #ljreturnF )         = @C2ReturnF()
      *ptrJumpTable( #ljreturnS )         = @C2ReturnS()
      *ptrJumpTable( #ljPOP )             = @C2POP()
      *ptrJumpTable( #ljPOPS )            = @C2POPS()
      *ptrJumpTable( #ljPOPF )            = @C2POPF()
      *ptrJumpTable( #ljPUSHS )           = @C2PUSHS()
      *ptrJumpTable( #ljPUSHF )           = @C2PUSHF()
      *ptrJumpTable( #ljPUSH_IMM )        = @C2PUSH_IMM()   ; V1.031.113: Push immediate value

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
      *ptrJumpTable( #ljBUILTIN_PRINTF )  = @C2BUILTIN_PRINTF()  ; V1.035.13

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

      ; V1.029.36: Struct pointer operations
      *ptrJumpTable( #ljSTRUCT_ALLOC )          = @C2STRUCT_ALLOC()
      *ptrJumpTable( #ljSTRUCT_ALLOC_LOCAL )    = @C2STRUCT_ALLOC_LOCAL()
      *ptrJumpTable( #ljSTRUCT_FREE )           = @C2STRUCT_FREE()
      *ptrJumpTable( #ljSTRUCT_FETCH_INT )      = @C2STRUCT_FETCH_INT()
      *ptrJumpTable( #ljSTRUCT_FETCH_FLOAT )    = @C2STRUCT_FETCH_FLOAT()
      *ptrJumpTable( #ljSTRUCT_FETCH_INT_LOCAL )    = @C2STRUCT_FETCH_INT_LOCAL()
      *ptrJumpTable( #ljSTRUCT_FETCH_FLOAT_LOCAL )  = @C2STRUCT_FETCH_FLOAT_LOCAL()
      *ptrJumpTable( #ljSTRUCT_STORE_INT )      = @C2STRUCT_STORE_INT()
      *ptrJumpTable( #ljSTRUCT_STORE_FLOAT )    = @C2STRUCT_STORE_FLOAT()
      *ptrJumpTable( #ljSTRUCT_STORE_INT_LOCAL )    = @C2STRUCT_STORE_INT_LOCAL()
      *ptrJumpTable( #ljSTRUCT_STORE_FLOAT_LOCAL )  = @C2STRUCT_STORE_FLOAT_LOCAL()
      ; V1.029.55: String struct field support
      *ptrJumpTable( #ljSTRUCT_FETCH_STR )        = @C2STRUCT_FETCH_STR()
      *ptrJumpTable( #ljSTRUCT_FETCH_STR_LOCAL )  = @C2STRUCT_FETCH_STR_LOCAL()
      *ptrJumpTable( #ljSTRUCT_STORE_STR )        = @C2STRUCT_STORE_STR()
      *ptrJumpTable( #ljSTRUCT_STORE_STR_LOCAL )  = @C2STRUCT_STORE_STR_LOCAL()
      *ptrJumpTable( #ljSTRUCT_COPY_PTR )       = @C2STRUCT_COPY_PTR()
      *ptrJumpTable( #ljFETCH_STRUCT )          = @C2FETCH_STRUCT()
      *ptrJumpTable( #ljLFETCH_STRUCT )         = @C2LFETCH_STRUCT()

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

      ; V1.029.28: Struct list operations
      *ptrJumpTable( #ljLIST_ADD_STRUCT )       = @C2LIST_ADD_STRUCT()
      *ptrJumpTable( #ljLIST_GET_STRUCT )       = @C2LIST_GET_STRUCT()
      *ptrJumpTable( #ljLIST_SET_STRUCT )       = @C2LIST_SET_STRUCT()

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

      ; V1.029.28: Struct map operations
      *ptrJumpTable( #ljMAP_PUT_STRUCT )        = @C2MAP_PUT_STRUCT()
      *ptrJumpTable( #ljMAP_GET_STRUCT )        = @C2MAP_GET_STRUCT()
      *ptrJumpTable( #ljMAP_VALUE_STRUCT )      = @C2MAP_VALUE_STRUCT()

      ; V1.029.65: \ptr-based struct collection operations
      *ptrJumpTable( #ljLIST_ADD_STRUCT_PTR )   = @C2LIST_ADD_STRUCT_PTR()
      *ptrJumpTable( #ljLIST_GET_STRUCT_PTR )   = @C2LIST_GET_STRUCT_PTR()
      *ptrJumpTable( #ljMAP_PUT_STRUCT_PTR )    = @C2MAP_PUT_STRUCT_PTR()
      *ptrJumpTable( #ljMAP_GET_STRUCT_PTR )    = @C2MAP_GET_STRUCT_PTR()

      ; V1.034.6: FOREACH opcodes for lists and maps
      *ptrJumpTable( #ljFOREACH_LIST_INIT )     = @C2FOREACH_LIST_INIT()
      *ptrJumpTable( #ljFOREACH_LIST_NEXT )     = @C2FOREACH_LIST_NEXT()
      *ptrJumpTable( #ljFOREACH_MAP_INIT )      = @C2FOREACH_MAP_INIT()
      *ptrJumpTable( #ljFOREACH_MAP_NEXT )      = @C2FOREACH_MAP_NEXT()
      *ptrJumpTable( #ljFOREACH_END )           = @C2FOREACH_END()
      *ptrJumpTable( #ljFOREACH_LIST_GET_INT )  = @C2FOREACH_LIST_GET_INT()
      *ptrJumpTable( #ljFOREACH_LIST_GET_FLOAT )= @C2FOREACH_LIST_GET_FLOAT()
      *ptrJumpTable( #ljFOREACH_LIST_GET_STR )  = @C2FOREACH_LIST_GET_STR()
      *ptrJumpTable( #ljFOREACH_MAP_KEY )       = @C2FOREACH_MAP_KEY()
      *ptrJumpTable( #ljFOREACH_MAP_VALUE_INT ) = @C2FOREACH_MAP_VALUE_INT()
      *ptrJumpTable( #ljFOREACH_MAP_VALUE_FLOAT)= @C2FOREACH_MAP_VALUE_FLOAT()
      *ptrJumpTable( #ljFOREACH_MAP_VALUE_STR ) = @C2FOREACH_MAP_VALUE_STR()

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
      ; V1.033.5: Local variable pointer FETCH
      *ptrJumpTable( #ljPTRFETCH_LVAR_INT )   = @C2PTRFETCH_LVAR_INT()
      *ptrJumpTable( #ljPTRFETCH_LVAR_FLOAT ) = @C2PTRFETCH_LVAR_FLOAT()
      *ptrJumpTable( #ljPTRFETCH_LVAR_STR )   = @C2PTRFETCH_LVAR_STR()
      ; V1.033.5: Local array element pointer FETCH
      *ptrJumpTable( #ljPTRFETCH_LARREL_INT ) = @C2PTRFETCH_LARREL_INT()
      *ptrJumpTable( #ljPTRFETCH_LARREL_FLOAT)= @C2PTRFETCH_LARREL_FLOAT()
      *ptrJumpTable( #ljPTRFETCH_LARREL_STR ) = @C2PTRFETCH_LARREL_STR()
      ; V1.033.5: Local variable pointer STORE
      *ptrJumpTable( #ljPTRSTORE_LVAR_INT )   = @C2PTRSTORE_LVAR_INT()
      *ptrJumpTable( #ljPTRSTORE_LVAR_FLOAT ) = @C2PTRSTORE_LVAR_FLOAT()
      *ptrJumpTable( #ljPTRSTORE_LVAR_STR )   = @C2PTRSTORE_LVAR_STR()
      ; V1.033.5: Local array element pointer STORE
      *ptrJumpTable( #ljPTRSTORE_LARREL_INT ) = @C2PTRSTORE_LARREL_INT()
      *ptrJumpTable( #ljPTRSTORE_LARREL_FLOAT)= @C2PTRSTORE_LARREL_FLOAT()
      *ptrJumpTable( #ljPTRSTORE_LARREL_STR ) = @C2PTRSTORE_LARREL_STR()
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

      ; V1.035.0: Ensure *gVar pointer array is sized to accommodate all variables
      If gnLastVariable > ArraySize(*gVar()) + 1
         ReDim *gVar.stVar(gnLastVariable + 64)
      EndIf

   EndProcedure

   Procedure            vmTransferMetaToRuntime()
      ; V1.035.0: Transfer compile-time data to runtime using Pointer Array Architecture
      ; Each slot gets its own allocated stVar structure
      Protected i
      Protected structByteSize.i  ; V1.029.40: For struct allocation
      Protected templateSize.i    ; V1.033.47: For bounds checking
      Protected gVarSize.i        ; V1.033.47: gVar array size

      CompilerIf #DEBUG
         Debug "=== vmTransferMetaToRuntime: Transferring " + Str(gnLastVariable) + " variables ==="
         Debug "  gnGlobalVariables=" + Str(gnGlobalVariables) + " gnLastVariable=" + Str(gnLastVariable)
      CompilerEndIf

      ; V1.033.47: Verify arrays are properly sized before accessing
      templateSize = ArraySize(gGlobalTemplate()) + 1
      gVarSize = ArraySize(*gVar()) + 1

      CompilerIf #DEBUG
         Debug "vmTransferMetaToRuntime: gnLastVariable=" + Str(gnLastVariable) + " templateSize=" + Str(templateSize) + " gVarSize=" + Str(gVarSize)
      CompilerEndIf

      ; V1.033.49: Verify template is sized correctly
      If gnLastVariable > templateSize
         CompilerIf #DEBUG
            Debug "ERROR: gGlobalTemplate too small! gnLastVariable=" + Str(gnLastVariable) + " templateSize=" + Str(templateSize)
         CompilerEndIf
         ProcedureReturn
      EndIf

      ; V1.035.0: Dynamically resize *gVar pointer array if needed
      If gnLastVariable > gVarSize
         CompilerIf #DEBUG
            Debug "vmTransferMetaToRuntime: Resizing *gVar from " + Str(gVarSize) + " to " + Str(gnLastVariable + 64)
         CompilerEndIf
         ReDim *gVar.stVar(gnLastVariable + 64)
         gVarSize = ArraySize(*gVar()) + 1
      EndIf

      ; V1.035.0: POINTER ARRAY ARCHITECTURE
      ; Initialize all global slots (0 to gnLastVariable-1) including constants and literals
      ; Function slots are allocated on-demand during CALL
      For i = 0 To gnLastVariable - 1
         ; Allocate stVar structure for this slot if not already done
         If Not *gVar(i)
            *gVar(i) = AllocateStructure(stVar)
            ReDim *gVar(i)\var(0)  ; Default to 1 slot
         EndIf

         If gGlobalTemplate(i)\flags & #C2FLAG_CONST
            ; This is a constant - transfer from template
            *gVar(i)\var(0)\i = gGlobalTemplate(i)\i
            *gVar(i)\var(0)\f = gGlobalTemplate(i)\f
            *gVar(i)\var(0)\ss = gGlobalTemplate(i)\ss

            CompilerIf #DEBUG
               Debug "  Transfer constant [" + Str(i) + "]: i=" + Str(gGlobalTemplate(i)\i) + " f=" + StrD(gGlobalTemplate(i)\f, 6) + " ss='" + gGlobalTemplate(i)\ss + "'"
            CompilerEndIf
         ElseIf gGlobalTemplate(i)\paramOffset = -1
            ; This is a GLOBAL variable - use gGlobalTemplate (preloaded values)
            ; Local variables (paramOffset >= 0) are initialized at function call time
            *gVar(i)\var(0)\i = gGlobalTemplate(i)\i
            *gVar(i)\var(0)\f = gGlobalTemplate(i)\f
            *gVar(i)\var(0)\ss = gGlobalTemplate(i)\ss
            *gVar(i)\var(0)\ptr = gGlobalTemplate(i)\ptr
            *gVar(i)\var(0)\ptrtype = gGlobalTemplate(i)\ptrtype

            CompilerIf #DEBUG
               If gGlobalTemplate(i)\i <> 0 Or gGlobalTemplate(i)\f <> 0 Or gGlobalTemplate(i)\ss <> ""
                  Debug "  Preload global [" + Str(i) + "]: i=" + Str(gGlobalTemplate(i)\i) + " f=" + StrD(gGlobalTemplate(i)\f, 6) + " ss='" + gGlobalTemplate(i)\ss + "'"
               EndIf
            CompilerEndIf
         EndIf

         ; Allocate array storage if this is an array variable
         If gGlobalTemplate(i)\flags & #C2FLAG_ARRAY And gGlobalTemplate(i)\arraySize > 0
            ReDim *gVar(i)\var(0)\dta\ar(gGlobalTemplate(i)\arraySize - 1)  ; 0-based indexing
            *gVar(i)\var(0)\dta\size = gGlobalTemplate(i)\arraySize
         EndIf

         ; V1.029.40: Allocate struct memory for global struct variables
         ; Local structs are allocated at function call time via STRUCT_ALLOC_LOCAL
         If gGlobalTemplate(i)\flags & #C2FLAG_STRUCT And gGlobalTemplate(i)\paramOffset < 0
            ; Calculate byte size: elementSize is field count, multiply by 8 bytes per field
            structByteSize = gGlobalTemplate(i)\elementSize * 8
            If structByteSize > 0
               *gVar(i)\var(0)\ptr = AllocateMemory(structByteSize)
               CompilerIf #DEBUG
                  Debug "  Allocate struct [" + Str(i) + "]: " + Str(structByteSize) + " bytes at ptr=" + Str(*gVar(i)\var(0)\ptr)
               CompilerEndIf
            EndIf
         EndIf
      Next
   EndProcedure

   Procedure            vmClearRun()
      Protected         i

      ; V1.035.0: POINTER ARRAY ARCHITECTURE
      ; Allocate stVar structures for all globals and functions
      ; Each *gVar(slot) points to its own stVar with var() array

      ; Clear and reallocate all variable slots (gnLastVariable includes all types)
      For i = 0 To gnLastVariable - 1
         ; Free existing structure if any
         If *gVar(i)
            FreeStructure(*gVar(i))
         EndIf
         ; Allocate new structure for this slot
         *gVar(i) = AllocateStructure(stVar)
         ; Globals use var(0) only; functions will ReDim during CALL
         ReDim *gVar(i)\var(0)
         ; Clear the value
         *gVar(i)\var(0)\i = 0
         *gVar(i)\var(0)\f = 0.0
         *gVar(i)\var(0)\ss = ""
      Next

      ; Clear the call stack
      gStackDepth = -1
      gFunctionDepth = 0

      ; V1.035.0: Clear function active flags
      For i = 0 To gGlobalStack - 1
         gFuncActive(i) = #False
      Next

      ; V1.035.0: Clear eval stack
      For i = 0 To gMaxEvalStack - 1
         gEvalStack(i)\i = 0
         gEvalStack(i)\f = 0.0
         gEvalStack(i)\ss = ""
      Next
      sp = 0

      ; V1.034.65: Initialize frame pool for fast recursion (size from gRecursionFrame pragma)
      For i = 0 To gRecursionFrame - 1
         If Not *gFramePool(i)
            *gFramePool(i) = AllocateStructure(stVar)
            ReDim *gFramePool(i)\var(#FRAME_VAR_SIZE - 1)
         EndIf
      Next
      gFramePoolTop = 0

      ; Stop any running code by resetting pc and putting HALT at start
      pc = 0
      arCode(0)\code = #ljHALT
      arCode(0)\i = 0
      arCode(0)\j = 0

      ; V1.026.4: Reset collection pools between runs
      ResetCollections()

      ; V1.031.106: Reset console line buffer for logging
      gConsoleLine   = ""
      gBatchOutput   = ""
      gAutoclose     = 0   ; Reset - vmPragmaSet will set from mapPragmas if pragma exists

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
      Protected      CountDown.i
      Protected      verFile
      Protected.s    temp, name, line, verString, endline
      Protected      opcode.w        ; Cached opcode (VM optimization)
      Protected      *opcodeHandler  ; Cached handler pointer (VM optimization)
      CompilerIf #C2PROFILER_LOG > 0
         Protected   profLogFile.i
         Protected.s timestamp$
      CompilerEndIf
      Dim            arProfiler.stProfiler(1)

      t     = ElapsedMilliseconds()
      CompilerIf #C2PROFILER > 0
         ReDim arProfiler( gnTotalTokens )
      CompilerEndIf

      ; Transfer compile-time metadata to runtime values
      ; V1.033.46: Uses gGlobalTemplate only (VM is now independent of gVarMeta)
      ; In the future, this will load from JSON/XML
      vmTransferMetaToRuntime()

      ; V1.035.0: Initialize eval stack pointer and function slot
      sp = 0                              ; Eval stack starts at 0
      gCurrentFuncSlot = 0                ; No function active initially

      ; V1.034.61: ASM listing moved to post-execution (user preference)

      ; V1.034.57: cy must account for pre-execution output (GUI mode only)
      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Executable
         If gTestMode = #False
            cy = CountGadgetItems(#edConsole) - 1  ; -1 because AddGadgetItem adds at end
            If cy < 0 : cy = 0 : EndIf
         Else
            cy = 0
         EndIf
      CompilerElse
         cy = 0
      CompilerEndIf
      pc    = 0
      
      ; Optimized VM loop: cache opcode and handler pointer
      opcode = CPC()
      While opcode <> #ljHALT And Not gExitApplication And Not gStopVMThread
         CompilerIf #C2PROFILER > 0
            arProfiler(opcode)\count + 1
            t1 = ElapsedMilliseconds()
         CompilerEndIf

         ; V1.031.111: Inline hot opcodes to eliminate procedure call overhead
         ; V1.033.15: Extended with LFETCHS, STORE, LSTORES, SUB, JMP, NEG
         CompilerIf #VM_INLINE_HOT > 0
            If opcode <= #ljNEGATE
               ; Hot opcodes in low range: JMP (#121), NEG (#122)
               If opcode = #ljJMP
                  vm_InlineJMP()
               ElseIf opcode = #ljNEGATE
                  vm_InlineNEG()
               Else
                  *opcodeHandler = *ptrJumpTable(opcode)
                  CallFunctionFast(*opcodeHandler)
               EndIf
            ElseIf opcode = #ljLFETCHS
               vm_InlineLFETCHS()
            ElseIf opcode = #ljLSTORES
               vm_InlineLSTORES()
            ElseIf opcode = #ljStore
               vm_InlineSTORE()
            ElseIf opcode = #ljSUBTRACT
               vm_InlineSUB()
            ElseIf opcode = #ljLFETCH
               vm_InlineLFETCH()
            ElseIf opcode = #ljPUSH_IMM
               vm_InlinePUSH_IMM()
            ElseIf opcode = #ljPush
               vm_InlinePUSH()
            ElseIf opcode = #ljLSTORE
               vm_InlineLSTORE()
            ElseIf opcode = #ljADD
               vm_InlineADD()
            Else
               *opcodeHandler = *ptrJumpTable(opcode)
               CallFunctionFast(*opcodeHandler)
            EndIf
         CompilerElse
            *opcodeHandler = *ptrJumpTable(opcode)
            CallFunctionFast(*opcodeHandler)
         CompilerEndIf

         CompilerIf #C2PROFILER > 0
            arProfiler(opcode)\time + (ElapsedMilliseconds() - t1)
         CompilerEndIf

         ; Cache next opcode at end of loop (VM optimization)
         opcode = CPC()
      Wend

      ; V1.031.42: VM loop ended - thread will terminate naturally
      ; V1.035.0: Stack balance - sp should be 0 at end
      ; V1.035.7: CALL/CALL0 stats only shown in DEBUG mode
      CompilerIf #DEBUG
         endline  = "Runtime: " + FormatNumber( (ElapsedMilliseconds() - t ) / 1000 ) + " seconds. sp=(" + Str(sp) + ") CALL=" + Str(gCallCount) + " CALL0=" + Str(gCall0Count)
      CompilerElse
         endline  = "Runtime: " + FormatNumber( (ElapsedMilliseconds() - t ) / 1000 ) + " seconds."
      CompilerEndIf

      ; V1.035.0: Debug leaked stack values (stack should be empty: sp == 0)
      If sp <> 0
         CompilerIf #DEBUG
            Debug "*** STACK IMBALANCE DETECTED ***"
            Debug "Expected sp=0, actual sp=" + Str(sp)
            If sp > 0
               Debug "Leaked values on gEvalStack[]:"
               For i = 0 To sp - 1
                  Debug "  gEvalStack[" + Str(i) + "]: i=" + Str(gEvalStack(i)\i) + " f=" + StrD(gEvalStack(i)\f, 6) + " ss='" + gEvalStack(i)\ss + "'"
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

      ; V1.034.61: ASM listing at end (post-execution)
      If gListASM
         vm_ConsoleOrGUI( "====[ASM Listing]=====" )
         vmListCode()
         vm_ConsoleOrGUI( "======================" )
      EndIf

      CompilerIf #C2PROFILER > 0
         vm_ConsoleOrGUI( "====[Stats]=======================================" )
         For i = 0 To gnTotalTokens
            If arProfiler(i)\count > 0
               vm_ConsoleOrGUI( LSet(gszATR(i)\s,20) + RSet(FormatNumber(arProfiler(i)\count,0),16) + RSet( FormatNumber( arProfiler(i)\time/1000,3,".","," ), 12) + " total" + RSet( FormatNumber( arProfiler(i)\time / arProfiler(i)\count,3,".","," ), 16) )
            EndIf
         Next
         vm_ConsoleOrGUI( "==================================================" )

         ; V1.031.112: Append profiler data to cumulative log file
         CompilerIf #C2PROFILER_LOG > 0
            profLogFile = OpenFile(#PB_Any, "profiler_cumulative.csv", #PB_File_Append | #PB_File_SharedRead)
            If profLogFile
               ; Write header if file is empty (new file)
               If Lof(profLogFile) = 0
                  WriteStringN(profLogFile, "Timestamp,Module,Version,Opcode,Count,TotalTime_ms,AvgTime_ms")
               EndIf
               ; Write data for each opcode with non-zero count
               timestamp$ = FormatDate("%yyyy-%mm-%dd %hh:%ii:%ss", Date())
               For i = 0 To gnTotalTokens
                  If arProfiler(i)\count > 0
                     WriteStringN(profLogFile, timestamp$ + "," + gModulename + "," + verString + "," + gszATR(i)\s + "," + Str(arProfiler(i)\count) + "," + StrD(arProfiler(i)\time/1000, 3) + "," + StrD(arProfiler(i)\time / arProfiler(i)\count, 6))
                  EndIf
               Next
               CloseFile(profLogFile)
            EndIf
         CompilerEndIf

         ; Reset profiler stats
         For i = 0 To gnTotalTokens
            arProfiler(i)\count = 0
            arProfiler(i)\time  = 0
         Next
      CompilerEndIf
      
      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Executable
         If gPasteToClipboard
            vm_ConsoleOrGUI( "" )
            SetClipboardText( GetGadgetText(#edConsole) )
         EndIf
      CompilerEndIf

      If gCreateLog
         CloseFile( gLogfn )
         gCreateLog = 0
      EndIf

      If gAutoclose
         CountDown = gAutoclose * 1000
         line = "App will auto-close in " + Str(gAutoclose) + " seconds."
         vm_ConsoleOrGUI( "" )
         vm_ConsoleOrGUI( line )

         ; V1.031.108: Autoclose - wait with abort check
         ; Only call WindowEvent() for non-threaded mode (threaded has main loop running)
         gAbortAutoclose = 0
         t = ElapsedMilliseconds()
         While ElapsedMilliseconds() - t < CountDown And Not gAbortAutoclose
            CompilerIf #PB_Compiler_ExecutableFormat <> #PB_Compiler_Console
               If Not gRunThreaded
                  WindowEvent()
               EndIf
            CompilerEndIf
            Delay(50)
         Wend

         ; Only exit if countdown completed (not aborted)
         If Not gAbortAutoclose
            gExitApplication = #True
         EndIf
      EndIf

      gVMThreadFinished = #True
      Delay(gFPSFast)
   EndProcedure
   Procedure            vmPragmaSet()
      Protected.s       temp, name
      Protected         n

      CompilerIf #PB_Compiler_OS = #PB_OS_Windows
         vm_SetGlobalFromPragma( 1, "runthreaded", gRunThreaded )
      CompilerEndIf
      
      vm_SetGlobalFromPragma( 1, "console", gConsole )
      vm_SetGlobalFromPragma( 0, "version", gShowversion )      
      vm_SetGlobalFromPragma( 0, "fastprint", gFastPrint )
      vm_SetGlobalFromPragma( 0, "listasm", gListASM )
      vm_SetGlobalFromPragma( 0, "pastetoclipboard", gPasteToClipboard )      
      vm_SetGlobalFromPragma( 0, "modulename", gShowModulename )
      vm_SetGlobalFromPragma( 0, "createlog", gCreateLog )

      ; V1.031.106: Set appname BEFORE logname so [default] works correctly
      ; V1.033.3: Strip quotes from appname pragma value
      temp     = mapPragmas("appname")
      If temp > ""
         If Left(temp, 1) = #DQUOTE$ And Right(temp, 1) = #DQUOTE$
            temp = Mid(temp, 2, Len(temp) - 2)
         EndIf
         gszAppname = temp
      EndIf

      temp  = mapPragmas("logname")
      If temp <> ""
         szLogname = temp
         If Mid(temp,1,1) = "+"
            n = #PB_File_Append
            szLogname = Mid(temp,2)
         Else
            n = 0
         EndIf
         
         If szLogname = "[default]"
            szLogname = gszAppname + ".log"
         EndIf
         
         gLogfn = OpenFile(#PB_Any,szLogname,n)
         
         If gLogfn = 0
            Debug "-- Unable to create logfile [" + szLogname + "]"
            gCreateLog = 0
         Else
            gFastPrint = 1          ; Logging will require fastprint to work
         EndIf
      EndIf
      
      vm_SetIntFromPragma("decimals", gdecs)
      vm_SetIntFromPragma("autoclose", gAutoclose)
      vm_SetIntFromPragma("defaultfps", gDefFPS)
      vm_SetIntFromPragma("threadkillwait", gThreadKillWait)
      
      gFPSFast = gDefFPS / 2
      gFPSWait = gDefFPS * 4
      
      vm_SetArrayFromPragma("functionstack", gStack, gFunctionStack)
      ; V1.035.0: Separate eval stack and pointer array
      vm_SetIntFromPragma("evalstack", gMaxEvalStack)
      vm_SetIntFromPragma("globalstack", gGlobalStack)
      ; V1.034.65: RecursionFrame pragma for frame pool size
      vm_SetIntFromPragma("recursionframe", gRecursionFrame)
      ; V1.035.0: Resize arrays for new architecture
      ReDim *gVar.stVar(gGlobalStack)
      ReDim gEvalStack.stVT(gMaxEvalStack)
      ReDim gFuncActive.b(gGlobalStack)
      ReDim *gFramePool.stVar(gRecursionFrame)   ; V1.034.65: Resize frame pool
      gFunctionDepth = gFunctionStack - 1
     
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

      vm_DualAssign( "consolesize", gWidth, gHeight, "x" )
      vm_DualAssign( "consoleposition", gWindowX, gWindowY, "," )

   EndProcedure
    Procedure            vmCloseWindow()
      gExitApplication = #True
   EndProcedure
   Procedure            vmListExamples()
      Protected         i, err
      Protected.s       filename

      Delay(gFPSFast)
      i = GetGadgetState(#lstExamples)

      If i >= 0
         ; V1.031.108: Abort any autoclose countdown when selecting new file
         gAbortAutoclose = #True
         gSelectedExample = i  ; V1.027.6: Remember selection for next window
         ; V1.031.30: Cross-platform path
         CompilerIf #PB_Compiler_OS = #PB_OS_Windows
            filename = ".\Examples\" + GetGadgetItemText(#lstExamples, i)
         CompilerElse
            filename = "./Examples/" + GetGadgetItemText(#lstExamples, i)
         CompilerEndIf

         ; V1.033.33: Stop thread FIRST before clearing VM state to avoid race condition
         If gRunThreaded = #True And IsThread( gthRun )
            vmStopVMThread( gthRun )
         EndIf

         ; V1.034.53: Clear GUI message queue BEFORE clearing console
         ; This prevents old messages from being processed after console clear
         LockMutex(gGUIQueueMutex)
         ClearList(gGUIQueue())
         UnlockMutex(gGUIQueueMutex)

         ; Clear console AFTER queue is cleared (V1.031.84: SetGadgetText for EditorGadget)
         SetGadgetText(#edConsole, "")
         ClearDebugOutput()

         ; Clear VM state (now safe since thread is stopped)
         vmClearRun()

         gModuleName = filename
         AddGadgetItem(#edConsole, -1, "Loading: " + filename)

         If C2Lang::LoadLJ( filename )
            AddGadgetItem(#edConsole, -1, "Error: " + C2Lang::Error( @err ))
         Else
            If C2Lang::Compile() = 0
               ; Compile passed - run it
               AddGadgetItem(#edConsole, -1, "Compile OK - Running...")
               AddGadgetItem(#edConsole, -1, "")
               ; V1.031.96: Set flag - main loop will call RunVM outside callback context
               gRunVMPending = #True
            Else
               AddGadgetItem(#edConsole, -1, "Compile failed")
            EndIf
         EndIf
      EndIf

   EndProcedure

   Procedure            vmWindowEvents()
      Protected         Event, e, err, i
      Protected.s       filename      
      
      If gRunThreaded = #True
         Debug " -- Running threaded."
      Else
         Debug " -- Running non-threaded."
      EndIf
      ; V1.031.108: Both modes use pending flag - event loop handles execution
      gRunVMPending = #True

      If IsWindow( #MainWindow )
         BindEvent( #PB_Event_CloseWindow, @vmCloseWindow() )
         BindEvent( #PB_Event_SizeWindow, @ResizeMain() )
         BindGadgetEvent( #lstExamples, @vmListExamples() )
         ; V1.031.104: Timer-based GUI queue processing for Linux threading support
         AddWindowTimer(#MainWindow, #C2VM_QUEUE_TIMER, 32)  ; ~60fps
         BindEvent(#PB_Event_Timer, @vmTimerCallback())

         While Not gExitApplication
            Event = WaitWindowEvent(gDefFPS)

            ; V1.031.96: Check pending RunVM flag - execute outside callback context
            If gRunVMPending
               gRunVMPending = #False
               vm_InitializeVM()

               ; V1.033.4: Set window title AFTER pragmas are loaded
               SetWindowTitle( #MainWindow, gszAppname )

               If gConsole = #True
                  ResizeWindow( #MainWindow, gWindowX, gWindowY, gWidth, gHeight )
               EndIf

               ; Execute: threaded creates thread, non-threaded runs directly
               If gRunThreaded
                  gthRun = CreateThread(@vmExecute(), 0)
               Else
                  ; V1.031.108: Force GTK refresh before/after blocking execution
                  CompilerIf #PB_Compiler_OS <> #PB_OS_Windows
                     While WindowEvent() : Wend
                  CompilerEndIf
                  vmExecute()
                  CompilerIf #PB_Compiler_OS <> #PB_OS_Windows
                     While WindowEvent() : Wend
                  CompilerEndIf
               EndIf
            EndIf
   
            Select Event
               Case #PB_Event_Gadget
                  e = EventGadget()
   
                  If e = #BtnExit
                     vm_ProperCloseWindow()
                     gExitApplication = #True
                  ElseIf e = #BtnLoad
                     ; V1.031.108: Abort any autoclose countdown
                     gAbortAutoclose = #True
                     ; V1.031.30: Cross-platform path
                     CompilerIf #PB_Compiler_OS = #PB_OS_Windows
                        filename = OpenFileRequester( "Please choose source", ".\Examples\", "LJ Files|*.lj", 0 )
                     CompilerElse
                        filename = OpenFileRequester( "Please choose source", "./Examples/", "LJ Files|*.lj", 0 )
                     CompilerEndIf
   
                     ; V1.033.33: Stop thread FIRST before clearing VM state to avoid race condition
                     If gRunThreaded = #True And IsThread( gthRun )
                        vmStopVMThread( gthRun )
                     EndIf

                     ; Clear VM state (now safe since thread is stopped)
                     vmClearRun()

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
                     ; V1.031.108: Abort any autoclose countdown
                     gAbortAutoclose = #True
                     vm_ProperCloseWindow()
                     Delay(gFPSWait)
                     C2VM::RunVM()
                  EndIf
            EndSelect
         Wend
      EndIf
   EndProcedure
   ; Execute the code list
   Procedure            RunVM()
      Protected         i, j
      Protected         err
      Protected         x, y
      Protected.s       temp
      Protected         win
      Protected         verFile.i, verString.s
      Protected         threadFinished.i      ; V1.031.49: For mutex-protected thread check
      Protected         vmThreadDone = #False

      CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
         ; Batch mode - just execute directly
         gExitApplication = 0
         vmInitVM()
         cs = ArraySize(ArCode())
         vmPragmaSet()
         vmExecute()
      CompilerElse
         ; V1.031.117: Test mode - run without GUI, output to stdout
         If gTestMode = #True
            ; Open console for output (works on both Windows and Linux)
            OpenConsole()
            ; Run directly like batch mode
            gExitApplication = 0
            vmInitVM()
            cs = ArraySize(ArCode())
            vmPragmaSet()
            vmExecute()
            ; Exit when done
            End
         EndIf

         ; V1.031.30: On Linux, check if DISPLAY is set before attempting GUI
         CompilerIf #PB_Compiler_OS = #PB_OS_Linux
            If GetEnvironmentVariable("DISPLAY") = ""
               Debug "ERROR: No DISPLAY set. Compile with 'Create executable' as Console or set DISPLAY for GUI."
               End
            EndIf
         CompilerEndIf

         If gConsole = #True
            win = MainWindow( gszAppName )
         EndIf

         If IsWindow( #MainWindow )
            vmWindowEvents()

            ; Wait for vmExecute thread to finish before destroying window
            If gRunThreaded = #True And IsThread(gthRun)
               ; V1.031.41: Use graceful shutdown with timeout (2 seconds for exit)
               vmStopVMThread(gthRun, gThreadKillWait)
            EndIf
         Else
            ; Window creation failed - can't execute without console gadget
            Debug "ERROR: Failed to create console window. Cannot execute program."
         EndIf
      CompilerEndIf
   EndProcedure
EndModule

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 79
; FirstLine = 62
; Folding = ---------------
; Markers = 1307,1402
; EnableAsm
; EnableThread
; EnableXP
; SharedUCRT
; CPU = 1
; EnablePurifier
; EnableCompileCount = 182
; EnableBuildCount = 0
; EnableExeConstant