; -- LJ2 View Module
;
; PBx64 v6.10+
;
; Standalone view rendering engine for LJ2
; Auto-generated GUI from declarative cell-based layout
;
; Kingwolf71 Dec/2024
; (c) All Rights reserved.
;

DeclareModule LJView
   ; Debug mode - set to 1 to enable debug panel without IDE debugger
   #LJV_DEBUG    = 1

   ; Public interface
   Declare   ViewCreate(name.s, cols.i, rows.i, seed.i = 0)
   Declare   ViewCell(ref.s, gadgetType.i, text.s = "", align.i = 0)
   Declare   ViewCellRange(refStart.s, refEnd.s, gadgetType.i, text.s = "", align.i = 0)
   Declare   ViewJoin(refStart.s, refEnd.s, name.s = "")
   Declare   ViewShow(width.i = 0, height.i = 0)
   Declare   ViewClose()
   Declare   ViewSetOrientation(landscape.i)
   Declare   ViewGetOrientation()
   Declare.i ViewGetWindowID()

   ; Debug panel (available when debugger active OR #LJV_DEBUG = 1)
   CompilerIf (Defined(PB_Compiler_Debugger, #PB_Constant) And #PB_Compiler_Debugger) Or #LJV_DEBUG
      Declare.i HandleDebugEvent(event.i, eventWindow.i, eventGadget.i)
      Declare   HandleViewClick(x.i, y.i)
   CompilerEndIf

   ; Gadget types - matches SpiderBasic gadgets
   #LJV_TEXT         = 1
   #LJV_INPUT        = 2      ; StringGadget
   #LJV_BUTTON       = 3
   #LJV_IMAGE        = 4
   #LJV_LISTVIEW     = 5      ; ListViewGadget
   #LJV_CALENDAR     = 6
   #LJV_CHECKBOX     = 7
   #LJV_COMBO        = 8      ; ComboBoxGadget
   #LJV_DATE         = 9      ; DateGadget
   #LJV_OPTION       = 10     ; OptionGadget (radio button)
   #LJV_SPIN         = 11     ; SpinGadget
   #LJV_TRACKBAR     = 12     ; TrackBarGadget (slider)
   #LJV_PROGRESS     = 13     ; ProgressBarGadget
   #LJV_HYPERLINK    = 14     ; HyperLinkGadget
   #LJV_CONTAINER    = 15     ; ContainerGadget
   #LJV_FRAME        = 16     ; FrameGadget
   #LJV_PANEL        = 17     ; PanelGadget (tabs)
   #LJV_SCROLLAREA   = 18     ; ScrollAreaGadget
   #LJV_SPLITTER     = 19     ; SplitterGadget
   #LJV_CANVAS       = 20     ; CanvasGadget
   #LJV_EDITOR       = 21     ; EditorGadget (multiline text)
   #LJV_LISTICON     = 22     ; ListIconGadget (columns)
   #LJV_TREE         = 23     ; TreeGadget
   #LJV_WEB          = 24     ; WebGadget

   ; Alignment base
   #LJV_CENTER   = 0
   #LJV_LEFT     = 1
   #LJV_RIGHT    = 2
   #LJV_TOP      = 4
   #LJV_BOTTOM   = 8

   ; Alignment modifiers (can be combined with base)
   #LJV_UP       = 16
   #LJV_DOWN     = 32
   #LJV_TOLEFT   = 64
   #LJV_TORIGHT  = 128

   ; Event flags (bitmask)
   #LJV_EVT_TAP       = 1
   #LJV_EVT_SWIPE     = 2
   #LJV_EVT_DRAG      = 4
   #LJV_EVT_LONGPRESS = 8
EndDeclareModule

Module LJView
   EnableExplicit

   ;- Forward declarations for helper functions
   Declare.i GetCellIndex(col.i, row.i)
   Declare.i GetEffectiveCols()
   Declare.i GetEffectiveRows()

   ;- Constants
   #VIEW_MAX_COLS     = 26      ; A-Z
   #VIEW_MAX_ROWS     = 99
   #VIEW_MAX_GADGETS  = 64
   #VIEW_WINDOW       = 9000

   ;- Structures
   Structure stGadget
      type.i
      text.s
      align.i                   ; Base align + nudge modifiers (#LJV_TOLEFT, etc)
      gadgetID.i
      size.i                    ; 0=small, 1=medium, 2=large, 3=xlarge
      bold.i                    ; Bold text
      italic.i                  ; Italic text
      fgColor.i                 ; Foreground (text) color, -1 = default
      bgColor.i                 ; Background color, -1 = transparent
      events.i                  ; Event bitmask (#LJV_EVT_TAP, etc)
      handler.s                 ; Handler function name prefix
   EndStructure

   Structure stCell
      col.i                     ; 0-based column (A=0, B=1, ...)
      row.i                     ; 0-based row (1=0, 2=1, ...)
      joinGroup.i               ; 0 = single, >0 = joined group ID
      masterCell.i              ; Index of master cell if joined
      isMaster.i                ; True if this is the master of a join group
      color.i                   ; Background color (from seed)
      colorLocked.i             ; If true, random doesn't change this color
      lockCorner.i              ; Always stay in corner position
      lockCornerCol.i           ; Source col for lockCorner (for join groups, tracks which cell had it)
      lockCornerRow.i           ; Source row for lockCorner (for join groups, tracks which cell had it)
      visible.i                 ; Move cell to visible if hidden (default true)
      gadgetCount.i
      Array gadgets.stGadget(4)
   EndStructure

   Structure stJoinGroup
      id.i
      name.s                    ; Optional name for the joined range (like Excel named ranges)
      startCol.i
      startRow.i
      endCol.i
      endRow.i
      masterIdx.i               ; Index into cells array
   EndStructure

   Structure stView
      name.s
      cols.i
      rows.i
      seed.i
      orientation.i             ; 0=portrait, 1=landscape
      windowID.i
      width.i
      height.i
      cellWidth.i
      cellHeight.i
      totalCells.i
      joinGroupCount.i
      Array cells.stCell(1)
      Array joinGroups.stJoinGroup(8)
   EndStructure

   ; Precomputed render position for a cell in a specific orientation
   Structure stRenderPos
      cellIdx.i                 ; Index into cells array
      x.i                       ; Pixel X position
      y.i                       ; Pixel Y position
      show.i                    ; Whether to show in this orientation
      placeholder.i             ; Background only (lockCorner vacated position)
      shifted.i                 ; Cell was shifted from natural position (visible flag)
   EndStructure

   ;- Globals
   Global gView.stView
   Global gInitialized.i = #False

   ; Maps for precomputed positions: key = "cellIdx", value = stRenderPos
   ; Portrait positions (orientation = 0)
   Global NewMap gPortraitPos.stRenderPos()
   ; Landscape positions (orientation = 1)
   Global NewMap gLandscapePos.stRenderPos()

   ; Forward declaration for GenerateColor (used by debug panel)
   Declare.i GenerateColor(seed.i, index.i)

   ;- Debug Control Panel
   CompilerIf (Defined(PB_Compiler_Debugger, #PB_Constant) And #PB_Compiler_Debugger) Or #LJV_DEBUG
      #DEBUG_WINDOW      = 9001
      #DEBUG_BTN_ROTATE  = 9010
      #DEBUG_BTN_RANDOM  = 9011
      #DEBUG_INPUT_SEED  = 9012
      #DEBUG_LBL_SEED    = 9013
      #DEBUG_LBL_ORIENT  = 9014
      #DEBUG_INPUT_START = 9015
      #DEBUG_INPUT_END   = 9016
      #DEBUG_BTN_MERGE   = 9017
      #DEBUG_EDITOR_CODE = 9018
      #DEBUG_LBL_SELECT  = 9019
      #DEBUG_BTN_UNMERGE = 9020
      #DEBUG_BTN_JOIN    = 9021
      ; Cell properties controls
      #DEBUG_FRAME_CELL  = 9022
      #DEBUG_LBL_SIZE    = 9023
      #DEBUG_OPT_SIZE_S  = 9024
      #DEBUG_OPT_SIZE_M  = 9025
      #DEBUG_OPT_SIZE_L  = 9026
      #DEBUG_OPT_SIZE_XL = 9027
      #DEBUG_CHK_BOLD    = 9028
      #DEBUG_CHK_ITALIC  = 9029
      #DEBUG_LBL_NUDGE   = 9030
      #DEBUG_CHK_NUDGE_L = 9031
      #DEBUG_CHK_NUDGE_R = 9032
      #DEBUG_CHK_NUDGE_U = 9033
      #DEBUG_CHK_NUDGE_D = 9034
      #DEBUG_CHK_CORNER  = 9035
      #DEBUG_CHK_VISIBLE = 9036
      #DEBUG_BTN_COLOR   = 9037
      #DEBUG_CHK_COLORLK = 9038
      #DEBUG_LBL_EVENTS  = 9039
      #DEBUG_CHK_EVT_TAP = 9040
      #DEBUG_CHK_EVT_SWIPE = 9041
      #DEBUG_CHK_EVT_DRAG = 9042
      #DEBUG_CHK_EVT_LONG = 9043
      #DEBUG_LBL_HANDLER = 9044
      #DEBUG_INPUT_HANDLER = 9045
      ; V02 additions
      #DEBUG_LBL_TYPE    = 9046
      #DEBUG_COMBO_TYPE  = 9047
      #DEBUG_LBL_VALUE   = 9048
      #DEBUG_INPUT_VALUE = 9049
      #DEBUG_LBL_ALIGN   = 9050
      #DEBUG_BTN_ALIGN_L = 9051
      #DEBUG_BTN_ALIGN_C = 9052
      #DEBUG_BTN_ALIGN_R = 9053
      #DEBUG_BTN_ALIGN_T = 9054
      #DEBUG_BTN_ALIGN_M = 9055
      #DEBUG_BTN_ALIGN_B = 9056
      #DEBUG_BTN_ADD_GADGET = 9057
      #DEBUG_BTN_DEL_GADGET = 9058
      #DEBUG_LBL_GCOLORS  = 9059       ; Gadget colors label
      #DEBUG_BTN_FG_COLOR = 9080       ; Foreground color button
      #DEBUG_BTN_BG_COLOR = 9081       ; Background color button
      #DEBUG_CHK_BG_TRANS = 9082       ; Transparent background checkbox
      ; Collapsible section headers and containers
      #DEBUG_HDR_SELECTION = 9060
      #DEBUG_HDR_GADGET    = 9061
      #DEBUG_HDR_FLAGS     = 9062
      #DEBUG_HDR_EVENTS    = 9063
      #DEBUG_CNT_SELECTION = 9070
      #DEBUG_CNT_GADGET    = 9071
      #DEBUG_CNT_FLAGS     = 9072
      #DEBUG_CNT_EVENTS    = 9073

      Global gDebugWindow.i = 0
      Global gLastCode.s = ""

      ; Collapsible section state (0=expanded, 1=collapsed)
      Global gCollapseSelection.i = 0
      Global gCollapseGadget.i = 0
      Global gCollapseFlags.i = 0
      Global gCollapseEvents.i = 0

      ; Section heights when expanded
      #SEC_HEIGHT_SELECTION = 90
      #SEC_HEIGHT_GADGET    = 184
      #SEC_HEIGHT_FLAGS     = 32
      #SEC_HEIGHT_EVENTS    = 56

      ; Cell selection tracking
      Global gSelectStartCol.i = -1
      Global gSelectStartRow.i = -1
      Global gSelectEndCol.i = -1
      Global gSelectEndRow.i = -1
      Global gSelectMode.i = 0      ; 0=select start, 1=select end
      Global gSelectedMergeGroup.i = 0   ; >0 if selection is on a merged cell

      Procedure.s CellRefFromColRow(col.i, row.i)
         ProcedureReturn Chr('A' + col) + Str(row + 1)
      EndProcedure

      Procedure DisableCellProps(disabled.i)
         ; Enable/disable all cell property controls
         DisableGadget(#DEBUG_COMBO_TYPE, disabled)
         DisableGadget(#DEBUG_INPUT_VALUE, disabled)
         DisableGadget(#DEBUG_BTN_ALIGN_L, disabled)
         DisableGadget(#DEBUG_BTN_ALIGN_C, disabled)
         DisableGadget(#DEBUG_BTN_ALIGN_R, disabled)
         DisableGadget(#DEBUG_BTN_ALIGN_T, disabled)
         DisableGadget(#DEBUG_BTN_ALIGN_M, disabled)
         DisableGadget(#DEBUG_BTN_ALIGN_B, disabled)
         DisableGadget(#DEBUG_OPT_SIZE_S, disabled)
         DisableGadget(#DEBUG_OPT_SIZE_M, disabled)
         DisableGadget(#DEBUG_OPT_SIZE_L, disabled)
         DisableGadget(#DEBUG_OPT_SIZE_XL, disabled)
         DisableGadget(#DEBUG_CHK_BOLD, disabled)
         DisableGadget(#DEBUG_CHK_ITALIC, disabled)
         DisableGadget(#DEBUG_CHK_NUDGE_L, disabled)
         DisableGadget(#DEBUG_CHK_NUDGE_R, disabled)
         DisableGadget(#DEBUG_CHK_NUDGE_U, disabled)
         DisableGadget(#DEBUG_CHK_NUDGE_D, disabled)
         DisableGadget(#DEBUG_BTN_FG_COLOR, disabled)
         DisableGadget(#DEBUG_BTN_BG_COLOR, disabled)
         DisableGadget(#DEBUG_CHK_BG_TRANS, disabled)
         DisableGadget(#DEBUG_CHK_CORNER, disabled)
         DisableGadget(#DEBUG_CHK_VISIBLE, disabled)
         DisableGadget(#DEBUG_BTN_COLOR, disabled)
         DisableGadget(#DEBUG_CHK_COLORLK, disabled)
         DisableGadget(#DEBUG_CHK_EVT_TAP, disabled)
         DisableGadget(#DEBUG_CHK_EVT_SWIPE, disabled)
         DisableGadget(#DEBUG_CHK_EVT_DRAG, disabled)
         DisableGadget(#DEBUG_CHK_EVT_LONG, disabled)
         DisableGadget(#DEBUG_INPUT_HANDLER, disabled)
         DisableGadget(#DEBUG_BTN_ADD_GADGET, disabled)
         DisableGadget(#DEBUG_BTN_DEL_GADGET, disabled)
      EndProcedure

      Procedure UpdateCellPropsDisplay()
         ; Update cell property controls to reflect selected cell
         Protected idx.i, *cell.stCell, gIdx.i, align.i
         Protected hasCell.i = #False
         Protected isCorner.i = #False
         Protected effCols.i, effRows.i

         If gSelectStartCol >= 0
            idx = GetCellIndex(gSelectStartCol, gSelectStartRow)
            *cell = @gView\cells(idx)
            hasCell = #True

            ; For join groups, get master cell for lockCorner/visible state
            Protected masterIdx.i = idx
            Protected *masterCell.stCell = *cell
            If *cell\joinGroup > 0
               masterIdx = *cell\masterCell
               *masterCell = @gView\cells(masterIdx)
            EndIf

            ; Check if cell is in a corner
            effCols = GetEffectiveCols()
            effRows = GetEffectiveRows()
            If (gSelectStartCol = 0 Or gSelectStartCol = effCols - 1) And (gSelectStartRow = 0 Or gSelectStartRow = effRows - 1)
               isCorner = #True
            EndIf
            Debug "UpdateCellDisplay: col=" + Str(gSelectStartCol) + " row=" + Str(gSelectStartRow) + " effCols=" + Str(effCols) + " effRows=" + Str(effRows) + " isCorner=" + Str(isCorner)

            ; Cell-level properties (read from master for join groups)
            SetGadgetState(#DEBUG_CHK_CORNER, *masterCell\lockCorner)
            SetGadgetState(#DEBUG_CHK_VISIBLE, *masterCell\visible)
            SetGadgetState(#DEBUG_CHK_COLORLK, *cell\colorLocked)
            SetGadgetColor(#DEBUG_BTN_COLOR, #PB_Gadget_BackColor, *cell\color)
            Debug "  master lockCorner=" + Str(*masterCell\lockCorner) + " visible=" + Str(*masterCell\visible)

            ; Lock Corner only available for corner cells
            DisableGadget(#DEBUG_CHK_CORNER, Bool(Not isCorner))
            Debug "  Lock Corner checkbox disabled=" + Str(Bool(Not isCorner))

            ; Gadget-level properties (from first gadget if any)
            If *cell\gadgetCount > 0
               gIdx = 0
               ; Type - map gadget type to combo index (type+1 because index 0 is "(none)")
               SetGadgetState(#DEBUG_COMBO_TYPE, *cell\gadgets(gIdx)\type + 1)
               ; Value
               SetGadgetText(#DEBUG_INPUT_VALUE, *cell\gadgets(gIdx)\text)
               ; Alignment base (horizontal)
               align = *cell\gadgets(gIdx)\align
               ; Note: buttons show current state visually (we'll handle via color later)
               ; Size
               Select *cell\gadgets(gIdx)\size
                  Case 0 : SetGadgetState(#DEBUG_OPT_SIZE_S, #True)
                  Case 1 : SetGadgetState(#DEBUG_OPT_SIZE_M, #True)
                  Case 2 : SetGadgetState(#DEBUG_OPT_SIZE_L, #True)
                  Case 3 : SetGadgetState(#DEBUG_OPT_SIZE_XL, #True)
                  Default : SetGadgetState(#DEBUG_OPT_SIZE_M, #True)
               EndSelect
               ; Style
               SetGadgetState(#DEBUG_CHK_BOLD, *cell\gadgets(gIdx)\bold)
               SetGadgetState(#DEBUG_CHK_ITALIC, *cell\gadgets(gIdx)\italic)
               ; Nudge from align modifiers
               SetGadgetState(#DEBUG_CHK_NUDGE_L, Bool(align & #LJV_TOLEFT))
               SetGadgetState(#DEBUG_CHK_NUDGE_R, Bool(align & #LJV_TORIGHT))
               SetGadgetState(#DEBUG_CHK_NUDGE_U, Bool(align & #LJV_UP))
               SetGadgetState(#DEBUG_CHK_NUDGE_D, Bool(align & #LJV_DOWN))
               ; Gadget colors
               If *cell\gadgets(gIdx)\fgColor >= 0
                  SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_BackColor, *cell\gadgets(gIdx)\fgColor)
                  ; Set contrasting text color
                  If Red(*cell\gadgets(gIdx)\fgColor) + Green(*cell\gadgets(gIdx)\fgColor) + Blue(*cell\gadgets(gIdx)\fgColor) > 384
                     SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_FrontColor, RGB(0, 0, 0))
                  Else
                     SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_FrontColor, RGB(255, 255, 255))
                  EndIf
               Else
                  SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_BackColor, RGB(0, 0, 0))
                  SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_FrontColor, RGB(255, 255, 255))
               EndIf
               If *cell\gadgets(gIdx)\bgColor >= 0
                  SetGadgetColor(#DEBUG_BTN_BG_COLOR, #PB_Gadget_BackColor, *cell\gadgets(gIdx)\bgColor)
                  SetGadgetState(#DEBUG_CHK_BG_TRANS, #False)
               Else
                  SetGadgetColor(#DEBUG_BTN_BG_COLOR, #PB_Gadget_BackColor, RGB(240, 240, 240))
                  SetGadgetState(#DEBUG_CHK_BG_TRANS, #True)
               EndIf
               ; Events
               Protected evts.i = *cell\gadgets(gIdx)\events
               SetGadgetState(#DEBUG_CHK_EVT_TAP, Bool(evts & #LJV_EVT_TAP))
               SetGadgetState(#DEBUG_CHK_EVT_SWIPE, Bool(evts & #LJV_EVT_SWIPE))
               SetGadgetState(#DEBUG_CHK_EVT_DRAG, Bool(evts & #LJV_EVT_DRAG))
               SetGadgetState(#DEBUG_CHK_EVT_LONG, Bool(evts & #LJV_EVT_LONGPRESS))
               SetGadgetText(#DEBUG_INPUT_HANDLER, *cell\gadgets(gIdx)\handler)
            Else
               ; No gadget - reset to defaults
               SetGadgetState(#DEBUG_COMBO_TYPE, 0)  ; (none)
               SetGadgetText(#DEBUG_INPUT_VALUE, "")
               SetGadgetState(#DEBUG_OPT_SIZE_M, #True)
               SetGadgetState(#DEBUG_CHK_BOLD, #False)
               SetGadgetState(#DEBUG_CHK_ITALIC, #False)
               SetGadgetState(#DEBUG_CHK_NUDGE_L, #False)
               SetGadgetState(#DEBUG_CHK_NUDGE_R, #False)
               SetGadgetState(#DEBUG_CHK_NUDGE_U, #False)
               SetGadgetState(#DEBUG_CHK_NUDGE_D, #False)
               SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_BackColor, RGB(0, 0, 0))
               SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_FrontColor, RGB(255, 255, 255))
               SetGadgetColor(#DEBUG_BTN_BG_COLOR, #PB_Gadget_BackColor, RGB(240, 240, 240))
               SetGadgetState(#DEBUG_CHK_BG_TRANS, #True)
               SetGadgetState(#DEBUG_CHK_EVT_TAP, #False)
               SetGadgetState(#DEBUG_CHK_EVT_SWIPE, #False)
               SetGadgetState(#DEBUG_CHK_EVT_DRAG, #False)
               SetGadgetState(#DEBUG_CHK_EVT_LONG, #False)
               SetGadgetText(#DEBUG_INPUT_HANDLER, "")
            EndIf
         EndIf

         If hasCell
            DisableCellProps(#False)
         Else
            DisableCellProps(#True)
         EndIf
      EndProcedure

      Procedure UpdateSelectionDisplay()
         If gDebugWindow And IsWindow(gDebugWindow)
            If gSelectStartCol >= 0
               SetGadgetText(#DEBUG_INPUT_START, CellRefFromColRow(gSelectStartCol, gSelectStartRow))
            Else
               SetGadgetText(#DEBUG_INPUT_START, "")
            EndIf

            If gSelectEndCol >= 0
               SetGadgetText(#DEBUG_INPUT_END, CellRefFromColRow(gSelectEndCol, gSelectEndRow))
            Else
               SetGadgetText(#DEBUG_INPUT_END, "")
            EndIf

            ; Handle merge/unmerge button states
            If gSelectedMergeGroup > 0
               ; Merged cell selected - show unmerge option
               DisableGadget(#DEBUG_BTN_UNMERGE, #False)
               DisableGadget(#DEBUG_BTN_MERGE, #True)
               SetGadgetText(#DEBUG_LBL_SELECT, "Merged cell selected")
            ElseIf gSelectStartCol >= 0 And gSelectEndCol >= 0
               ; Two cells selected - enable merge
               DisableGadget(#DEBUG_BTN_MERGE, #False)
               DisableGadget(#DEBUG_BTN_UNMERGE, #True)
               SetGadgetText(#DEBUG_LBL_SELECT, "Click cell to change start")
            ElseIf gSelectStartCol >= 0
               DisableGadget(#DEBUG_BTN_MERGE, #True)
               DisableGadget(#DEBUG_BTN_UNMERGE, #True)
               SetGadgetText(#DEBUG_LBL_SELECT, "Click cell to set end")
            Else
               DisableGadget(#DEBUG_BTN_MERGE, #True)
               DisableGadget(#DEBUG_BTN_UNMERGE, #True)
               SetGadgetText(#DEBUG_LBL_SELECT, "Click cell to set start")
            EndIf

            ; Update cell properties display
            UpdateCellPropsDisplay()
         EndIf
      EndProcedure

      Procedure ClearSelection()
         gSelectStartCol = -1
         gSelectStartRow = -1
         gSelectEndCol = -1
         gSelectEndRow = -1
         gSelectMode = 0
         gSelectedMergeGroup = 0
         UpdateSelectionDisplay()
      EndProcedure

      Procedure HandleViewClick(x.i, y.i)
         ; Determine which cell was clicked
         ; Cell refs are FIXED - A1 is always A1 regardless of orientation
         Protected col.i, row.i, effectiveCols.i, effectiveRows.i
         Protected idx.i, i.i
         Protected *cell.stCell
         Protected *grp.stJoinGroup
         Protected clickedMergeGroup.i = 0

         effectiveCols = GetEffectiveCols()
         effectiveRows = GetEffectiveRows()

         col = x / gView\cellWidth
         row = y / gView\cellHeight

         If col >= 0 And col < effectiveCols And row >= 0 And row < effectiveRows
            ; Get cell index - cell refs are FIXED (no transformation)
            idx = GetCellIndex(col, row)

            *cell = @gView\cells(idx)
            clickedMergeGroup = *cell\joinGroup

            ; If we have a merged cell selected and click elsewhere, extend selection
            If gSelectedMergeGroup > 0 And clickedMergeGroup <> gSelectedMergeGroup
               ; Extend from current selection to clicked cell
               Protected minCol.i, maxCol.i, minRow.i, maxRow.i

               minCol = gSelectStartCol
               maxCol = gSelectEndCol
               If maxCol < minCol : Swap minCol, maxCol : EndIf
               minRow = gSelectStartRow
               maxRow = gSelectEndRow
               If maxRow < minRow : Swap minRow, maxRow : EndIf

               ; Expand to include clicked cell (or its merge range)
               If clickedMergeGroup > 0
                  ; Clicked on another merged cell - expand to include its range
                  ; Cell refs are FIXED - use coords directly
                  For i = 0 To gView\joinGroupCount - 1
                     If gView\joinGroups(i)\id = clickedMergeGroup
                        *grp = @gView\joinGroups(i)
                        If *grp\startCol < minCol : minCol = *grp\startCol : EndIf
                        If *grp\endCol > maxCol : maxCol = *grp\endCol : EndIf
                        If *grp\startRow < minRow : minRow = *grp\startRow : EndIf
                        If *grp\endRow > maxRow : maxRow = *grp\endRow : EndIf
                        Break
                     EndIf
                  Next
               Else
                  ; Clicked on regular cell - expand to include it
                  If col < minCol : minCol = col : EndIf
                  If col > maxCol : maxCol = col : EndIf
                  If row < minRow : minRow = row : EndIf
                  If row > maxRow : maxRow = row : EndIf
               EndIf

               gSelectStartCol = minCol
               gSelectStartRow = minRow
               gSelectEndCol = maxCol
               gSelectEndRow = maxRow
               gSelectedMergeGroup = 0   ; No longer just a merge group selection
               gSelectMode = 0

            ElseIf clickedMergeGroup > 0
               ; Clicked on a merged cell (first click or same merge group)
               ; Cell refs are FIXED - use group coords directly
               For i = 0 To gView\joinGroupCount - 1
                  If gView\joinGroups(i)\id = clickedMergeGroup
                     *grp = @gView\joinGroups(i)
                     gSelectStartCol = *grp\startCol
                     gSelectStartRow = *grp\startRow
                     gSelectEndCol = *grp\endCol
                     gSelectEndRow = *grp\endRow
                     gSelectedMergeGroup = clickedMergeGroup
                     gSelectMode = 0
                     Break
                  EndIf
               Next
            Else
               ; Regular cell selection
               gSelectedMergeGroup = 0

               If gSelectMode = 0
                  ; Set start cell
                  gSelectStartCol = col
                  gSelectStartRow = row
                  gSelectEndCol = -1
                  gSelectEndRow = -1
                  gSelectMode = 1
               Else
                  ; Set end cell
                  gSelectEndCol = col
                  gSelectEndRow = row
                  gSelectMode = 0
               EndIf
            EndIf
            UpdateSelectionDisplay()
            ; Redraw to show selection
            ViewShow(gView\width, gView\height)
         EndIf
      EndProcedure

      Procedure.s GetGadgetTypeName(gadgetType.i)
         ; Return string name for gadget type
         Select gadgetType
            Case #LJV_TEXT : ProcedureReturn "text"
            Case #LJV_INPUT : ProcedureReturn "input"
            Case #LJV_BUTTON : ProcedureReturn "button"
            Case #LJV_CHECKBOX : ProcedureReturn "checkbox"
            Case #LJV_OPTION : ProcedureReturn "option"
            Case #LJV_COMBO : ProcedureReturn "combo"
            Case #LJV_DATE : ProcedureReturn "date"
            Case #LJV_SPIN : ProcedureReturn "spin"
            Case #LJV_TRACKBAR : ProcedureReturn "trackbar"
            Case #LJV_PROGRESS : ProcedureReturn "progress"
            Case #LJV_EDITOR : ProcedureReturn "editor"
            Case #LJV_LISTVIEW : ProcedureReturn "listview"
            Case #LJV_LISTICON : ProcedureReturn "listicon"
            Case #LJV_TREE : ProcedureReturn "tree"
            Case #LJV_CALENDAR : ProcedureReturn "calendar"
            Case #LJV_CANVAS : ProcedureReturn "canvas"
            Case #LJV_IMAGE : ProcedureReturn "image"
            Case #LJV_FRAME : ProcedureReturn "frame"
            Case #LJV_CONTAINER : ProcedureReturn "container"
            Case #LJV_PANEL : ProcedureReturn "panel"
            Case #LJV_SCROLLAREA : ProcedureReturn "scrollarea"
            Case #LJV_WEB : ProcedureReturn "web"
            Case #LJV_HYPERLINK : ProcedureReturn "hyperlink"
            Default : ProcedureReturn "text"
         EndSelect
      EndProcedure

      Procedure.s GetAlignName(align.i)
         ; Return string name for alignment
         Protected result.s = ""
         If align & #LJV_LEFT : result = "left" : EndIf
         If align & #LJV_RIGHT : result = "right" : EndIf
         If align & #LJV_CENTER And Not (align & #LJV_LEFT) And Not (align & #LJV_RIGHT) : result = "center" : EndIf
         If align & #LJV_TOP
            If result <> "" : result + " | " : EndIf
            result + "top"
         EndIf
         If align & #LJV_BOTTOM
            If result <> "" : result + " | " : EndIf
            result + "bottom"
         EndIf
         If result = "" : result = "center" : EndIf
         ProcedureReturn result
      EndProcedure

      Procedure.s GenerateViewCode()
         ; Generate LJ2 code representation of current view (JSON-style syntax)
         ; Cell refs are FIXED - A1 is always A1
         Protected code.s, i.i, j.i, ref.s, refEnd.s
         Protected col.i, row.i, sc.i, sr.i, ec.i, er.i
         Protected *cell.stCell
         Protected *grp.stJoinGroup
         Protected hasRanges.i = #False
         Protected hasCells.i = #False
         Protected viewName.s, cols.i, rows.i

         ; Determine view name from gView\name or generate one
         viewName = gView\name
         If viewName = "" : viewName = "myView" : EndIf
         ; Remove spaces and make valid identifier
         viewName = ReplaceString(viewName, " ", "")

         ; Get grid dimensions based on orientation
         If gView\orientation
            cols = gView\rows : rows = gView\cols
         Else
            cols = gView\cols : rows = gView\rows
         EndIf

         ; Start view block
         code = "view " + viewName + " {" + #CRLF$
         code + "    name: " + Chr(34) + gView\name + Chr(34) + #CRLF$
         code + "    grid: " + Str(cols) + ", " + Str(rows) + #CRLF$

         ; Check if we have any named ranges
         For i = 0 To gView\joinGroupCount - 1
            If gView\joinGroups(i)\id > 0 And gView\joinGroups(i)\name <> ""
               hasRanges = #True
               Break
            EndIf
         Next

         ; Output range block if we have named ranges
         If hasRanges
            code + #CRLF$ + "    range {" + #CRLF$
            For i = 0 To gView\joinGroupCount - 1
               *grp = @gView\joinGroups(i)
               If *grp\id > 0 And *grp\name <> ""
                  ; Convert portrait coords to current orientation
                  If gView\orientation
                     sc = *grp\startRow : sr = *grp\startCol
                     ec = *grp\endRow : er = *grp\endCol
                  Else
                     sc = *grp\startCol : sr = *grp\startRow
                     ec = *grp\endCol : er = *grp\endRow
                  EndIf
                  ref = Chr('A' + sc) + Str(sr + 1)
                  refEnd = Chr('A' + ec) + Str(er + 1)
                  code + "        " + Chr(34) + ref + "-" + refEnd + Chr(34) + ": " + Chr(34) + *grp\name + Chr(34) + #CRLF$
               EndIf
            Next
            code + "    }" + #CRLF$
         EndIf

         ; Check if we have any cells with gadgets
         For i = 0 To gView\totalCells - 1
            If gView\cells(i)\gadgetCount > 0
               hasCells = #True
               Break
            EndIf
         Next

         ; Output cell block
         If hasCells
            code + #CRLF$ + "    cell {" + #CRLF$
            For i = 0 To gView\totalCells - 1
               *cell = @gView\cells(i)
               If *cell\gadgetCount > 0
                  ; Skip slave cells - master handles the range
                  If *cell\joinGroup > 0 And Not *cell\isMaster
                     Continue
                  EndIf

                  ; Convert portrait coords to current orientation
                  If gView\orientation
                     col = *cell\row : row = *cell\col
                  Else
                     col = *cell\col : row = *cell\row
                  EndIf
                  ref = Chr('A' + col) + Str(row + 1)

                  ; Check if part of a named join group - use name instead of cell ref
                  Protected cellKey.s = ref
                  If *cell\joinGroup > 0 And *cell\isMaster
                     For j = 0 To gView\joinGroupCount - 1
                        If gView\joinGroups(j)\id = *cell\joinGroup
                           *grp = @gView\joinGroups(j)
                           If *grp\name <> ""
                              cellKey = *grp\name
                           Else
                              ; Unnamed range - use "A1-B2" format
                              If gView\orientation
                                 ec = *grp\endRow : er = *grp\endCol
                              Else
                                 ec = *grp\endCol : er = *grp\endRow
                              EndIf
                              refEnd = Chr('A' + ec) + Str(er + 1)
                              cellKey = ref + "-" + refEnd
                           EndIf
                           Break
                        EndIf
                     Next
                  EndIf

                  ; Output cell definition
                  code + "        " + Chr(34) + cellKey + Chr(34) + ": {" + #CRLF$

                  ; Output first gadget properties (primary gadget)
                  If *cell\gadgetCount > 0
                     code + "            type: " + GetGadgetTypeName(*cell\gadgets(0)\type) + #CRLF$
                     code + "            value: " + Chr(34) + *cell\gadgets(0)\text + Chr(34) + #CRLF$
                     code + "            align: " + GetAlignName(*cell\gadgets(0)\align) + #CRLF$
                     ; Size (only if not default medium)
                     Protected szName.s = ""
                     Select *cell\gadgets(0)\size
                        Case 0 : szName = "small"
                        Case 2 : szName = "large"
                        Case 3 : szName = "xlarge"
                     EndSelect
                     If szName <> ""
                        code + "            size: " + szName + #CRLF$
                     EndIf
                     ; Style (only if set)
                     If *cell\gadgets(0)\bold
                        code + "            bold: true" + #CRLF$
                     EndIf
                     If *cell\gadgets(0)\italic
                        code + "            italic: true" + #CRLF$
                     EndIf
                     ; Colors (only if non-default)
                     If *cell\gadgets(0)\fgColor >= 0
                        code + "            color: #" + RSet(Hex(*cell\gadgets(0)\fgColor, #PB_Long), 6, "0") + #CRLF$
                     EndIf
                     If *cell\gadgets(0)\bgColor >= 0
                        code + "            bgColor: #" + RSet(Hex(*cell\gadgets(0)\bgColor, #PB_Long), 6, "0") + #CRLF$
                     EndIf
                  EndIf

                  ; Output flags if set
                  If *cell\lockCorner
                     code + "            lockCorner: true" + #CRLF$
                  EndIf
                  If *cell\visible
                     code + "            visible: true" + #CRLF$
                  EndIf

                  ; Output event handlers if set
                  If *cell\gadgetCount > 0
                     Protected evts.i = *cell\gadgets(0)\events
                     Protected hnd.s = *cell\gadgets(0)\handler
                     If hnd = "" : hnd = "on" + cellKey : EndIf  ; Default handler name
                     If evts & #LJV_EVT_TAP
                        code + "            onTap: " + hnd + "Tap" + #CRLF$
                     EndIf
                     If evts & #LJV_EVT_SWIPE
                        code + "            onSwipe: " + hnd + "Swipe" + #CRLF$
                     EndIf
                     If evts & #LJV_EVT_DRAG
                        code + "            onDrag: " + hnd + "Drag" + #CRLF$
                     EndIf
                     If evts & #LJV_EVT_LONGPRESS
                        code + "            onLongPress: " + hnd + "LongPress" + #CRLF$
                     EndIf
                  EndIf

                  code + "        }" + #CRLF$
               EndIf
            Next
            code + "    }" + #CRLF$
         EndIf

         code + "}" + #CRLF$

         ProcedureReturn code
      EndProcedure

      Procedure UpdateCodeDisplay()
         Protected code.s
         code = GenerateViewCode()
         If code <> gLastCode
            gLastCode = code
            If IsGadget(#DEBUG_EDITOR_CODE)
               SetGadgetText(#DEBUG_EDITOR_CODE, code)
            EndIf
            ; Auto-copy to clipboard
            SetClipboardText(code)
         EndIf
      EndProcedure

      ; Color constants for UI styling
      #CLR_HEADER_BG    = $D07020     ; Dark blue header
      #CLR_HEADER_FG    = $FFFFFF     ; White text
      #CLR_SECTION_BG   = $F5F0E8     ; Light warm gray
      #CLR_ACCENT       = $E08040     ; Orange accent
      #CLR_BTN_ACTIVE   = $80C080     ; Green for active buttons
      #CLR_BTN_NORMAL   = $F0F0F0     ; Default button
      #CLR_INPUT_BG     = $FFFFFF     ; White input
      #CLR_DELETE       = $6060E0     ; Red-ish for delete
      #CLR_COLLAPSE_BG  = $A08060     ; Collapsible header

      Procedure UpdateSectionLayout()
         ; Reposition sections based on collapsed state
         Protected y.i = 90  ; After VIEW CONTROLS (fixed)

         ; Selection section
         SetGadgetAttribute(#DEBUG_HDR_SELECTION, #PB_Button_Image, 0)
         If gCollapseSelection
            SetGadgetText(#DEBUG_HDR_SELECTION, Chr($25B6) + " SELECTION")  ; ▶
            HideGadget(#DEBUG_CNT_SELECTION, #True)
         Else
            SetGadgetText(#DEBUG_HDR_SELECTION, Chr($25BC) + " SELECTION")  ; ▼
            HideGadget(#DEBUG_CNT_SELECTION, #False)
         EndIf
         ResizeGadget(#DEBUG_HDR_SELECTION, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         y + 24
         ResizeGadget(#DEBUG_CNT_SELECTION, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         If Not gCollapseSelection : y + #SEC_HEIGHT_SELECTION : EndIf

         ; Gadget Properties section
         If gCollapseGadget
            SetGadgetText(#DEBUG_HDR_GADGET, Chr($25B6) + " GADGET PROPERTIES")
            HideGadget(#DEBUG_CNT_GADGET, #True)
         Else
            SetGadgetText(#DEBUG_HDR_GADGET, Chr($25BC) + " GADGET PROPERTIES")
            HideGadget(#DEBUG_CNT_GADGET, #False)
         EndIf
         ResizeGadget(#DEBUG_HDR_GADGET, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         y + 24
         ResizeGadget(#DEBUG_CNT_GADGET, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         If Not gCollapseGadget : y + #SEC_HEIGHT_GADGET : EndIf

         ; Cell Flags section
         If gCollapseFlags
            SetGadgetText(#DEBUG_HDR_FLAGS, Chr($25B6) + " CELL FLAGS")
            HideGadget(#DEBUG_CNT_FLAGS, #True)
         Else
            SetGadgetText(#DEBUG_HDR_FLAGS, Chr($25BC) + " CELL FLAGS")
            HideGadget(#DEBUG_CNT_FLAGS, #False)
         EndIf
         ResizeGadget(#DEBUG_HDR_FLAGS, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         y + 24
         ResizeGadget(#DEBUG_CNT_FLAGS, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         If Not gCollapseFlags : y + #SEC_HEIGHT_FLAGS : EndIf

         ; Events section
         If gCollapseEvents
            SetGadgetText(#DEBUG_HDR_EVENTS, Chr($25B6) + " EVENTS")
            HideGadget(#DEBUG_CNT_EVENTS, #True)
         Else
            SetGadgetText(#DEBUG_HDR_EVENTS, Chr($25BC) + " EVENTS")
            HideGadget(#DEBUG_CNT_EVENTS, #False)
         EndIf
         ResizeGadget(#DEBUG_HDR_EVENTS, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         y + 24
         ResizeGadget(#DEBUG_CNT_EVENTS, #PB_Ignore, y, #PB_Ignore, #PB_Ignore)
         If Not gCollapseEvents : y + #SEC_HEIGHT_EVENTS : EndIf

         ; Generated Code section (fixed, always at bottom)
         y + 4  ; Small gap
         ; Move code header and editor
         Protected codeHdr.i = GetGadgetData(#DEBUG_EDITOR_CODE)
         If codeHdr : ResizeGadget(codeHdr, #PB_Ignore, y, #PB_Ignore, #PB_Ignore) : EndIf
         ResizeGadget(#DEBUG_EDITOR_CODE, #PB_Ignore, y + 24, #PB_Ignore, #PB_Ignore)

         ; Resize window to fit
         Protected newHeight.i = y + 24 + 155  ; Header + editor + margin
         ResizeWindow(gDebugWindow, #PB_Ignore, #PB_Ignore, #PB_Ignore, newHeight)
      EndProcedure

      Procedure ShowDebugPanel()
         ; Create debug control window - V02 with collapsible sections
         Protected y.i, cy.i, hdrGadget.i
         If gDebugWindow And IsWindow(gDebugWindow)
            ProcedureReturn
         EndIf

         gDebugWindow = OpenWindow(#PB_Any, 10, 10, 320, 700, "View Properties",
                                    #PB_Window_SystemMenu | #PB_Window_Tool)
         If gDebugWindow
            SetWindowColor(gDebugWindow, RGB(245, 245, 250))
            y = 0

            ; === VIEW CONTROLS (non-collapsible) ===
            hdrGadget = TextGadget(#PB_Any, 0, y, 320, 24, "  VIEW CONTROLS")
            SetGadgetColor(hdrGadget, #PB_Gadget_BackColor, #CLR_HEADER_BG)
            SetGadgetColor(hdrGadget, #PB_Gadget_FrontColor, #CLR_HEADER_FG)
            y + 26

            TextGadget(#DEBUG_LBL_SEED, 10, y + 3, 40, 20, "Seed:")
            StringGadget(#DEBUG_INPUT_SEED, 50, y, 70, 24, Str(gView\seed))
            SetGadgetColor(#DEBUG_INPUT_SEED, #PB_Gadget_BackColor, #CLR_INPUT_BG)
            ButtonGadget(#DEBUG_BTN_RANDOM, 125, y, 60, 24, "Random")
            SetGadgetColor(#DEBUG_BTN_RANDOM, #PB_Gadget_BackColor, #CLR_ACCENT)
            ButtonGadget(#DEBUG_BTN_ROTATE, 190, y, 120, 24, "Rotate 90")
            y + 28

            If gView\orientation = 0
               TextGadget(#DEBUG_LBL_ORIENT, 10, y, 300, 18, "Portrait (" + Str(gView\width) + "x" + Str(gView\height) + ")")
            Else
               TextGadget(#DEBUG_LBL_ORIENT, 10, y, 300, 18, "Landscape (" + Str(gView\width) + "x" + Str(gView\height) + ")")
            EndIf
            SetGadgetColor(#DEBUG_LBL_ORIENT, #PB_Gadget_FrontColor, RGB(80, 80, 120))
            y + 22

            ; === SELECTION (collapsible) ===
            ButtonGadget(#DEBUG_HDR_SELECTION, 0, y, 320, 22, Chr($25BC) + " SELECTION", 0)
            SetGadgetColor(#DEBUG_HDR_SELECTION, #PB_Gadget_BackColor, RGB(100, 120, 140))
            SetGadgetColor(#DEBUG_HDR_SELECTION, #PB_Gadget_FrontColor, #CLR_HEADER_FG)
            y + 24

            ContainerGadget(#DEBUG_CNT_SELECTION, 0, y, 320, #SEC_HEIGHT_SELECTION)
            SetGadgetColor(#DEBUG_CNT_SELECTION, #PB_Gadget_BackColor, RGB(240, 245, 250))
            cy = 4
            TextGadget(#DEBUG_LBL_SELECT, 10, cy, 300, 16, "Click cell to set start")
            SetGadgetColor(#DEBUG_LBL_SELECT, #PB_Gadget_FrontColor, RGB(60, 100, 60))
            cy + 20
            TextGadget(#PB_Any, 10, cy + 3, 35, 18, "Start:")
            StringGadget(#DEBUG_INPUT_START, 48, cy, 48, 22, "")
            SetGadgetColor(#DEBUG_INPUT_START, #PB_Gadget_BackColor, RGB(220, 255, 220))
            TextGadget(#PB_Any, 105, cy + 3, 28, 18, "End:")
            StringGadget(#DEBUG_INPUT_END, 135, cy, 48, 22, "")
            SetGadgetColor(#DEBUG_INPUT_END, #PB_Gadget_BackColor, RGB(255, 220, 220))
            cy + 26
            ButtonGadget(#DEBUG_BTN_MERGE, 10, cy, 85, 24, "Merge")
            SetGadgetColor(#DEBUG_BTN_MERGE, #PB_Gadget_BackColor, RGB(200, 220, 255))
            DisableGadget(#DEBUG_BTN_MERGE, #True)
            ButtonGadget(#DEBUG_BTN_UNMERGE, 100, cy, 85, 24, "Unmerge")
            DisableGadget(#DEBUG_BTN_UNMERGE, #True)
            CloseGadgetList()
            y + #SEC_HEIGHT_SELECTION

            ; === GADGET PROPERTIES (collapsible) ===
            ButtonGadget(#DEBUG_HDR_GADGET, 0, y, 320, 22, Chr($25BC) + " GADGET PROPERTIES", 0)
            SetGadgetColor(#DEBUG_HDR_GADGET, #PB_Gadget_BackColor, #CLR_HEADER_BG)
            SetGadgetColor(#DEBUG_HDR_GADGET, #PB_Gadget_FrontColor, #CLR_HEADER_FG)
            y + 24

            ContainerGadget(#DEBUG_CNT_GADGET, 0, y, 320, #SEC_HEIGHT_GADGET)
            SetGadgetColor(#DEBUG_CNT_GADGET, #PB_Gadget_BackColor, RGB(250, 248, 245))
            cy = 4
            ; Type row
            TextGadget(#DEBUG_LBL_TYPE, 8, cy + 3, 32, 18, "Type:")
            ComboBoxGadget(#DEBUG_COMBO_TYPE, 42, cy, 145, 22)
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "(none)")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "text")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "button")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "input")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "checkbox")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "option")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "combo")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "list")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "spin")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "track")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "progress")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "scroll")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "image")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "canvas")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "container")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "panel")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "frame")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "splitter")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "date")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "calendar")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "editor")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "scintilla")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "listicon")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "tree")
            AddGadgetItem(#DEBUG_COMBO_TYPE, -1, "web")
            SetGadgetState(#DEBUG_COMBO_TYPE, 0)
            ButtonGadget(#DEBUG_BTN_ADD_GADGET, 195, cy, 55, 22, "+Add")
            SetGadgetColor(#DEBUG_BTN_ADD_GADGET, #PB_Gadget_BackColor, RGB(180, 230, 180))
            ButtonGadget(#DEBUG_BTN_DEL_GADGET, 255, cy, 55, 22, "-Del")
            SetGadgetColor(#DEBUG_BTN_DEL_GADGET, #PB_Gadget_BackColor, RGB(255, 180, 180))
            cy + 26
            ; Value row
            TextGadget(#DEBUG_LBL_VALUE, 8, cy + 3, 32, 18, "Value:")
            StringGadget(#DEBUG_INPUT_VALUE, 42, cy, 268, 22, "")
            SetGadgetColor(#DEBUG_INPUT_VALUE, #PB_Gadget_BackColor, #CLR_INPUT_BG)
            cy + 26
            ; Align row
            TextGadget(#DEBUG_LBL_ALIGN, 8, cy + 3, 32, 18, "Align:")
            ButtonGadget(#DEBUG_BTN_ALIGN_L, 42, cy, 28, 22, "L")
            ButtonGadget(#DEBUG_BTN_ALIGN_C, 72, cy, 28, 22, "C")
            ButtonGadget(#DEBUG_BTN_ALIGN_R, 102, cy, 28, 22, "R")
            TextGadget(#PB_Any, 138, cy + 3, 12, 18, "|")
            ButtonGadget(#DEBUG_BTN_ALIGN_T, 155, cy, 28, 22, "T")
            ButtonGadget(#DEBUG_BTN_ALIGN_M, 185, cy, 28, 22, "M")
            ButtonGadget(#DEBUG_BTN_ALIGN_B, 215, cy, 28, 22, "B")
            cy + 26
            ; Size/Style row
            TextGadget(#DEBUG_LBL_SIZE, 8, cy + 2, 32, 18, "Size:")
            OptionGadget(#DEBUG_OPT_SIZE_S, 42, cy, 38, 18, "S")
            OptionGadget(#DEBUG_OPT_SIZE_M, 82, cy, 38, 18, "M")
            OptionGadget(#DEBUG_OPT_SIZE_L, 122, cy, 38, 18, "L")
            OptionGadget(#DEBUG_OPT_SIZE_XL, 162, cy, 42, 18, "XL")
            SetGadgetState(#DEBUG_OPT_SIZE_M, #True)
            CheckBoxGadget(#DEBUG_CHK_BOLD, 220, cy, 38, 18, "B")
            SetGadgetColor(#DEBUG_CHK_BOLD, #PB_Gadget_FrontColor, RGB(0, 0, 180))
            CheckBoxGadget(#DEBUG_CHK_ITALIC, 260, cy, 38, 18, "I")
            SetGadgetColor(#DEBUG_CHK_ITALIC, #PB_Gadget_FrontColor, RGB(120, 0, 120))
            cy + 24
            ; Nudge row
            TextGadget(#DEBUG_LBL_NUDGE, 8, cy + 2, 40, 18, "Nudge:")
            CheckBoxGadget(#DEBUG_CHK_NUDGE_L, 52, cy, 32, 18, "<")
            CheckBoxGadget(#DEBUG_CHK_NUDGE_R, 88, cy, 32, 18, ">")
            CheckBoxGadget(#DEBUG_CHK_NUDGE_U, 128, cy, 32, 18, "^")
            CheckBoxGadget(#DEBUG_CHK_NUDGE_D, 164, cy, 32, 18, "v")
            cy + 24
            ; Gadget colors row
            TextGadget(#DEBUG_LBL_GCOLORS, 8, cy + 2, 42, 18, "Colors:")
            ButtonGadget(#DEBUG_BTN_FG_COLOR, 52, cy, 50, 20, "Text")
            SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_BackColor, RGB(0, 0, 0))
            SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_FrontColor, RGB(255, 255, 255))
            ButtonGadget(#DEBUG_BTN_BG_COLOR, 106, cy, 50, 20, "Back")
            SetGadgetColor(#DEBUG_BTN_BG_COLOR, #PB_Gadget_BackColor, RGB(240, 240, 240))
            CheckBoxGadget(#DEBUG_CHK_BG_TRANS, 162, cy, 55, 18, "Trans")
            CloseGadgetList()
            y + #SEC_HEIGHT_GADGET

            ; === CELL FLAGS (collapsible) ===
            ButtonGadget(#DEBUG_HDR_FLAGS, 0, y, 320, 22, Chr($25BC) + " CELL FLAGS", 0)
            SetGadgetColor(#DEBUG_HDR_FLAGS, #PB_Gadget_BackColor, RGB(100, 120, 140))
            SetGadgetColor(#DEBUG_HDR_FLAGS, #PB_Gadget_FrontColor, #CLR_HEADER_FG)
            y + 24

            ContainerGadget(#DEBUG_CNT_FLAGS, 0, y, 320, #SEC_HEIGHT_FLAGS)
            SetGadgetColor(#DEBUG_CNT_FLAGS, #PB_Gadget_BackColor, RGB(245, 248, 250))
            cy = 6
            CheckBoxGadget(#DEBUG_CHK_CORNER, 10, cy, 95, 18, "Lock Corner")
            CheckBoxGadget(#DEBUG_CHK_VISIBLE, 110, cy, 70, 18, "Visible")
            SetGadgetState(#DEBUG_CHK_VISIBLE, #True)
            ButtonGadget(#DEBUG_BTN_COLOR, 190, cy, 55, 20, "Color")
            CheckBoxGadget(#DEBUG_CHK_COLORLK, 250, cy, 55, 18, "Lock")
            CloseGadgetList()
            y + #SEC_HEIGHT_FLAGS

            ; === EVENTS (collapsible) ===
            ButtonGadget(#DEBUG_HDR_EVENTS, 0, y, 320, 22, Chr($25BC) + " EVENTS", 0)
            SetGadgetColor(#DEBUG_HDR_EVENTS, #PB_Gadget_BackColor, RGB(140, 100, 120))
            SetGadgetColor(#DEBUG_HDR_EVENTS, #PB_Gadget_FrontColor, #CLR_HEADER_FG)
            y + 24

            ContainerGadget(#DEBUG_CNT_EVENTS, 0, y, 320, #SEC_HEIGHT_EVENTS)
            SetGadgetColor(#DEBUG_CNT_EVENTS, #PB_Gadget_BackColor, RGB(252, 248, 250))
            cy = 4
            CheckBoxGadget(#DEBUG_CHK_EVT_TAP, 10, cy, 50, 18, "Tap")
            CheckBoxGadget(#DEBUG_CHK_EVT_SWIPE, 65, cy, 60, 18, "Swipe")
            CheckBoxGadget(#DEBUG_CHK_EVT_DRAG, 130, cy, 50, 18, "Drag")
            CheckBoxGadget(#DEBUG_CHK_EVT_LONG, 185, cy, 85, 18, "LongPress")
            cy + 22
            TextGadget(#DEBUG_LBL_HANDLER, 10, cy + 2, 50, 18, "Handler:")
            StringGadget(#DEBUG_INPUT_HANDLER, 62, cy, 130, 20, "")
            SetGadgetColor(#DEBUG_INPUT_HANDLER, #PB_Gadget_BackColor, RGB(255, 255, 230))
            CloseGadgetList()
            y + #SEC_HEIGHT_EVENTS

            ; === GENERATED CODE (non-collapsible) ===
            y + 4
            hdrGadget = TextGadget(#PB_Any, 0, y, 320, 22, "  GENERATED CODE (auto-copied)")
            SetGadgetColor(hdrGadget, #PB_Gadget_BackColor, #CLR_HEADER_BG)
            SetGadgetColor(hdrGadget, #PB_Gadget_FrontColor, #CLR_HEADER_FG)
            y + 24

            EditorGadget(#DEBUG_EDITOR_CODE, 5, y, 310, 150, #PB_Editor_ReadOnly)
            SetGadgetData(#DEBUG_EDITOR_CODE, hdrGadget)  ; Store header ID for repositioning
            SetGadgetColor(#DEBUG_EDITOR_CODE, #PB_Gadget_BackColor, RGB(40, 44, 52))
            SetGadgetColor(#DEBUG_EDITOR_CODE, #PB_Gadget_FrontColor, RGB(200, 220, 180))
            SetGadgetFont(#DEBUG_EDITOR_CODE, LoadFont(#PB_Any, "Consolas", 9))

            UpdateCodeDisplay()
            DisableCellProps(#True)
         EndIf
      EndProcedure

      Procedure CloseDebugPanel()
         If gDebugWindow And IsWindow(gDebugWindow)
            CloseWindow(gDebugWindow)
            gDebugWindow = 0
         EndIf
      EndProcedure

      Procedure UpdateDebugPanel()
         ; Refresh seed display and orientation label
         If gDebugWindow And IsWindow(gDebugWindow)
            SetGadgetText(#DEBUG_INPUT_SEED, Str(gView\seed))
            If gView\orientation = 0
               SetGadgetText(#DEBUG_LBL_ORIENT, "Orientation: Portrait (" + Str(gView\width) + "x" + Str(gView\height) + ")")
            Else
               SetGadgetText(#DEBUG_LBL_ORIENT, "Orientation: Landscape (" + Str(gView\width) + "x" + Str(gView\height) + ")")
            EndIf
            UpdateCodeDisplay()
         EndIf
      EndProcedure

      Procedure ApplySeedChange()
         ; Read seed from input and refresh view
         Protected newSeed.i, i.i

         If gDebugWindow And IsWindow(gDebugWindow)
            newSeed = Val(GetGadgetText(#DEBUG_INPUT_SEED))
            If newSeed <> gView\seed
               gView\seed = newSeed
               ; Regenerate cell colors with new seed (skip locked colors)
               For i = 0 To gView\totalCells - 1
                  If Not gView\cells(i)\colorLocked
                     gView\cells(i)\color = GenerateColor(gView\seed, i)
                  EndIf
               Next
               ; Refresh view
               ViewShow(gView\width, gView\height)
               UpdateCodeDisplay()
               UpdateCellPropsDisplay()  ; Update color button
            EndIf
         EndIf
      EndProcedure

      Procedure UnmergeGroup(groupID.i)
         ; Unmerge a join group - restore cells to individual state
         Protected i.i, j.i, idx.i
         Protected *grp.stJoinGroup
         Protected grpIdx.i = -1

         ; Find the group
         For i = 0 To gView\joinGroupCount - 1
            If gView\joinGroups(i)\id = groupID
               grpIdx = i
               *grp = @gView\joinGroups(i)
               Break
            EndIf
         Next

         If grpIdx < 0
            ProcedureReturn
         EndIf

         ; Clear join group from all cells in the range
         For j = *grp\startRow To *grp\endRow
            For i = *grp\startCol To *grp\endCol
               idx = j * gView\cols + i
               gView\cells(idx)\joinGroup = 0
               gView\cells(idx)\masterCell = 0
               gView\cells(idx)\isMaster = #False
            Next
         Next

         ; Remove the group (mark as invalid)
         gView\joinGroups(grpIdx)\id = 0
      EndProcedure

      Procedure MergeCellsWithInheritance(startCol.i, startRow.i, endCol.i, endRow.i)
         ; Merge cells while preserving gadgets from populated cells
         Protected i.i, j.i, idx.i, masterIdx.i, groupID.i
         Protected masterColor.i = 0
         Protected foundPopulated.i = #False
         Protected gIdx.i, k.i
         Protected *srcCell.stCell
         Protected *masterCell.stCell

         ; Ensure start <= end
         If endCol < startCol : Swap startCol, endCol : EndIf
         If endRow < startRow : Swap startRow, endRow : EndIf

         ; Clamp to view bounds
         If endCol >= gView\cols : endCol = gView\cols - 1 : EndIf
         If endRow >= gView\rows : endRow = gView\rows - 1 : EndIf

         ; Create join group
         groupID = gView\joinGroupCount + 1
         gView\joinGroupCount + 1

         If gView\joinGroupCount > ArraySize(gView\joinGroups())
            ReDim gView\joinGroups(gView\joinGroupCount + 8)
         EndIf

         masterIdx = startRow * gView\cols + startCol

         gView\joinGroups(groupID - 1)\id = groupID
         gView\joinGroups(groupID - 1)\startCol = startCol
         gView\joinGroups(groupID - 1)\startRow = startRow
         gView\joinGroups(groupID - 1)\endCol = endCol
         gView\joinGroups(groupID - 1)\endRow = endRow
         gView\joinGroups(groupID - 1)\masterIdx = masterIdx

         *masterCell = @gView\cells(masterIdx)

         ; Find first populated cell and collect all gadgets
         For j = startRow To endRow
            For i = startCol To endCol
               idx = j * gView\cols + i
               *srcCell = @gView\cells(idx)

               ; Mark cell as part of group
               *srcCell\joinGroup = groupID
               *srcCell\masterCell = masterIdx
               *srcCell\isMaster = Bool(idx = masterIdx)

               ; Take color from first populated cell
               If *srcCell\gadgetCount > 0 And Not foundPopulated
                  masterColor = *srcCell\color
                  foundPopulated = #True
               EndIf

               ; Copy gadgets to master cell (if not already master)
               If idx <> masterIdx And *srcCell\gadgetCount > 0
                  For k = 0 To *srcCell\gadgetCount - 1
                     gIdx = *masterCell\gadgetCount
                     If gIdx < #VIEW_MAX_GADGETS
                        If gIdx > ArraySize(*masterCell\gadgets())
                           ReDim *masterCell\gadgets(gIdx + 4)
                        EndIf
                        *masterCell\gadgets(gIdx)\type = *srcCell\gadgets(k)\type
                        *masterCell\gadgets(gIdx)\text = *srcCell\gadgets(k)\text
                        *masterCell\gadgets(gIdx)\align = *srcCell\gadgets(k)\align
                        *masterCell\gadgets(gIdx)\size = *srcCell\gadgets(k)\size
                        *masterCell\gadgets(gIdx)\bold = *srcCell\gadgets(k)\bold
                        *masterCell\gadgets(gIdx)\italic = *srcCell\gadgets(k)\italic
                        *masterCell\gadgets(gIdx)\fgColor = *srcCell\gadgets(k)\fgColor
                        *masterCell\gadgets(gIdx)\bgColor = *srcCell\gadgets(k)\bgColor
                        *masterCell\gadgets(gIdx)\events = *srcCell\gadgets(k)\events
                        *masterCell\gadgets(gIdx)\handler = *srcCell\gadgets(k)\handler
                        *masterCell\gadgetCount + 1
                     EndIf
                  Next
                  ; Clear source cell gadgets
                  *srcCell\gadgetCount = 0
               EndIf
            Next
         Next

         ; Apply color from populated cell to master
         If foundPopulated
            *masterCell\color = masterColor
         EndIf
      EndProcedure

      Procedure HandleDebugEvent(event.i, eventWindow.i, eventGadget.i)
         ; Handle debug panel events, returns #True if handled
         Protected randomSeed.i, i.i
         Protected newW.i, newH.i
         Protected startRef.s, endRef.s
         Protected msc.i, msr.i, mec.i, mer.i   ; Merge coords (portrait)
         Protected jsc.i, jsr.i, jec.i, jer.i   ; Join coords (portrait)

         ; Debug all events going to debug window
         If eventWindow = gDebugWindow And event = #PB_Event_Gadget
            Debug "HandleDebugEvent: gadget=" + Str(eventGadget) + " (#DEBUG_CHK_CORNER=" + Str(#DEBUG_CHK_CORNER) + ")"
         EndIf

         If eventWindow = gDebugWindow
            Select event
               Case #PB_Event_CloseWindow
                  CloseDebugPanel()
                  ProcedureReturn #True

               Case #PB_Event_Gadget
                  Select eventGadget
                     Case #DEBUG_BTN_ROTATE
                        ; Rotate 90 degrees - swap dimensions
                        ; Cell refs are FIXED - A1 is always A1
                        ; Selection stays the same, but may be outside new bounds
                        gView\orientation = 1 - gView\orientation
                        newW = gView\height
                        newH = gView\width
                        ; Clear selection if outside new effective bounds
                        Protected newEffCols.i = GetEffectiveCols()
                        Protected newEffRows.i = GetEffectiveRows()
                        If gSelectStartCol >= newEffCols Or gSelectStartRow >= newEffRows
                           ClearSelection()
                        ElseIf gSelectEndCol >= newEffCols Or gSelectEndRow >= newEffRows
                           ClearSelection()
                        EndIf
                        ViewShow(newW, newH)
                        UpdateSelectionDisplay()
                        UpdateDebugPanel()
                        ProcedureReturn #True

                     Case #DEBUG_HDR_SELECTION
                        ; Toggle Selection section
                        gCollapseSelection = 1 - gCollapseSelection
                        UpdateSectionLayout()
                        ProcedureReturn #True

                     Case #DEBUG_HDR_GADGET
                        ; Toggle Gadget Properties section
                        gCollapseGadget = 1 - gCollapseGadget
                        UpdateSectionLayout()
                        ProcedureReturn #True

                     Case #DEBUG_HDR_FLAGS
                        ; Toggle Cell Flags section
                        gCollapseFlags = 1 - gCollapseFlags
                        UpdateSectionLayout()
                        ProcedureReturn #True

                     Case #DEBUG_HDR_EVENTS
                        ; Toggle Events section
                        gCollapseEvents = 1 - gCollapseEvents
                        UpdateSectionLayout()
                        ProcedureReturn #True

                     Case #DEBUG_BTN_RANDOM
                        ; Generate random seed
                        randomSeed = Random(999999)
                        gView\seed = randomSeed
                        SetGadgetText(#DEBUG_INPUT_SEED, Str(randomSeed))
                        ; Regenerate cell colors (skip locked colors)
                        For i = 0 To gView\totalCells - 1
                           If Not gView\cells(i)\colorLocked
                              gView\cells(i)\color = GenerateColor(gView\seed, i)
                           EndIf
                        Next
                        ViewShow(gView\width, gView\height)
                        UpdateCodeDisplay()
                        UpdateCellPropsDisplay()  ; Update color button
                        ProcedureReturn #True

                     Case #DEBUG_INPUT_SEED
                        ; Seed changed - apply on Enter
                        ApplySeedChange()
                        ProcedureReturn #True

                     Case #DEBUG_BTN_MERGE
                        ; Merge cells with property inheritance
                        ; Cell refs are FIXED - selection coords are the cell refs directly
                        If gSelectStartCol >= 0 And gSelectEndCol >= 0
                           MergeCellsWithInheritance(gSelectStartCol, gSelectStartRow, gSelectEndCol, gSelectEndRow)
                           ClearSelection()
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_UNMERGE
                        ; Unmerge selected merge group
                        If gSelectedMergeGroup > 0
                           UnmergeGroup(gSelectedMergeGroup)
                           ClearSelection()
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     ; Cell property controls
                     Case #DEBUG_OPT_SIZE_S, #DEBUG_OPT_SIZE_M, #DEBUG_OPT_SIZE_L, #DEBUG_OPT_SIZE_XL
                        ; Size option changed
                        If gSelectStartCol >= 0
                           Protected sizeVal.i = 1  ; Default medium
                           If GetGadgetState(#DEBUG_OPT_SIZE_S) : sizeVal = 0 : EndIf
                           If GetGadgetState(#DEBUG_OPT_SIZE_L) : sizeVal = 2 : EndIf
                           If GetGadgetState(#DEBUG_OPT_SIZE_XL) : sizeVal = 3 : EndIf
                           Protected sIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected sGIdx.i
                           For sGIdx = 0 To gView\cells(sIdx)\gadgetCount - 1
                              gView\cells(sIdx)\gadgets(sGIdx)\size = sizeVal
                           Next
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_CHK_BOLD, #DEBUG_CHK_ITALIC
                        ; Style changed - apply to ALL gadgets
                        If gSelectStartCol >= 0
                           Protected stIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected stBold.i = GetGadgetState(#DEBUG_CHK_BOLD)
                           Protected stItalic.i = GetGadgetState(#DEBUG_CHK_ITALIC)
                           Protected stGIdx.i
                           For stGIdx = 0 To gView\cells(stIdx)\gadgetCount - 1
                              gView\cells(stIdx)\gadgets(stGIdx)\bold = stBold
                              gView\cells(stIdx)\gadgets(stGIdx)\italic = stItalic
                           Next
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_CHK_NUDGE_L, #DEBUG_CHK_NUDGE_R, #DEBUG_CHK_NUDGE_U, #DEBUG_CHK_NUDGE_D
                        ; Nudge changed - apply to ALL gadgets
                        ; Handle mutual exclusivity
                        If GetGadgetState(#DEBUG_CHK_NUDGE_L) And EventGadget() = #DEBUG_CHK_NUDGE_L
                           SetGadgetState(#DEBUG_CHK_NUDGE_R, #False)
                        EndIf
                        If GetGadgetState(#DEBUG_CHK_NUDGE_R) And EventGadget() = #DEBUG_CHK_NUDGE_R
                           SetGadgetState(#DEBUG_CHK_NUDGE_L, #False)
                        EndIf
                        If GetGadgetState(#DEBUG_CHK_NUDGE_U) And EventGadget() = #DEBUG_CHK_NUDGE_U
                           SetGadgetState(#DEBUG_CHK_NUDGE_D, #False)
                        EndIf
                        If GetGadgetState(#DEBUG_CHK_NUDGE_D) And EventGadget() = #DEBUG_CHK_NUDGE_D
                           SetGadgetState(#DEBUG_CHK_NUDGE_U, #False)
                        EndIf
                        If gSelectStartCol >= 0
                           Protected ndIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected ndAlign.i = 0
                           If GetGadgetState(#DEBUG_CHK_NUDGE_L) : ndAlign | #LJV_TOLEFT : EndIf
                           If GetGadgetState(#DEBUG_CHK_NUDGE_R) : ndAlign | #LJV_TORIGHT : EndIf
                           If GetGadgetState(#DEBUG_CHK_NUDGE_U) : ndAlign | #LJV_UP : EndIf
                           If GetGadgetState(#DEBUG_CHK_NUDGE_D) : ndAlign | #LJV_DOWN : EndIf
                           Protected ndGIdx.i
                           For ndGIdx = 0 To gView\cells(ndIdx)\gadgetCount - 1
                              ; Preserve base alignment, update nudge modifiers
                              Protected baseAlign.i = gView\cells(ndIdx)\gadgets(ndGIdx)\align & $0F
                              gView\cells(ndIdx)\gadgets(ndGIdx)\align = baseAlign | ndAlign
                           Next
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_CHK_CORNER
                        ; Lock corner - set alignment to top-left and apply nudges
                        Debug "=== DEBUG_CHK_CORNER clicked ==="
                        Debug "  gSelectStartCol=" + Str(gSelectStartCol) + " gSelectStartRow=" + Str(gSelectStartRow)
                        If gSelectStartCol >= 0
                           Protected cIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected cMasterIdx.i = cIdx
                           ; If part of join group, propagate to master cell
                           If gView\cells(cIdx)\joinGroup > 0
                              cMasterIdx = gView\cells(cIdx)\masterCell
                              Debug "  Cell is slave, master idx=" + Str(cMasterIdx)
                           EndIf
                           Protected cornerState.i = GetGadgetState(#DEBUG_CHK_CORNER)
                           Debug "  Setting lockCorner=" + Str(cornerState) + " on cell[" + Str(cMasterIdx) + "]"
                           gView\cells(cMasterIdx)\lockCorner = cornerState
                           ; Store the SELECTED cell's position for corner detection
                           ; This is crucial - use the selected cell's position, not the master's
                           If gView\cells(cMasterIdx)\lockCorner
                              gView\cells(cMasterIdx)\lockCornerCol = gSelectStartCol
                              gView\cells(cMasterIdx)\lockCornerRow = gSelectStartRow
                              Debug "  Set lockCornerCol=" + Str(gSelectStartCol) + " lockCornerRow=" + Str(gSelectStartRow)
                           EndIf
                           ; When corner locked, set to top-left alignment
                           If gView\cells(cMasterIdx)\lockCorner And gView\cells(cMasterIdx)\gadgetCount > 0
                              Protected cAlign.i = #LJV_LEFT | #LJV_TOP
                              If GetGadgetState(#DEBUG_CHK_NUDGE_L) : cAlign | #LJV_TOLEFT : EndIf
                              If GetGadgetState(#DEBUG_CHK_NUDGE_R) : cAlign | #LJV_TORIGHT : EndIf
                              If GetGadgetState(#DEBUG_CHK_NUDGE_U) : cAlign | #LJV_UP : EndIf
                              If GetGadgetState(#DEBUG_CHK_NUDGE_D) : cAlign | #LJV_DOWN : EndIf
                              gView\cells(cMasterIdx)\gadgets(0)\align = cAlign
                           EndIf
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_CHK_VISIBLE
                        ; Visible changed
                        If gSelectStartCol >= 0
                           Protected vIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected vMasterIdx.i = vIdx
                           ; If part of join group, propagate to master cell
                           If gView\cells(vIdx)\joinGroup > 0
                              vMasterIdx = gView\cells(vIdx)\masterCell
                           EndIf
                           gView\cells(vMasterIdx)\visible = GetGadgetState(#DEBUG_CHK_VISIBLE)
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_COLOR
                        ; Color picker
                        If gSelectStartCol >= 0
                           Protected colIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected newColor.i = ColorRequester(gView\cells(colIdx)\color)
                           If newColor >= 0
                              gView\cells(colIdx)\color = newColor
                              SetGadgetColor(#DEBUG_BTN_COLOR, #PB_Gadget_BackColor, newColor)
                              ViewShow(gView\width, gView\height)
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_CHK_COLORLK
                        ; Color lock changed
                        If gSelectStartCol >= 0
                           Protected clIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           gView\cells(clIdx)\colorLocked = GetGadgetState(#DEBUG_CHK_COLORLK)
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_FG_COLOR
                        ; Gadget foreground color picker - apply to ALL gadgets
                        If gSelectStartCol >= 0
                           Protected fgIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(fgIdx)\gadgetCount > 0
                              Protected curFg.i = gView\cells(fgIdx)\gadgets(0)\fgColor
                              If curFg < 0 : curFg = RGB(0, 0, 0) : EndIf
                              Protected newFgColor.i = ColorRequester(curFg)
                              If newFgColor >= 0
                                 Protected fgGIdx.i
                                 For fgGIdx = 0 To gView\cells(fgIdx)\gadgetCount - 1
                                    gView\cells(fgIdx)\gadgets(fgGIdx)\fgColor = newFgColor
                                 Next
                                 SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_BackColor, newFgColor)
                                 ; Set contrasting text
                                 If Red(newFgColor) + Green(newFgColor) + Blue(newFgColor) > 384
                                    SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_FrontColor, RGB(0, 0, 0))
                                 Else
                                    SetGadgetColor(#DEBUG_BTN_FG_COLOR, #PB_Gadget_FrontColor, RGB(255, 255, 255))
                                 EndIf
                                 ViewShow(gView\width, gView\height)
                                 UpdateCodeDisplay()
                              EndIf
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_BG_COLOR
                        ; Gadget background color picker - apply to ALL gadgets
                        If gSelectStartCol >= 0
                           Protected bgIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(bgIdx)\gadgetCount > 0
                              Protected curBg.i = gView\cells(bgIdx)\gadgets(0)\bgColor
                              If curBg < 0 : curBg = RGB(240, 240, 240) : EndIf
                              Protected newBgColor.i = ColorRequester(curBg)
                              If newBgColor >= 0
                                 Protected bgGIdx.i
                                 For bgGIdx = 0 To gView\cells(bgIdx)\gadgetCount - 1
                                    gView\cells(bgIdx)\gadgets(bgGIdx)\bgColor = newBgColor
                                 Next
                                 SetGadgetColor(#DEBUG_BTN_BG_COLOR, #PB_Gadget_BackColor, newBgColor)
                                 SetGadgetState(#DEBUG_CHK_BG_TRANS, #False)
                                 ViewShow(gView\width, gView\height)
                                 UpdateCodeDisplay()
                              EndIf
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_CHK_BG_TRANS
                        ; Transparent background checkbox - apply to ALL gadgets
                        If gSelectStartCol >= 0
                           Protected trIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(trIdx)\gadgetCount > 0
                              If GetGadgetState(#DEBUG_CHK_BG_TRANS)
                                 Protected trGIdx.i
                                 For trGIdx = 0 To gView\cells(trIdx)\gadgetCount - 1
                                    gView\cells(trIdx)\gadgets(trGIdx)\bgColor = -1
                                 Next
                                 SetGadgetColor(#DEBUG_BTN_BG_COLOR, #PB_Gadget_BackColor, RGB(240, 240, 240))
                              EndIf
                              ViewShow(gView\width, gView\height)
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_CHK_EVT_TAP, #DEBUG_CHK_EVT_SWIPE, #DEBUG_CHK_EVT_DRAG, #DEBUG_CHK_EVT_LONG
                        ; Event checkbox changed - apply to ALL gadgets
                        If gSelectStartCol >= 0
                           Protected evIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(evIdx)\gadgetCount > 0
                              Protected newEvts.i = 0
                              If GetGadgetState(#DEBUG_CHK_EVT_TAP) : newEvts | #LJV_EVT_TAP : EndIf
                              If GetGadgetState(#DEBUG_CHK_EVT_SWIPE) : newEvts | #LJV_EVT_SWIPE : EndIf
                              If GetGadgetState(#DEBUG_CHK_EVT_DRAG) : newEvts | #LJV_EVT_DRAG : EndIf
                              If GetGadgetState(#DEBUG_CHK_EVT_LONG) : newEvts | #LJV_EVT_LONGPRESS : EndIf
                              Protected evGIdx.i
                              For evGIdx = 0 To gView\cells(evIdx)\gadgetCount - 1
                                 gView\cells(evIdx)\gadgets(evGIdx)\events = newEvts
                              Next
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_INPUT_HANDLER
                        ; Handler name changed - apply to ALL gadgets
                        If gSelectStartCol >= 0
                           Protected hIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected hName.s = GetGadgetText(#DEBUG_INPUT_HANDLER)
                           Protected hGIdx.i
                           For hGIdx = 0 To gView\cells(hIdx)\gadgetCount - 1
                              gView\cells(hIdx)\gadgets(hGIdx)\handler = hName
                           Next
                           If gView\cells(hIdx)\gadgetCount > 0
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_COMBO_TYPE
                        ; Gadget type changed
                        If gSelectStartCol >= 0
                           Protected tyIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected tyState.i = GetGadgetState(#DEBUG_COMBO_TYPE)
                           If tyState = 0
                              ; (none) selected - remove gadget
                              gView\cells(tyIdx)\gadgetCount = 0
                           Else
                              ; Set gadget type (combo index - 1 = type)
                              If gView\cells(tyIdx)\gadgetCount = 0
                                 gView\cells(tyIdx)\gadgetCount = 1
                                 gView\cells(tyIdx)\gadgets(0)\align = #LJV_CENTER
                                 gView\cells(tyIdx)\gadgets(0)\size = 1
                                 gView\cells(tyIdx)\gadgets(0)\fgColor = -1
                                 gView\cells(tyIdx)\gadgets(0)\bgColor = -1
                              EndIf
                              gView\cells(tyIdx)\gadgets(0)\type = tyState - 1
                           EndIf
                           ViewShow(gView\width, gView\height)
                           UpdateCodeDisplay()
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_INPUT_VALUE
                        ; Gadget value changed
                        If gSelectStartCol >= 0
                           Protected valIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(valIdx)\gadgetCount > 0
                              gView\cells(valIdx)\gadgets(0)\text = GetGadgetText(#DEBUG_INPUT_VALUE)
                              ViewShow(gView\width, gView\height)
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_ALIGN_L, #DEBUG_BTN_ALIGN_C, #DEBUG_BTN_ALIGN_R
                        ; Horizontal alignment
                        If gSelectStartCol >= 0
                           Protected ahIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(ahIdx)\gadgetCount > 0
                              Protected ahAlign.i = gView\cells(ahIdx)\gadgets(0)\align & $FC  ; Clear H bits
                              Select EventGadget()
                                 Case #DEBUG_BTN_ALIGN_L : ahAlign | #LJV_LEFT
                                 Case #DEBUG_BTN_ALIGN_C : ; CENTER = 0, already cleared
                                 Case #DEBUG_BTN_ALIGN_R : ahAlign | #LJV_RIGHT
                              EndSelect
                              gView\cells(ahIdx)\gadgets(0)\align = ahAlign
                              ViewShow(gView\width, gView\height)
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_ALIGN_T, #DEBUG_BTN_ALIGN_M, #DEBUG_BTN_ALIGN_B
                        ; Vertical alignment
                        If gSelectStartCol >= 0
                           Protected avIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(avIdx)\gadgetCount > 0
                              Protected avAlign.i = gView\cells(avIdx)\gadgets(0)\align & $F3  ; Clear V bits
                              Select EventGadget()
                                 Case #DEBUG_BTN_ALIGN_T : avAlign | #LJV_TOP
                                 Case #DEBUG_BTN_ALIGN_M : ; MIDDLE = 0, already cleared
                                 Case #DEBUG_BTN_ALIGN_B : avAlign | #LJV_BOTTOM
                              EndSelect
                              gView\cells(avIdx)\gadgets(0)\align = avAlign
                              ViewShow(gView\width, gView\height)
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_ADD_GADGET
                        ; Add gadget to cell (allows multiple gadgets)
                        If gSelectStartCol >= 0
                           Protected addIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           Protected addGIdx.i = gView\cells(addIdx)\gadgetCount
                           If addGIdx < #VIEW_MAX_GADGETS
                              If addGIdx > ArraySize(gView\cells(addIdx)\gadgets())
                                 ReDim gView\cells(addIdx)\gadgets(addGIdx + 4)
                              EndIf
                              gView\cells(addIdx)\gadgets(addGIdx)\type = #LJV_TEXT
                              gView\cells(addIdx)\gadgets(addGIdx)\text = "Text" + Str(addGIdx + 1)
                              gView\cells(addIdx)\gadgets(addGIdx)\align = #LJV_CENTER
                              gView\cells(addIdx)\gadgets(addGIdx)\size = 1
                              gView\cells(addIdx)\gadgets(addGIdx)\fgColor = -1
                              gView\cells(addIdx)\gadgets(addGIdx)\bgColor = -1
                              gView\cells(addIdx)\gadgetCount + 1
                              ; Update UI to show first gadget properties
                              SetGadgetState(#DEBUG_COMBO_TYPE, gView\cells(addIdx)\gadgets(0)\type + 1)
                              SetGadgetText(#DEBUG_INPUT_VALUE, gView\cells(addIdx)\gadgets(0)\text)
                              ViewShow(gView\width, gView\height)
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True

                     Case #DEBUG_BTN_DEL_GADGET
                        ; Remove last gadget from cell
                        If gSelectStartCol >= 0
                           Protected delIdx.i = GetCellIndex(gSelectStartCol, gSelectStartRow)
                           If gView\cells(delIdx)\gadgetCount > 0
                              gView\cells(delIdx)\gadgetCount - 1
                              If gView\cells(delIdx)\gadgetCount = 0
                                 SetGadgetState(#DEBUG_COMBO_TYPE, 0)  ; (none)
                                 SetGadgetText(#DEBUG_INPUT_VALUE, "")
                              Else
                                 SetGadgetState(#DEBUG_COMBO_TYPE, gView\cells(delIdx)\gadgets(0)\type + 1)
                                 SetGadgetText(#DEBUG_INPUT_VALUE, gView\cells(delIdx)\gadgets(0)\text)
                              EndIf
                              ViewShow(gView\width, gView\height)
                              UpdateCodeDisplay()
                           EndIf
                        EndIf
                        ProcedureReturn #True
                  EndSelect
            EndSelect
         EndIf

         ProcedureReturn #False
      EndProcedure
   CompilerEndIf

   ;- Internal Functions

   Procedure.i ParseCellRef(ref.s, *col.Integer, *row.Integer)
      ; Parse "A1", "B12", "AA5" etc into col/row (0-based)
      Protected i.i, c.i, colVal.i = 0, rowVal.i = 0
      Protected char.s

      ref = UCase(Trim(ref))
      If Len(ref) < 2
         ProcedureReturn #False
      EndIf

      ; Parse column letters
      i = 1
      While i <= Len(ref)
         char = Mid(ref, i, 1)
         c = Asc(char)
         If c >= 'A' And c <= 'Z'
            colVal = colVal * 26 + (c - 'A' + 1)
            i + 1
         Else
            Break
         EndIf
      Wend

      ; Parse row number
      If i <= Len(ref)
         rowVal = Val(Mid(ref, i))
      EndIf

      If colVal > 0 And rowVal > 0
         *col\i = colVal - 1    ; 0-based
         *row\i = rowVal - 1    ; 0-based
         ProcedureReturn #True
      EndIf

      ProcedureReturn #False
   EndProcedure

   Procedure.i GetCellIndex(col.i, row.i)
      ; Get index into cells array for given col/row
      ; Cell references are FIXED - A1 is always A1 regardless of orientation
      ; Grid dimensions swap with orientation, cells outside bounds don't render
      ; Use maxDim to ensure we can store cells for both orientations
      Protected maxDim.i = gView\cols
      If gView\rows > maxDim : maxDim = gView\rows : EndIf
      ProcedureReturn row * maxDim + col
   EndProcedure

   Procedure.i GetEffectiveCols()
      ; In portrait: cols, in landscape: rows (they swap)
      If gView\orientation = 0
         ProcedureReturn gView\cols
      Else
         ProcedureReturn gView\rows
      EndIf
   EndProcedure

   Procedure.i GetEffectiveRows()
      ; In portrait: rows, in landscape: cols (they swap)
      If gView\orientation = 0
         ProcedureReturn gView\rows
      Else
         ProcedureReturn gView\cols
      EndIf
   EndProcedure

   Procedure PrecomputePositions(pWidth.i, pHeight.i, lWidth.i, lHeight.i)
      ; Precompute render positions for all cells in both orientations
      ; pWidth/pHeight = portrait dimensions, lWidth/lHeight = landscape dimensions
      Protected i.i, j.i, col.i, row.i, maxDim.i
      Protected pCellW.i, pCellH.i, lCellW.i, lCellH.i
      Protected pCols.i, pRows.i, lCols.i, lRows.i
      Protected cornerCol.i, cornerRow.i
      Protected isLeftEdge.i, isRightEdge.i, isTopEdge.i, isBottomEdge.i
      Protected x.i, y.i, show.i, natX.i, natY.i, phKey.s
      Protected key.s, posKey.s, probeX.i, probeY.i, found.i, probeCount.i
      Protected *cell.stCell
      Protected *masterCell.stCell
      Protected NewMap pOccupied.i()   ; Portrait occupied positions
      Protected NewMap lOccupied.i()   ; Landscape occupied positions

      ; Clear existing maps
      ClearMap(gPortraitPos())
      ClearMap(gLandscapePos())
      ClearMap(pOccupied())
      ClearMap(lOccupied())

      ; Calculate dimensions for each orientation
      pCols = gView\cols
      pRows = gView\rows
      lCols = gView\rows   ; Swapped for landscape
      lRows = gView\cols

      pCellW = pWidth / pCols
      pCellH = pHeight / pRows
      lCellW = lWidth / lCols
      lCellH = lHeight / lRows

      maxDim = gView\cols
      If gView\rows > maxDim : maxDim = gView\rows : EndIf

      Debug "=== PrecomputePositions ==="
      Debug "Grid: cols=" + Str(gView\cols) + " rows=" + Str(gView\rows) + " totalCells=" + Str(gView\totalCells)
      Debug "Portrait: " + Str(pCols) + "x" + Str(pRows) + " cellSize=" + Str(pCellW) + "x" + Str(pCellH)
      Debug "Landscape: " + Str(lCols) + "x" + Str(lRows) + " cellSize=" + Str(lCellW) + "x" + Str(lCellH)
      Debug "maxDim=" + Str(maxDim)

      ; FIRST PASS: Propagate lockCorner/visible from slaves to masters
      ; This must happen BEFORE position calculation since slaves come after masters in iteration order
      Debug "--- First pass: propagate slave flags to masters ---"
      For i = 0 To gView\totalCells - 1
         *cell = @gView\cells(i)
         If *cell\joinGroup > 0 And Not *cell\isMaster
            ; Slave cell - propagate to master
            If *cell\lockCorner Or *cell\visible
               *masterCell = @gView\cells(*cell\masterCell)
               If *cell\lockCorner
                  *masterCell\lockCorner = #True
                  ; Track which cell had lockCorner (use its position for corner detection)
                  *masterCell\lockCornerCol = *cell\col
                  *masterCell\lockCornerRow = *cell\row
                  Debug "  Propagated lockCorner from slave[" + Str(i) + "] col=" + Str(*cell\col) + " row=" + Str(*cell\row) + " to master[" + Str(*cell\masterCell) + "]"
               EndIf
               If *cell\visible
                  *masterCell\visible = #True
                  Debug "  Propagated visible from slave[" + Str(i) + "] to master[" + Str(*cell\masterCell) + "]"
               EndIf
            EndIf
         EndIf
      Next

      ; SECOND PASS: Initialize lockCornerCol/Row for cells with lockCorner that don't have it set yet
      ; This handles master/standalone cells where lockCorner was set directly
      Debug "--- Second pass: init lockCorner positions ---"
      For i = 0 To gView\totalCells - 1
         *cell = @gView\cells(i)
         If *cell\lockCorner And *cell\lockCornerCol = 0 And *cell\lockCornerRow = 0
            ; lockCorner is set but position not yet initialized
            ; Check if cell is actually at (0,0) or if we need to set it
            If *cell\col = 0 And *cell\row = 0
               ; Cell is at origin - already correct
               Debug "  Cell[" + Str(i) + "] at origin, lockCorner position already (0,0)"
            Else
               ; Need to set the corner position to this cell's own position
               *cell\lockCornerCol = *cell\col
               *cell\lockCornerRow = *cell\row
               Debug "  Cell[" + Str(i) + "] initialized lockCorner position to col=" + Str(*cell\col) + " row=" + Str(*cell\row)
            EndIf
         EndIf
      Next

      ; PRE-PASS: Mark in-bounds positions with gadgets as occupied
      ; This ensures visible-shifted cells don't probe into slots used by cells with gadgets
      ; Empty cells (no gadgets) don't reserve slots - they can be overlapped
      Debug "--- Pre-pass: mark in-bounds cells with gadgets ---"
      For row = 0 To maxDim - 1
         For col = 0 To maxDim - 1
            i = row * maxDim + col
            If i >= gView\totalCells : Continue : EndIf
            *cell = @gView\cells(i)
            ; Skip slave cells and empty cells
            If *cell\joinGroup > 0 And Not *cell\isMaster : Continue : EndIf
            If *cell\gadgetCount = 0 : Continue : EndIf
            ; Portrait in-bounds with gadgets
            If *cell\col < pCols And *cell\row < pRows And Not *cell\lockCorner
               posKey = Str(*cell\col * pCellW) + "," + Str(*cell\row * pCellH)
               pOccupied(posKey) = i
            EndIf
            ; Landscape in-bounds with gadgets
            If *cell\col < lCols And *cell\row < lRows And Not *cell\lockCorner
               posKey = Str(*cell\col * lCellW) + "," + Str(*cell\row * lCellH)
               lOccupied(posKey) = i
            EndIf
         Next
      Next

      ; THIRD PASS: Compute positions for all master/standalone cells
      Debug "--- Third pass: compute positions ---"
      For row = 0 To maxDim - 1
         For col = 0 To maxDim - 1
            i = row * maxDim + col
            If i >= gView\totalCells : Continue : EndIf

            *cell = @gView\cells(i)
            key = Str(i)

            ; Skip slave cells - only master renders
            If *cell\joinGroup > 0 And Not *cell\isMaster
               Continue
            EndIf

            Debug "Cell[" + Str(i) + "] col=" + Str(*cell\col) + " row=" + Str(*cell\row) + " lockCorner=" + Str(*cell\lockCorner) + " visible=" + Str(*cell\visible) + " gadgetCount=" + Str(*cell\gadgetCount) + " joinGroup=" + Str(*cell\joinGroup) + " isMaster=" + Str(*cell\isMaster)

            ;--- PORTRAIT positions ---
            If *cell\lockCorner
               ; Use lockCornerCol/Row which tracks the original lockCorner source cell position
               ; This is crucial for join groups where a slave cell has lockCorner
               cornerCol = *cell\lockCornerCol
               cornerRow = *cell\lockCornerRow

               ; Determine which edge this cell is at (check against both portrait dimensions)
               ; A cell is at an edge if its position equals the edge in either orientation
               isLeftEdge = Bool(cornerCol = 0)
               isRightEdge = Bool(cornerCol = pCols - 1 Or cornerCol = pRows - 1)
               isTopEdge = Bool(cornerRow = 0)
               isBottomEdge = Bool(cornerRow = pCols - 1 Or cornerRow = pRows - 1)

               Debug "  PORTRAIT lockCorner: lockCornerCol=" + Str(cornerCol) + " lockCornerRow=" + Str(cornerRow)
               Debug "  PORTRAIT edges: L=" + Str(isLeftEdge) + " R=" + Str(isRightEdge) + " T=" + Str(isTopEdge) + " B=" + Str(isBottomEdge)

               ; Position at the appropriate edge of the current portrait grid
               If isLeftEdge : x = 0 : ElseIf isRightEdge : x = (pCols - 1) * pCellW : Else : x = *cell\col * pCellW : EndIf
               If isTopEdge : y = 0 : ElseIf isBottomEdge : y = (pRows - 1) * pCellH : Else : y = *cell\row * pCellH : EndIf
               show = #True
               Debug "  PORTRAIT lockCorner position: x=" + Str(x) + " y=" + Str(y) + " show=" + Str(show)
            ElseIf *cell\col < pCols And *cell\row < pRows
               ; In bounds - show at normal position
               x = *cell\col * pCellW
               y = *cell\row * pCellH
               show = #True
               Debug "  PORTRAIT in-bounds: x=" + Str(x) + " y=" + Str(y)
            ElseIf *cell\visible And *cell\gadgetCount > 0
               ; Out of bounds but visible AND has gadgets - shift to edge with collision resolution
               ; Empty cells (no gadgets) just hide when out of bounds
               x = *cell\col * pCellW
               y = *cell\row * pCellH
               If *cell\col >= pCols : x = (pCols - 1) * pCellW : EndIf
               If *cell\row >= pRows : y = (pRows - 1) * pCellH : EndIf
               ; Collision resolution: probe x+1 then y+1 like hash table
               probeX = x : probeY = y : found = #False
               While Not found
                  posKey = Str(probeX) + "," + Str(probeY)
                  If Not FindMapElement(pOccupied(), posKey)
                     x = probeX : y = probeY : found = #True
                  Else
                     ; Try x+1 first
                     probeX + pCellW
                     If probeX >= pCols * pCellW
                        ; Wrap to next row
                        probeX = 0 : probeY + pCellH
                        If probeY >= pRows * pCellH
                           ; No space - keep original position (overlap)
                           found = #True
                        EndIf
                     EndIf
                  EndIf
               Wend
               show = #True
               Debug "  PORTRAIT visible shifted: x=" + Str(x) + " y=" + Str(y)
            Else
               ; Out of bounds and not visible - don't show
               show = #False
               x = 0 : y = 0
               Debug "  PORTRAIT hidden: out of bounds"
            EndIf
            gPortraitPos(key)\cellIdx = i
            gPortraitPos(key)\x = x
            gPortraitPos(key)\y = y
            gPortraitPos(key)\show = show
            gPortraitPos(key)\placeholder = #False
            ; Shifted = out of bounds with visible flag (not lockCorner, not in-bounds)
            gPortraitPos(key)\shifted = Bool(show And Not *cell\lockCorner And (*cell\col >= pCols Or *cell\row >= pRows))
            ; Mark position as occupied - only cells with gadgets reserve slots
            If show And *cell\gadgetCount > 0
               posKey = Str(x) + "," + Str(y)
               pOccupied(posKey) = i
            EndIf

            ; Add placeholder at natural position if lockCorner cell moved
            If *cell\lockCorner And *cell\col < pCols And *cell\row < pRows
               natX = *cell\col * pCellW
               natY = *cell\row * pCellH
               If natX <> x Or natY <> y
                  ; Cell moved from natural position - add placeholder
                  phKey = "ph_" + key
                  gPortraitPos(phKey)\cellIdx = i
                  gPortraitPos(phKey)\x = natX
                  gPortraitPos(phKey)\y = natY
                  gPortraitPos(phKey)\show = #True
                  gPortraitPos(phKey)\placeholder = #True
                  Debug "  PORTRAIT placeholder at natural pos: x=" + Str(natX) + " y=" + Str(natY)
               EndIf
            EndIf

            ;--- LANDSCAPE positions ---
            If *cell\lockCorner
               ; Use lockCornerCol/Row which tracks the original lockCorner source cell position
               cornerCol = *cell\lockCornerCol
               cornerRow = *cell\lockCornerRow

               ; Determine which edge this cell is at (same edge detection as portrait)
               ; The edge detection stays the same - we want to know if the cell was at an edge
               isLeftEdge = Bool(cornerCol = 0)
               isRightEdge = Bool(cornerCol = pCols - 1 Or cornerCol = pRows - 1)
               isTopEdge = Bool(cornerRow = 0)
               isBottomEdge = Bool(cornerRow = pCols - 1 Or cornerRow = pRows - 1)

               Debug "  LANDSCAPE lockCorner: lockCornerCol=" + Str(cornerCol) + " lockCornerRow=" + Str(cornerRow)
               Debug "  LANDSCAPE edges: L=" + Str(isLeftEdge) + " R=" + Str(isRightEdge) + " T=" + Str(isTopEdge) + " B=" + Str(isBottomEdge)

               ; Position at the appropriate edge of the current landscape grid
               If isLeftEdge : x = 0 : ElseIf isRightEdge : x = (lCols - 1) * lCellW : Else : x = *cell\col * lCellW : EndIf
               If isTopEdge : y = 0 : ElseIf isBottomEdge : y = (lRows - 1) * lCellH : Else : y = *cell\row * lCellH : EndIf
               show = #True
               Debug "  LANDSCAPE lockCorner position: x=" + Str(x) + " y=" + Str(y) + " show=" + Str(show)
            ElseIf *cell\col < lCols And *cell\row < lRows
               ; In bounds - show at normal position
               x = *cell\col * lCellW
               y = *cell\row * lCellH
               show = #True
               Debug "  LANDSCAPE in-bounds: x=" + Str(x) + " y=" + Str(y)
            ElseIf *cell\visible And *cell\gadgetCount > 0
               ; Out of bounds but visible AND has gadgets - shift to edge with collision resolution
               ; Empty cells (no gadgets) just hide when out of bounds
               Debug "  LANDSCAPE visible check: cell " + Str(i) + " visible=" + Str(*cell\visible) + " gadgetCount=" + Str(*cell\gadgetCount)
               x = *cell\col * lCellW
               y = *cell\row * lCellH
               Debug "  LANDSCAPE visible: natural pos x=" + Str(x) + " y=" + Str(y) + " col=" + Str(*cell\col) + " row=" + Str(*cell\row)
               If *cell\col >= lCols : x = (lCols - 1) * lCellW : EndIf
               If *cell\row >= lRows : y = (lRows - 1) * lCellH : EndIf
               Debug "  LANDSCAPE visible: edge clamp x=" + Str(x) + " y=" + Str(y)
               ; Collision resolution: probe x+1 then y+1 like hash table
               probeX = x : probeY = y : found = #False
               probeCount = 0
               While Not found
                  posKey = Str(probeX) + "," + Str(probeY)
                  Debug "  LANDSCAPE probe[" + Str(probeCount) + "]: checking " + posKey + " occupied=" + Str(Bool(FindMapElement(lOccupied(), posKey)))
                  If Not FindMapElement(lOccupied(), posKey)
                     x = probeX : y = probeY : found = #True
                     Debug "  LANDSCAPE probe: FOUND free slot at " + posKey
                  Else
                     Debug "  LANDSCAPE probe: occupied by cell " + Str(lOccupied(posKey))
                     ; Try x+1 first
                     probeX + lCellW
                     If probeX >= lCols * lCellW
                        ; Wrap to next row
                        probeX = 0 : probeY + lCellH
                        If probeY >= lRows * lCellH
                           ; No space - keep original position (overlap)
                           Debug "  LANDSCAPE probe: NO SPACE - overflow!"
                           found = #True
                        EndIf
                     EndIf
                  EndIf
                  probeCount + 1
                  If probeCount > 20 : Debug "  LANDSCAPE probe: INFINITE LOOP BREAK" : found = #True : EndIf
               Wend
               show = #True
               Debug "  LANDSCAPE visible shifted: final x=" + Str(x) + " y=" + Str(y)
            Else
               ; Out of bounds and not visible - don't show
               Debug "  LANDSCAPE hidden: out of bounds"
               show = #False
               x = 0 : y = 0
            EndIf
            gLandscapePos(key)\cellIdx = i
            gLandscapePos(key)\x = x
            gLandscapePos(key)\y = y
            gLandscapePos(key)\show = show
            gLandscapePos(key)\placeholder = #False
            ; Shifted = out of bounds with visible flag (not lockCorner, not in-bounds)
            gLandscapePos(key)\shifted = Bool(show And Not *cell\lockCorner And (*cell\col >= lCols Or *cell\row >= lRows))
            ; Mark position as occupied - only cells with gadgets reserve slots
            If show And *cell\gadgetCount > 0
               posKey = Str(x) + "," + Str(y)
               lOccupied(posKey) = i
            EndIf

            ; Add placeholder at natural position if lockCorner cell moved
            If *cell\lockCorner And *cell\col < lCols And *cell\row < lRows
               natX = *cell\col * lCellW
               natY = *cell\row * lCellH
               If natX <> x Or natY <> y
                  ; Cell moved from natural position - add placeholder
                  phKey = "ph_" + key
                  gLandscapePos(phKey)\cellIdx = i
                  gLandscapePos(phKey)\x = natX
                  gLandscapePos(phKey)\y = natY
                  gLandscapePos(phKey)\show = #True
                  gLandscapePos(phKey)\placeholder = #True
                  Debug "  LANDSCAPE placeholder at natural pos: x=" + Str(natX) + " y=" + Str(natY)
               EndIf
            EndIf
         Next
      Next

      ; Summary of computed positions
      Debug "=== PORTRAIT MAP ==="
      ForEach gPortraitPos()
         Debug "  [" + MapKey(gPortraitPos()) + "] idx=" + Str(gPortraitPos()\cellIdx) + " x=" + Str(gPortraitPos()\x) + " y=" + Str(gPortraitPos()\y) + " show=" + Str(gPortraitPos()\show)
      Next
      Debug "=== LANDSCAPE MAP ==="
      ForEach gLandscapePos()
         Debug "  [" + MapKey(gLandscapePos()) + "] idx=" + Str(gLandscapePos()\cellIdx) + " x=" + Str(gLandscapePos()\x) + " y=" + Str(gLandscapePos()\y) + " show=" + Str(gLandscapePos()\show)
      Next
      Debug "=== PrecomputePositions DONE ==="
   EndProcedure

   Procedure.i GenerateColor(seed.i, index.i)
      ; Generate deterministic color from seed + index
      Protected r.i, g.i, b.i
      Protected combined.i = seed ! (index * 2654435761)  ; Knuth multiplicative hash

      RandomSeed(combined)

      ; Generate pleasant, distinct colors
      r = Random(200, 80)
      g = Random(200, 80)
      b = Random(200, 80)

      ; Ensure minimum brightness difference
      If (r + g + b) < 300
         r + 50 : g + 50
      EndIf

      ProcedureReturn RGB(r, g, b)
   EndProcedure

   Procedure   CalculateGadgetPosition(cellX.i, cellY.i, cellW.i, cellH.i,
                                        gadgetW.i, gadgetH.i, align.i,
                                        *outX.Integer, *outY.Integer)
      ; Calculate gadget position within cell based on alignment
      Protected x.i, y.i
      Protected baseAlign.i = align & $F        ; Lower 4 bits = base
      Protected modifiers.i = align & $F0       ; Upper 4 bits = modifiers
      Protected offsetX.i = cellW / 10          ; 10% offset for modifiers
      Protected offsetY.i = cellH / 10

      ; Base horizontal position
      Select baseAlign & (#LJV_LEFT | #LJV_RIGHT)
         Case #LJV_LEFT
            x = cellX + 5
         Case #LJV_RIGHT
            x = cellX + cellW - gadgetW - 5
         Default  ; CENTER
            x = cellX + (cellW - gadgetW) / 2
      EndSelect

      ; Base vertical position
      Select baseAlign & (#LJV_TOP | #LJV_BOTTOM)
         Case #LJV_TOP
            y = cellY + 5
         Case #LJV_BOTTOM
            y = cellY + cellH - gadgetH - 5
         Default  ; CENTER
            y = cellY + (cellH - gadgetH) / 2
      EndSelect

      ; Apply modifiers
      If modifiers & #LJV_TOLEFT  : x - offsetX : EndIf
      If modifiers & #LJV_TORIGHT : x + offsetX : EndIf
      If modifiers & #LJV_UP      : y - offsetY : EndIf
      If modifiers & #LJV_DOWN    : y + offsetY : EndIf

      *outX\i = x
      *outY\i = y
   EndProcedure

   Procedure   RenderCell(idx.i, baseX.i, baseY.i, cellW.i, cellH.i)
      ; Render a single cell and its gadgets at the precomputed position
      ; Positions are precomputed by PrecomputePositions() - no shifting needed here
      Protected i.i, x.i, y.i, gw.i, gh.i
      Protected gid.i
      Protected *cell.stCell = @gView\cells(idx)
      Protected cellColor.i
      Protected visualCol.i, visualRow.i
      Protected isSelected.i = #False
      Protected effectiveCols.i, effectiveRows.i
      Protected fontSize.i, fontFlags.i, hFont.i

      effectiveCols = GetEffectiveCols()
      effectiveRows = GetEffectiveRows()

      ; Skip slave cells (part of join group but not master)
      If *cell\joinGroup > 0 And Not *cell\isMaster
         ProcedureReturn
      EndIf

      ; Calculate actual cell dimensions (for joined cells)
      Protected actualW.i = cellW
      Protected actualH.i = cellH

      If *cell\joinGroup > 0
         ; Find join group and calculate merged dimensions
         For i = 0 To gView\joinGroupCount - 1
            If gView\joinGroups(i)\id = *cell\joinGroup
               actualW = (gView\joinGroups(i)\endCol - gView\joinGroups(i)\startCol + 1) * cellW
               actualH = (gView\joinGroups(i)\endRow - gView\joinGroups(i)\startRow + 1) * cellH
               Break
            EndIf
         Next
      EndIf

      ; Positions are precomputed - no out-of-bounds check or shifting needed
      ; (PrecomputePositions handles lockCorner, visible, and edge cases)

      ; Determine cell color (with selection highlight in debug mode)
      cellColor = *cell\color

      ; Check if cell is selected (debug mode only)
      Protected borderSize.i = 0
      Protected borderColor.i = RGB(0, 120, 255)    ; Bright blue border
      Protected outerContainerID.i

      CompilerIf (Defined(PB_Compiler_Debugger, #PB_Constant) And #PB_Compiler_Debugger) Or #LJV_DEBUG
         visualCol = baseX / gView\cellWidth
         visualRow = baseY / gView\cellHeight

         ; Check if in selection range (between start and end)
         Protected minCol.i, maxCol.i, minRow.i, maxRow.i
         Protected inRange.i = #False

         If gSelectStartCol >= 0 And gSelectEndCol >= 0
            minCol = gSelectStartCol
            maxCol = gSelectEndCol
            If maxCol < minCol : Swap minCol, maxCol : EndIf
            minRow = gSelectStartRow
            maxRow = gSelectEndRow
            If maxRow < minRow : Swap minRow, maxRow : EndIf
            inRange = Bool(visualCol >= minCol And visualCol <= maxCol And visualRow >= minRow And visualRow <= maxRow)
         EndIf

         If (visualCol = gSelectStartCol And visualRow = gSelectStartRow) Or (visualCol = gSelectEndCol And visualRow = gSelectEndRow)
            isSelected = #True
            borderSize = 4        ; Thick border for selected cells
         ElseIf inRange
            isSelected = #True
            borderSize = 2        ; Thinner border for cells in range
            borderColor = RGB(100, 180, 255)   ; Lighter blue for range
         EndIf
      CompilerEndIf

      ; Draw cell with selection border if needed
      Protected containerID.i
      If borderSize > 0
         ; Create outer container for border
         outerContainerID = ContainerGadget(#PB_Any, baseX, baseY, actualW, actualH, #PB_Container_Flat)
         SetGadgetColor(outerContainerID, #PB_Gadget_BackColor, borderColor)
         ; Create inner container for cell content (inset by border size)
         containerID = ContainerGadget(#PB_Any, borderSize, borderSize, actualW - borderSize * 2, actualH - borderSize * 2, #PB_Container_Flat)
         SetGadgetColor(containerID, #PB_Gadget_BackColor, cellColor)
         ; Adjust actualW/H for gadget placement inside inner container
         actualW - borderSize * 2
         actualH - borderSize * 2
      Else
         ; Normal cell without selection
         containerID = ContainerGadget(#PB_Any, baseX, baseY, actualW, actualH, #PB_Container_Flat)
         SetGadgetColor(containerID, #PB_Gadget_BackColor, cellColor)
      EndIf

      ; Render gadgets within cell
      For i = 0 To *cell\gadgetCount - 1
         With *cell\gadgets(i)
            ; Determine gadget size based on type
            Select \type
               Case #LJV_TEXT, #LJV_HYPERLINK
                  gw = actualW - 10 : gh = 24
               Case #LJV_INPUT
                  gw = actualW - 20 : gh = 28
               Case #LJV_BUTTON
                  gw = actualW / 2 : gh = 32
               Case #LJV_CHECKBOX, #LJV_OPTION
                  gw = actualW - 10 : gh = 24
               Case #LJV_COMBO, #LJV_DATE, #LJV_SPIN
                  gw = actualW - 20 : gh = 28
               Case #LJV_TRACKBAR, #LJV_PROGRESS
                  gw = actualW - 20 : gh = 24
               Case #LJV_EDITOR, #LJV_LISTVIEW, #LJV_LISTICON, #LJV_TREE
                  gw = actualW - 10 : gh = actualH - 10
               Case #LJV_CALENDAR
                  gw = actualW - 10 : gh = actualH - 10
               Case #LJV_CANVAS
                  gw = actualW - 10 : gh = actualH - 10
               Case #LJV_IMAGE
                  gw = actualW - 10 : gh = actualH - 10
               Case #LJV_FRAME, #LJV_CONTAINER, #LJV_PANEL, #LJV_SCROLLAREA
                  gw = actualW - 10 : gh = actualH - 10
               Case #LJV_WEB
                  gw = actualW - 10 : gh = actualH - 10
               Default
                  gw = actualW - 10 : gh = 24
            EndSelect

            ; Calculate position
            CalculateGadgetPosition(0, i * (gh + 5), actualW, actualH - (i * (gh + 5)),
                                     gw, gh, \align, @x, @y)

            ; Create gadget
            Select \type
               Case #LJV_TEXT
                  \gadgetID = TextGadget(#PB_Any, x, y, gw, gh, \text)
               Case #LJV_INPUT
                  \gadgetID = StringGadget(#PB_Any, x, y, gw, gh, \text)
               Case #LJV_BUTTON
                  \gadgetID = ButtonGadget(#PB_Any, x, y, gw, gh, \text)
               Case #LJV_CHECKBOX
                  \gadgetID = CheckBoxGadget(#PB_Any, x, y, gw, gh, \text)
               Case #LJV_OPTION
                  \gadgetID = OptionGadget(#PB_Any, x, y, gw, gh, \text)
               Case #LJV_COMBO
                  \gadgetID = ComboBoxGadget(#PB_Any, x, y, gw, gh)
                  If \text <> "" : AddGadgetItem(\gadgetID, -1, \text) : SetGadgetState(\gadgetID, 0) : EndIf
               Case #LJV_DATE
                  \gadgetID = DateGadget(#PB_Any, x, y, gw, gh)
               Case #LJV_SPIN
                  \gadgetID = SpinGadget(#PB_Any, x, y, gw, gh, 0, 100)
                  If \text <> "" : SetGadgetState(\gadgetID, Val(\text)) : EndIf
               Case #LJV_TRACKBAR
                  \gadgetID = TrackBarGadget(#PB_Any, x, y, gw, gh, 0, 100)
                  If \text <> "" : SetGadgetState(\gadgetID, Val(\text)) : EndIf
               Case #LJV_PROGRESS
                  \gadgetID = ProgressBarGadget(#PB_Any, x, y, gw, gh, 0, 100)
                  If \text <> "" : SetGadgetState(\gadgetID, Val(\text)) : EndIf
               Case #LJV_HYPERLINK
                  \gadgetID = HyperLinkGadget(#PB_Any, x, y, gw, gh, \text, RGB(0, 0, 200))
               Case #LJV_EDITOR
                  \gadgetID = EditorGadget(#PB_Any, x, y, gw, gh)
                  If \text <> "" : SetGadgetText(\gadgetID, \text) : EndIf
               Case #LJV_LISTVIEW
                  \gadgetID = ListViewGadget(#PB_Any, x, y, gw, gh)
                  If \text <> "" : AddGadgetItem(\gadgetID, -1, \text) : EndIf
               Case #LJV_LISTICON
                  \gadgetID = ListIconGadget(#PB_Any, x, y, gw, gh, \text, 100)
               Case #LJV_TREE
                  \gadgetID = TreeGadget(#PB_Any, x, y, gw, gh)
                  If \text <> "" : AddGadgetItem(\gadgetID, -1, \text, 0, 0) : EndIf
               Case #LJV_CALENDAR
                  \gadgetID = CalendarGadget(#PB_Any, x, y, gw, gh)
               Case #LJV_CANVAS
                  \gadgetID = CanvasGadget(#PB_Any, x, y, gw, gh)
               Case #LJV_IMAGE
                  \gadgetID = ImageGadget(#PB_Any, x, y, gw, gh, 0)
               Case #LJV_FRAME
                  \gadgetID = FrameGadget(#PB_Any, x, y, gw, gh, \text)
               Case #LJV_CONTAINER
                  \gadgetID = ContainerGadget(#PB_Any, x, y, gw, gh)
                  CloseGadgetList()
               Case #LJV_PANEL
                  \gadgetID = PanelGadget(#PB_Any, x, y, gw, gh)
                  If \text <> "" : AddGadgetItem(\gadgetID, -1, \text) : EndIf
                  CloseGadgetList()
               Case #LJV_SCROLLAREA
                  \gadgetID = ScrollAreaGadget(#PB_Any, x, y, gw, gh, gw * 2, gh * 2)
                  CloseGadgetList()
               Case #LJV_WEB
                  CompilerIf Defined(PB_Compiler_SpiderBasic, #PB_Constant) = 0
                     \gadgetID = WebGadget(#PB_Any, x, y, gw, gh, \text)
                  CompilerEndIf
               Default
                  \gadgetID = TextGadget(#PB_Any, x, y, gw, gh, "[" + \text + "]")
            EndSelect

            ; Apply font based on size/bold/italic properties
            If \gadgetID And IsGadget(\gadgetID)
               ; Size: 0=S(8), 1=M(10), 2=L(13), 3=XL(16)
               Select \size
                  Case 0 : fontSize = 8
                  Case 2 : fontSize = 13
                  Case 3 : fontSize = 16
                  Default : fontSize = 10
               EndSelect
               fontFlags = 0
               If \bold : fontFlags | #PB_Font_Bold : EndIf
               If \italic : fontFlags | #PB_Font_Italic : EndIf
               hFont = LoadFont(#PB_Any, "Segoe UI", fontSize, fontFlags)
               If hFont
                  SetGadgetFont(\gadgetID, FontID(hFont))
               EndIf

               ; Apply gadget colors (skip buttons which should stay standard)
               If \type <> #LJV_BUTTON
                  ; Foreground (text) color
                  If \fgColor >= 0
                     SetGadgetColor(\gadgetID, #PB_Gadget_FrontColor, \fgColor)
                  EndIf
                  ; Background color (-1 = transparent = use cell's color)
                  If \bgColor >= 0
                     SetGadgetColor(\gadgetID, #PB_Gadget_BackColor, \bgColor)
                  Else
                     ; Transparent: use cell's background color
                     SetGadgetColor(\gadgetID, #PB_Gadget_BackColor, cellColor)
                  EndIf
               EndIf
            EndIf
         EndWith
      Next

      CloseGadgetList()   ; Close inner container

      ; Close outer container if we have selection border
      If borderSize > 0
         CloseGadgetList()
      EndIf
   EndProcedure

   Procedure   RenderPlaceholder(idx.i, baseX.i, baseY.i, cellW.i, cellH.i)
      ; Render just the background of a cell (no gadgets) for lockCorner placeholders
      Protected *cell.stCell = @gView\cells(idx)
      Protected containerID.i

      ; Skip slave cells
      If *cell\joinGroup > 0 And Not *cell\isMaster
         ProcedureReturn
      EndIf

      ; Calculate actual cell dimensions (for joined cells)
      Protected actualW.i = cellW
      Protected actualH.i = cellH
      Protected i.i

      If *cell\joinGroup > 0
         For i = 0 To gView\joinGroupCount - 1
            If gView\joinGroups(i)\id = *cell\joinGroup
               actualW = (gView\joinGroups(i)\endCol - gView\joinGroups(i)\startCol + 1) * cellW
               actualH = (gView\joinGroups(i)\endRow - gView\joinGroups(i)\startRow + 1) * cellH
               Break
            EndIf
         Next
      EndIf

      ; Just draw the background - no gadgets
      containerID = ContainerGadget(#PB_Any, baseX, baseY, actualW, actualH, #PB_Container_Flat)
      SetGadgetColor(containerID, #PB_Gadget_BackColor, *cell\color)
      CloseGadgetList()
   EndProcedure

   ;- Public Interface

   Procedure ViewCreate(name.s, cols.i, rows.i, seed.i = 0)
      ; Initialize a new view
      ; Allocate cells for BOTH orientations: max(cols,rows)^2
      ; In portrait: show cols x rows, in landscape: show rows x cols
      Protected i.i, totalCells.i, maxDim.i, col.i, row.i

      If cols < 1 : cols = 1 : EndIf
      If cols > #VIEW_MAX_COLS : cols = #VIEW_MAX_COLS : EndIf
      If rows < 1 : rows = 1 : EndIf
      If rows > #VIEW_MAX_ROWS : rows = #VIEW_MAX_ROWS : EndIf

      gView\name = name
      gView\cols = cols
      gView\rows = rows
      gView\seed = seed
      gView\orientation = 0     ; Portrait default
      gView\windowID = 0
      gView\joinGroupCount = 0

      ; Allocate for max dimension squared to cover both orientations
      maxDim = cols
      If rows > maxDim : maxDim = rows : EndIf
      totalCells = maxDim * maxDim
      gView\totalCells = totalCells

      ReDim gView\cells(totalCells - 1)
      ReDim gView\joinGroups(8)

      ; Initialize all cells with their fixed (col, row) position
      For row = 0 To maxDim - 1
         For col = 0 To maxDim - 1
            i = row * maxDim + col
            gView\cells(i)\col = col
            gView\cells(i)\row = row
            gView\cells(i)\joinGroup = 0
            gView\cells(i)\isMaster = #False
            gView\cells(i)\color = GenerateColor(seed, i)
            gView\cells(i)\colorLocked = #False
            gView\cells(i)\lockCorner = #False
            gView\cells(i)\visible = #True
            gView\cells(i)\gadgetCount = 0
            ReDim gView\cells(i)\gadgets(4)
         Next
      Next

      gInitialized = #True
   EndProcedure

   Procedure ViewCell(ref.s, gadgetType.i, text.s = "", align.i = 0)
      ; Add gadget to a single cell
      ; Cell references are FIXED - A1 is always A1 regardless of orientation
      Protected col.i, row.i, idx.i, gIdx.i
      Protected maxDim.i

      If Not gInitialized : ProcedureReturn : EndIf

      maxDim = gView\cols
      If gView\rows > maxDim : maxDim = gView\rows : EndIf

      If ParseCellRef(ref, @col, @row)
         ; Cell refs are FIXED - no orientation swap
         ; Bounds check against maxDim (covers both orientations)
         If col < maxDim And row < maxDim
            idx = GetCellIndex(col, row)
            gIdx = gView\cells(idx)\gadgetCount

            If gIdx < #VIEW_MAX_GADGETS
               If gIdx > ArraySize(gView\cells(idx)\gadgets())
                  ReDim gView\cells(idx)\gadgets(gIdx + 4)
               EndIf

               gView\cells(idx)\gadgets(gIdx)\type = gadgetType
               gView\cells(idx)\gadgets(gIdx)\text = text
               gView\cells(idx)\gadgets(gIdx)\align = align
               gView\cells(idx)\gadgets(gIdx)\fgColor = -1
               gView\cells(idx)\gadgets(gIdx)\bgColor = -1
               gView\cells(idx)\gadgetCount + 1
            EndIf
         EndIf
      EndIf
   EndProcedure

   Procedure ViewCellRange(refStart.s, refEnd.s, gadgetType.i, text.s = "", align.i = 0)
      ; Add gadget to a range of joined cells
      ; Cell references are FIXED - A1:B2 is always A1:B2 regardless of orientation
      Protected startCol.i, startRow.i, endCol.i, endRow.i
      Protected masterIdx.i, i.i, j.i, idx.i, groupID.i
      Protected maxDim.i

      If Not gInitialized : ProcedureReturn : EndIf

      maxDim = gView\cols
      If gView\rows > maxDim : maxDim = gView\rows : EndIf

      If ParseCellRef(refStart, @startCol, @startRow) And ParseCellRef(refEnd, @endCol, @endRow)
         ; Cell refs are FIXED - no orientation swap

         ; Ensure start <= end
         If endCol < startCol : Swap startCol, endCol : EndIf
         If endRow < startRow : Swap startRow, endRow : EndIf

         ; Clamp to maxDim bounds (covers both orientations)
         If endCol >= maxDim : endCol = maxDim - 1 : EndIf
         If endRow >= maxDim : endRow = maxDim - 1 : EndIf

         ; Create join group
         groupID = gView\joinGroupCount + 1
         gView\joinGroupCount + 1

         If gView\joinGroupCount > ArraySize(gView\joinGroups())
            ReDim gView\joinGroups(gView\joinGroupCount + 8)
         EndIf

         masterIdx = GetCellIndex(startCol, startRow)

         gView\joinGroups(groupID - 1)\id = groupID
         gView\joinGroups(groupID - 1)\startCol = startCol
         gView\joinGroups(groupID - 1)\startRow = startRow
         gView\joinGroups(groupID - 1)\endCol = endCol
         gView\joinGroups(groupID - 1)\endRow = endRow
         gView\joinGroups(groupID - 1)\masterIdx = masterIdx

         ; Mark cells as joined
         For j = startRow To endRow
            For i = startCol To endCol
               idx = GetCellIndex(i, j)
               gView\cells(idx)\joinGroup = groupID
               gView\cells(idx)\masterCell = masterIdx
               gView\cells(idx)\isMaster = Bool(idx = masterIdx)
            Next
         Next

         ; Add gadget to master cell
         ViewCell(refStart, gadgetType, text, align)
      EndIf
   EndProcedure

   Procedure ViewJoin(refStart.s, refEnd.s, name.s = "")
      ; Join cells without adding a gadget - creates a named range like Excel
      ; Cell references are FIXED - no orientation swap
      Protected startCol.i, startRow.i, endCol.i, endRow.i
      Protected masterIdx.i, i.i, j.i, idx.i, groupID.i
      Protected maxDim.i

      If Not gInitialized : ProcedureReturn : EndIf

      maxDim = gView\cols
      If gView\rows > maxDim : maxDim = gView\rows : EndIf

      If ParseCellRef(refStart, @startCol, @startRow) And ParseCellRef(refEnd, @endCol, @endRow)
         ; Cell refs are FIXED - no orientation swap

         ; Ensure start <= end
         If endCol < startCol : Swap startCol, endCol : EndIf
         If endRow < startRow : Swap startRow, endRow : EndIf

         ; Clamp to maxDim bounds
         If endCol >= maxDim : endCol = maxDim - 1 : EndIf
         If endRow >= maxDim : endRow = maxDim - 1 : EndIf

         ; Create join group
         groupID = gView\joinGroupCount + 1
         gView\joinGroupCount + 1

         If gView\joinGroupCount > ArraySize(gView\joinGroups())
            ReDim gView\joinGroups(gView\joinGroupCount + 8)
         EndIf

         masterIdx = GetCellIndex(startCol, startRow)

         gView\joinGroups(groupID - 1)\id = groupID
         gView\joinGroups(groupID - 1)\name = name
         gView\joinGroups(groupID - 1)\startCol = startCol
         gView\joinGroups(groupID - 1)\startRow = startRow
         gView\joinGroups(groupID - 1)\endCol = endCol
         gView\joinGroups(groupID - 1)\endRow = endRow
         gView\joinGroups(groupID - 1)\masterIdx = masterIdx

         ; Mark cells as joined
         For j = startRow To endRow
            For i = startCol To endCol
               idx = GetCellIndex(i, j)
               gView\cells(idx)\joinGroup = groupID
               gView\cells(idx)\masterCell = masterIdx
               gView\cells(idx)\isMaster = Bool(idx = masterIdx)
            Next
         Next
      EndIf
   EndProcedure

   Procedure ViewShow(width.i = 0, height.i = 0)
      ; Render the view in a window using precomputed positions
      Protected i.i, x.i, y.i
      Protected effectiveCols.i, effectiveRows.i
      Protected title.s
      Protected winX.i = #PB_Ignore, winY.i = #PB_Ignore
      Protected pWidth.i, pHeight.i, lWidth.i, lHeight.i
      Protected key.s
      Protected *pos.stRenderPos

      If Not gInitialized : ProcedureReturn : EndIf

      ; Save window position before closing
      If gView\windowID And IsWindow(gView\windowID)
         winX = WindowX(gView\windowID)
         winY = WindowY(gView\windowID)
         CloseWindow(gView\windowID)
      EndIf

      ; Calculate dimensions for both orientations
      pWidth = 320 : pHeight = 480   ; Portrait defaults
      lWidth = 480 : lHeight = 320   ; Landscape defaults

      ; Determine current dimensions based on orientation
      If gView\orientation = 0  ; Portrait
         effectiveCols = gView\cols
         effectiveRows = gView\rows
         If width = 0 : width = pWidth : Else : pWidth = width : EndIf
         If height = 0 : height = pHeight : Else : pHeight = height : EndIf
      Else                       ; Landscape
         effectiveCols = gView\rows
         effectiveRows = gView\cols
         If width = 0 : width = lWidth : Else : lWidth = width : EndIf
         If height = 0 : height = lHeight : Else : lHeight = height : EndIf
      EndIf

      gView\width = width
      gView\height = height
      gView\cellWidth = width / effectiveCols
      gView\cellHeight = height / effectiveRows

      ; Precompute positions for both orientations
      PrecomputePositions(pWidth, pHeight, lWidth, lHeight)

      title = gView\name
      If gView\orientation : title + " [Landscape]" : Else : title + " [Portrait]" : EndIf

      gView\windowID = OpenWindow(#PB_Any, winX, winY, width, height, title)

      If gView\windowID
         ; Render cells using precomputed positions
         ; Pass 0: Render placeholders (background only for vacated lockCorner positions)
         If gView\orientation = 0
            ForEach gPortraitPos()
               If gPortraitPos()\show And gPortraitPos()\placeholder
                  RenderPlaceholder(gPortraitPos()\cellIdx, gPortraitPos()\x, gPortraitPos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         Else
            ForEach gLandscapePos()
               If gLandscapePos()\show And gLandscapePos()\placeholder
                  RenderPlaceholder(gLandscapePos()\cellIdx, gLandscapePos()\x, gLandscapePos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         EndIf

         ; Pass 1a: Render EMPTY in-bounds cells first (background only)
         ; These render first so shifted cells can cover them
         If gView\orientation = 0
            ForEach gPortraitPos()
               If gPortraitPos()\show And Not gPortraitPos()\placeholder And Not gPortraitPos()\shifted And Not gView\cells(gPortraitPos()\cellIdx)\lockCorner And gView\cells(gPortraitPos()\cellIdx)\gadgetCount = 0
                  RenderPlaceholder(gPortraitPos()\cellIdx, gPortraitPos()\x, gPortraitPos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         Else
            ForEach gLandscapePos()
               If gLandscapePos()\show And Not gLandscapePos()\placeholder And Not gLandscapePos()\shifted And Not gView\cells(gLandscapePos()\cellIdx)\lockCorner And gView\cells(gLandscapePos()\cellIdx)\gadgetCount = 0
                  RenderPlaceholder(gLandscapePos()\cellIdx, gLandscapePos()\x, gLandscapePos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         EndIf

         ; Pass 1b: Render SHIFTED cells (on top of empty cells)
         If gView\orientation = 0
            ForEach gPortraitPos()
               If gPortraitPos()\show And Not gPortraitPos()\placeholder And gPortraitPos()\shifted
                  RenderCell(gPortraitPos()\cellIdx, gPortraitPos()\x, gPortraitPos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         Else
            ForEach gLandscapePos()
               If gLandscapePos()\show And Not gLandscapePos()\placeholder And gLandscapePos()\shifted
                  RenderCell(gLandscapePos()\cellIdx, gLandscapePos()\x, gLandscapePos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         EndIf

         ; Pass 1c: Render IN-BOUNDS cells WITH gadgets (on top)
         If gView\orientation = 0
            ForEach gPortraitPos()
               If gPortraitPos()\show And Not gPortraitPos()\placeholder And Not gPortraitPos()\shifted And Not gView\cells(gPortraitPos()\cellIdx)\lockCorner And gView\cells(gPortraitPos()\cellIdx)\gadgetCount > 0
                  RenderCell(gPortraitPos()\cellIdx, gPortraitPos()\x, gPortraitPos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         Else
            ForEach gLandscapePos()
               If gLandscapePos()\show And Not gLandscapePos()\placeholder And Not gLandscapePos()\shifted And Not gView\cells(gLandscapePos()\cellIdx)\lockCorner And gView\cells(gLandscapePos()\cellIdx)\gadgetCount > 0
                  RenderCell(gLandscapePos()\cellIdx, gLandscapePos()\x, gLandscapePos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         EndIf

         ; Pass 2: Render lockCorner cells (on top, skip placeholders)
         If gView\orientation = 0
            ForEach gPortraitPos()
               If gPortraitPos()\show And Not gPortraitPos()\placeholder And gView\cells(gPortraitPos()\cellIdx)\lockCorner
                  RenderCell(gPortraitPos()\cellIdx, gPortraitPos()\x, gPortraitPos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         Else
            ForEach gLandscapePos()
               If gLandscapePos()\show And Not gLandscapePos()\placeholder And gView\cells(gLandscapePos()\cellIdx)\lockCorner
                  RenderCell(gLandscapePos()\cellIdx, gLandscapePos()\x, gLandscapePos()\y, gView\cellWidth, gView\cellHeight)
               EndIf
            Next
         EndIf

         ; Show debug panel if debugger is active
         CompilerIf (Defined(PB_Compiler_Debugger, #PB_Constant) And #PB_Compiler_Debugger) Or #LJV_DEBUG
            ShowDebugPanel()
         CompilerEndIf
      EndIf
   EndProcedure

   Procedure ViewClose()
      CompilerIf (Defined(PB_Compiler_Debugger, #PB_Constant) And #PB_Compiler_Debugger) Or #LJV_DEBUG
         CloseDebugPanel()
      CompilerEndIf

      If gView\windowID And IsWindow(gView\windowID)
         CloseWindow(gView\windowID)
         gView\windowID = 0
      EndIf
      gInitialized = #False
   EndProcedure

   Procedure ViewSetOrientation(landscape.i)
      Protected wasShown.i = Bool(gView\windowID And IsWindow(gView\windowID))

      gView\orientation = Bool(landscape)

      If wasShown
         ViewShow(gView\width, gView\height)
      EndIf
   EndProcedure

   Procedure ViewGetOrientation()
      ProcedureReturn gView\orientation
   EndProcedure

   Procedure.i ViewGetWindowID()
      ProcedureReturn gView\windowID
   EndProcedure

EndModule

;- Test Code (standalone execution)
CompilerIf #PB_Compiler_IsMainFile

   ;- LJ Language Syntax (proposed JSON-style):
   ; ==========================================
   ; view loginScreen {
   ;     name: "Login Screen"
   ;     grid: 4, 6
   ;
   ;     range {
   ;         "A2-C2": "header"
   ;         "B5-C5": "loginBtn"
   ;     }
   ;
   ;     cell {
   ;         "A1": {
   ;             type: text
   ;             value: "Welcome!"
   ;             align: center
   ;         }
   ;         "header": {
   ;             type: text
   ;             value: "Please Login"
   ;             align: center
   ;         }
   ;         "B3": {
   ;             type: input
   ;             value: "Username"
   ;             align: left
   ;         }
   ;         "B4": {
   ;             type: input
   ;             value: "Password"
   ;             align: left
   ;         }
   ;         "loginBtn": {
   ;             type: button
   ;             value: "Login"
   ;             align: center
   ;             visible: true
   ;         }
   ;         "D1": {
   ;             type: button
   ;             value: "X"
   ;             align: right | top
   ;             lockCorner: true
   ;         }
   ;     }
   ; }
   ; ==========================================

   ; PureBasic API equivalent:
   LJView::ViewCreate("TestApp", 4, 6, 42)

   LJView::ViewCell("A1", LJView::#LJV_TEXT, "Welcome!", LJView::#LJV_CENTER)
   LJView::ViewCellRange("A2", "C2", LJView::#LJV_TEXT, "Please Login", LJView::#LJV_CENTER)
   LJView::ViewCell("B3", LJView::#LJV_INPUT, "Username", LJView::#LJV_LEFT)
   LJView::ViewCell("B4", LJView::#LJV_INPUT, "Password", LJView::#LJV_LEFT)
   LJView::ViewCellRange("B5", "C5", LJView::#LJV_BUTTON, "Login", LJView::#LJV_CENTER)
   LJView::ViewCell("D1", LJView::#LJV_BUTTON, "X", LJView::#LJV_RIGHT | LJView::#LJV_TOP)

   ; Show the view
   LJView::ViewShow(320, 480)

   ; Event loop
   Define event.i, exitApp.i = #False
   Define eventWindow.i, eventGadget.i
   Define mouseX.i, mouseY.i

   Repeat
      event = WaitWindowEvent()
      eventWindow = EventWindow()
      eventGadget = EventGadget()

      ; Handle debug panel events if debugger is active
      CompilerIf (Defined(PB_Compiler_Debugger, #PB_Constant) And #PB_Compiler_Debugger) Or LJView::#LJV_DEBUG
         If LJView::HandleDebugEvent(event, eventWindow, eventGadget)
            Continue
         EndIf
      CompilerEndIf

      Select event
         Case #PB_Event_CloseWindow
            exitApp = #True

         Case #PB_Event_LeftClick
            ; Handle cell selection (debug mode only)
            CompilerIf (Defined(PB_Compiler_Debugger, #PB_Constant) And #PB_Compiler_Debugger) Or LJView::#LJV_DEBUG
               ; Check if click was on the view window (not debug panel)
               If eventWindow = LJView::ViewGetWindowID()
                  mouseX = WindowMouseX(eventWindow)
                  mouseY = WindowMouseY(eventWindow)
                  If mouseX >= 0 And mouseY >= 0
                     LJView::HandleViewClick(mouseX, mouseY)
                  EndIf
               EndIf
            CompilerEndIf

         Case #PB_Event_Menu
            ; Could add keyboard shortcuts for orientation toggle

      EndSelect

   Until exitApp

   LJView::ViewClose()

CompilerEndIf

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 8
; Folding = --------
; EnableThread
; EnableXP
; CPU = 1
; EnableCompileCount = 48
; EnableBuildCount = 0
; EnableExeConstant