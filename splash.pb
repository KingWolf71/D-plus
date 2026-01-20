; D-Plus Compilation Splash - Shows "Compiling..." with animation and stages
; Launched by main app, killed when compilation completes
; Reads stage info from splash.stage file
; V1.039.41

EnableExplicit

#SPLASH_TIMER = 1
#SPLASH_INTERVAL = 200  ; Update every 200ms

; Window size - taller for stages
#WIN_WIDTH = 480
#WIN_HEIGHT = 200
#BORDER_GAP = 8
#BORDER_INNER = 4

Global gDotCount.i = 0
Global gFilename.s = ""
Global gCompilingGadget.i
Global gStageGadget.i
Global gStagePath.s = ""

Procedure UpdateDots()
   gDotCount = (gDotCount + 1) % 4
   Protected dots.s = ""
   Protected i.i
   For i = 1 To gDotCount
      dots + "."
   Next
   SetGadgetText(gCompilingGadget, "Compiling" + dots)
EndProcedure

Procedure UpdateStage()
   ; Read stage from file if it exists
   If gStagePath > "" And FileSize(gStagePath) > 0
      Protected file.i = ReadFile(#PB_Any, gStagePath)
      If file
         Protected stage.s = ReadString(file)
         CloseFile(file)
         If stage > ""
            SetGadgetText(gStageGadget, stage)
         EndIf
      EndIf
   EndIf
EndProcedure

; Get filename from command line if provided
If CountProgramParameters() > 0
   gFilename = ProgramParameter(0)
   ; Remove quotes if present
   If Left(gFilename, 1) = #DQUOTE$
      gFilename = Mid(gFilename, 2, Len(gFilename) - 2)
   EndIf
EndIf

; Stage file path - in temp directory
gStagePath = GetTemporaryDirectory() + "dplus_compile.stage"

Define event.i, titleGadget.i, filenameGadget.i, progressGadget.i

; Create splash window
If OpenWindow(0, #PB_Ignore, #PB_Ignore, #WIN_WIDTH, #WIN_HEIGHT, "D-Plus",
              #PB_Window_ScreenCentered | #PB_Window_BorderLess)

   ; Set window background
   SetWindowColor(0, RGB(45, 45, 48))

   ; Outer border container (red)
   ContainerGadget(10, 0, 0, #WIN_WIDTH, #WIN_HEIGHT)
   SetGadgetColor(10, #PB_Gadget_BackColor, RGB(180, 50, 50))

   ; Inner border container (brighter red)
   ContainerGadget(11, #BORDER_GAP, #BORDER_GAP, #WIN_WIDTH - #BORDER_GAP * 2, #WIN_HEIGHT - #BORDER_GAP * 2)
   SetGadgetColor(11, #PB_Gadget_BackColor, RGB(220, 60, 60))

   ; Content area (dark)
   ContainerGadget(12, #BORDER_INNER, #BORDER_INNER,
                   #WIN_WIDTH - #BORDER_GAP * 2 - #BORDER_INNER * 2,
                   #WIN_HEIGHT - #BORDER_GAP * 2 - #BORDER_INNER * 2)
   SetGadgetColor(12, #PB_Gadget_BackColor, RGB(45, 45, 48))

   Define contentWidth.i = #WIN_WIDTH - #BORDER_GAP * 2 - #BORDER_INNER * 2 - 20

   ; Title text
   titleGadget = TextGadget(#PB_Any, 10, 10, contentWidth, 30, "D-Plus Compiler", #PB_Text_Center)
   SetGadgetColor(titleGadget, #PB_Gadget_FrontColor, RGB(220, 220, 220))
   SetGadgetColor(titleGadget, #PB_Gadget_BackColor, RGB(45, 45, 48))
   SetGadgetFont(titleGadget, LoadFont(0, "Segoe UI", 14, #PB_Font_Bold))

   ; Compiling text with animation
   gCompilingGadget = TextGadget(#PB_Any, 10, 45, contentWidth, 25, "Compiling...", #PB_Text_Center)
   SetGadgetColor(gCompilingGadget, #PB_Gadget_FrontColor, RGB(100, 220, 100))
   SetGadgetColor(gCompilingGadget, #PB_Gadget_BackColor, RGB(45, 45, 48))
   SetGadgetFont(gCompilingGadget, LoadFont(1, "Segoe UI", 11))

   ; Filename
   If gFilename > ""
      filenameGadget = TextGadget(#PB_Any, 10, 75, contentWidth, 22, GetFilePart(gFilename), #PB_Text_Center)
      SetGadgetColor(filenameGadget, #PB_Gadget_FrontColor, RGB(150, 150, 150))
      SetGadgetColor(filenameGadget, #PB_Gadget_BackColor, RGB(45, 45, 48))
      SetGadgetFont(filenameGadget, LoadFont(2, "Segoe UI", 9))
   EndIf

   ; Stage display
   gStageGadget = TextGadget(#PB_Any, 10, 110, contentWidth, 25, "Initializing...", #PB_Text_Center)
   SetGadgetColor(gStageGadget, #PB_Gadget_FrontColor, RGB(200, 180, 100))
   SetGadgetColor(gStageGadget, #PB_Gadget_BackColor, RGB(45, 45, 48))
   SetGadgetFont(gStageGadget, LoadFont(3, "Segoe UI", 10))

   ; Progress bar area (simple visual)
   progressGadget = TextGadget(#PB_Any, 10, 145, contentWidth, 20, "", #PB_Text_Center)
   SetGadgetColor(progressGadget, #PB_Gadget_FrontColor, RGB(100, 100, 100))
   SetGadgetColor(progressGadget, #PB_Gadget_BackColor, RGB(60, 60, 65))

   CloseGadgetList()  ; Content
   CloseGadgetList()  ; Inner border
   CloseGadgetList()  ; Outer border

   ; Start animation timer
   AddWindowTimer(0, #SPLASH_TIMER, #SPLASH_INTERVAL)

   ; Event loop
   Repeat
      event = WaitWindowEvent()

      Select event
         Case #PB_Event_Timer
            If EventTimer() = #SPLASH_TIMER
               UpdateDots()
               UpdateStage()
            EndIf
         Case #PB_Event_CloseWindow
            Break
      EndSelect
   ForEver

   CloseWindow(0)
EndIf

; Clean up stage file
If gStagePath > "" And FileSize(gStagePath) > 0
   DeleteFile(gStagePath)
EndIf
