; -- Form Designer
; 
; PBx64 v5.73
;
; 
; 
; 
; 
; 
; Kingwolf71 Mar/2021
; (c) All Rights reserved.
;

; ======================================================================================================
;- Includes
; -=====================================================================================================

DeclareModule LJDesign
   ;Global            _dummy.s
EndDeclareModule

Module LJDesign
   XIncludeFile "..\common\preproc.sbi"

   EnableExplicit
   
   ; ======================================================================================================
   ;- Constants
   ; -=====================================================================================================
   Enumeration
      #MainWindow
      #BtnExit
      #BtnAdd
      #BtnCreate
      #BtnJoin
      #BtnClear
      #BtnLock
      #BtnScreen
      #BtnDelete
      #BtnUpdate
      #BtnRemove
      #BtnLoad
      #BtnSave
      #lvType
      #txtX
      #txtY
      #InpX
      #InpY
      #txtSeed
      #txtChooseScreen
      #InpSeed
      #txtAppName
      #InpAppName
      #txtWidth
      #txtHeight
      #InpWidth
      #InpHeight
      #OptLandscape
      #OptPortrait
      #GridObjects
      #TreeObjects
      #txtDetails
      #txtObjName
      #txtSize
      #txtDefaultText
      #txtAlign
      #txtColour
      #InpObjName
      #InpSize
      #InpDefaultText
      #InpAlign
      #InpColour
      #InpType
      #txtType
      #cbWhite
      #cbGrey
      #cbBlack
      #cbBlue
      #cbOrange
      #cbGreen
      #cbLightGrey
      #cbScreen
      #My_Event_Logging
      #My_Event_Statusbar
      
      #LastGadget
   EndEnumeration
  
   Enumeration
      #GridX
      #GridY
      #X
      #Y
      #Width
      #Height
      #Small
      #Medium
      #Large
      #Extra
      #Huge
      
   EndEnumeration

   Enumeration
      #LJD_Screens
      #LJD_Container
      #LJD_Details
   EndEnumeration

   #LJD_MAXGRIDLINES    = 12
   #LJD_MINTEXTSIZE     = 8
   #LJD_PARAMETERS      = 20
   #LJD_WindowWidth     = 510
   #LJD_WindowHeight    = 555 ;540
   #LJD_DetailsWidth    = 160
   ;#LJD_PanelWidth      = 450
   #LJD_PanelWidth      = #LJD_WindowWidth - 20
   #LJD_ButtonsHeight   = 170 ; 140
   #LJD_TextLabelW      = 80
   #LJD_TextLabelH      = 24  ;24
   #LJD_2NDROW          = 50 + (#LJD_TextLabelW*2)
   #LJD_3RDDROW         = 100 + (#LJD_TextLabelW*4)
   #LJD_TREEWIDTH       = 180 ; 150
   #LJD_MAXOBJECTS      = 55
   #LJD_MINOBJECTS      = 2
   #LJD_MAXSCREENS      = 48
  
   #EventDataID         = $FFFFAAAA
   ; ======================================================================================================
   ;- Structures
   ; -=====================================================================================================
   Structure      stTemp
      last.i
      List  ll.i()
   EndStructure
   Structure      stGrid
      i.l
      bFlag.w
      bLock.w
   EndStructure
   Structure      stTree  
      code.s
      NodeType.w
      pos.w
      *prev.stTree
      screen.w
   EndStructure
   Structure      stCount
      count.i
      x.u
      y.u
   EndStructure
   Structure      stBox
      x.l
      y.l
      w.l
      h.l
      ow.l
      oh.l
   EndStructure
   Structure      stObject
      type.l
      size.l
      objName.s
      Value.s
      alignment.l
   EndStructure
   Structure      stCont
      bFlag.l
      id.i
      color.i
      image.i
      pressed.i
      imgID.i
      objName.s
      key.s
      objcolor.l
      maxObj.l
      currObj.l
      *slave
      bIsPressed.w
      bLock.w
      GroupID.w
      Array    box.stBox(2)
      Array    Obj.stObject(#LJD_MINOBJECTS)
   EndStructure
   Structure      stScreen
      x.l
      y.l
      gridx.l
      gridy.l
      width.i
      height.i
      ScreenName.s
      ;Array    box.stBox(2)
      Array    params.l(#LJD_PARAMETERS,2)
      Map      mapCont.stCont()
   EndStructure
   Structure      stApp
      AppName.s
      Seed.i
      winid.i
      Orientation.l
      Screen.l
      TotScreens.l
      Array    scr.stScreen(#LJD_MAXSCREENS)
   EndStructure
   Structure      stGrid2
      coord.s
      i.l
      j.l
   EndStructure
   ; ======================================================================================================
   ;- Macros
   ; ======================================================================================================
   Macro                 APM
      appInfo\scr(appInfo\Screen)\mapCont()
   EndMacro
   Macro                 APS
      appInfo\scr(appInfo\Screen)
   EndMacro
   Macro                BlockNewApp(onoff)
      DisableGadget(#InpWidth,onoff)
      DisableGadget(#InpHeight,onoff)
      DisableGadget(#InpAppName,onoff)
      
      If onoff
         DisableGadget(#BtnJoin,0)
         DisableGadget(#BtnLock,0)
         DisableGadget(#BtnClear,0)
      Else
         DisableGadget(#BtnJoin,1)
         DisableGadget(#BtnLock,1)
         DisableGadget(#BtnClear,1)
      EndIf
   EndMacro
   Macro                AddNode()
      AddElement( llNodes() )
      llNodes() = *p
   EndMacro
   Macro                ClearGridInfo()
      For j = 0 To #LJD_MAXGRIDLINES
         For i = 0 To #LJD_MAXGRIDLINES
            arGrid(i,j)\i     = -1
            arGrid(i,j)\bFlag = 0
         Next
      Next
   EndMacro
   Macro                RemoveSubTree()
      ForEach llNodes()
         *t = llNodes()
         If *t\NodeType = #LJD_Details And *t\Screen = AppInfo\Screen
            If *t\prev = *v
               FreeStructure(*t)
               DeleteElement(llNodes())
            EndIf
         EndIf
      Next
   EndMacro
   Macro                AllowAdd(onoff)
      DisableGadget(#lvType, onoff)
      DisableGadget(#BtnAdd, onoff)
      DisableGadget(#BtnUpdate, onoff)
      DisableGadget(#BtnRemove, onoff)
      ;DisableGadget(#BtnLock, onoff)
      ;DisableGadget(#BtnClear, onoff)
      ;DisableGadget(#BtnJoin, onoff)
   EndMacro
   Macro                MakeGrid()
      ;Make grid
      ;DrawingMode(#PB_2DDrawing_Outlined )
      ;DrawingMode(#PB_2DDrawing_XOr )
      diamondfield(2,16,10,$202020)
      ;diamondfield(2,16,10,$808080)
      ;For x1 = 2 To tw Step
      ;   For y1 = 16 To th Step 6
      ;      Line(2,y1,tw,1,$C4B3AB)
      ;     Line(x1,16,1,th,$C4B3AB)
      ;   Next
      ;Next
   EndMacro
   Macro                TreeInfoAllow(segment)
      CompilerIf segment=1
         DisableGadget(#InpAlign, 0)
         DisableGadget(#InpSize, 0)
         DisableGadget(#InpColour, 1)
         DisableGadget(#InpDefaultText, 0)
         DisableGadget(#InpObjName, 0)
      CompilerElseIf segment=2
         DisableGadget(#InpAlign, 1)
         DisableGadget(#InpSize, 1)
         DisableGadget(#InpColour, 0)
         DisableGadget(#InpDefaultText, 1)
         DisableGadget(#InpObjName, 0)
      CompilerElseIf segment=3
         DisableGadget(#InpAlign, 1)
         DisableGadget(#InpSize, 1)
         DisableGadget(#InpColour, 1)
         DisableGadget(#InpDefaultText, 1)
         DisableGadget(#InpObjName, 0)
      CompilerElse
         DisableGadget(#InpAlign, 1)
         DisableGadget(#InpSize, 1)
         DisableGadget(#InpColour, 1)
         DisableGadget(#InpDefaultText, 1)
         DisableGadget(#InpObjName, 1)
      CompilerEndIf
   EndMacro
   Macro                MakeImage(id,color)
        CreateImage(id,64,64)
        StartDrawing(ImageOutput(id))
        Box(0,0,64,64,color)
        StopDrawing()
   EndMacro
   Macro                TxtGadget(det,y,text)
      TextGadget(det, #LJD_TREEWIDTH+10,75+y,90,#LJD_TextLabelH,text)
      SetGadgetColor(det,#PB_Gadget_BackColor,$ADADAD)
      ;SetGadgetColor(#txtDetails,#PB_Gadget_FrontColor,#White)
   EndMacro
   Macro                _RndColor()
      Random(255, Random(80,48))
      ;Random(255, 64)
   EndMacro
   Macro                IfNotWide(result,size)
      If result
         result = (result + 1) * size
      Else
         result = size
      EndIf
   EndMacro
   Macro                NewVal()
      k + 1 : AddElement(llVals()) : llVals() = k
   EndMacro
   Macro                DebugCoords(mytext)
      ;debug check
      Debug "----[ " +mytext+ " ]---------------------------------"
      For j = 1 To maxj
         temp = ""
         For i = 1 To maxi
            temp + "[ "+RSet(Str(arGrid(i,j)\i),2,"0") +" ]  "
         Next
         
         Debug "("+Str(j)+") "+temp
      Next
      Debug "-------------------------------------------"
   EndMacro
   ; ======================================================================================================
   ;- Globals
   ; -=====================================================================================================
   Global               gszTitle.s           = "LJ Editor - V1.00"
   Global               gszDefaultMaxX.s     = "300"
   Global               gszDefaultMaxY.s     = "600"
   Global               gszScreenBase.s      = "Screen"
   
   Global               gLastObject
   Global               gSmallFont
   
   Global               appInfo.stApp
   Global NewList       llNodes()
   Global NewMap        mapSmallButtons(3361)
   
   Global Dim           arGrid.stGrid(#LJD_MAXGRIDLINES,#LJD_MAXGRIDLINES)
   Global Dim           arObjects.s(20)
   ; ======================================================================================================
   ;- Declarations
   ; -=====================================================================================================  
   Declare              RedrawApp(bReset = 0)
   Declare              MakeNode(NodeType, code.s, *prev.stTree, screen, pos = -1)
   ; ======================================================================================================
   ;- Functions
   ; -=====================================================================================================  
   Procedure diamondfield(cx,cy,rayon,color=$ffffff)  
      Protected   x, x1, y, y1
   
     x = -1000 + cx
     y = cy
     x1 = x + 600
     y1 = y + 600
     
     While x1 < 3000 
       
       x1 = x1 + rayon
       x = x + rayon
       
       LineXY(x,y,x1,y1,color) 
       LineXY(x,y1,x1,y,color) 
     Wend 
   EndProcedure
   Procedure            Intersect(*r1.stBox, *r2.stBox)
      Protected         w, h
      
      w = *r2\x + *r2\w
      h = *r2\y + *r2\h
   
      If (w > *r1\x) And (w <= *r1\x+*r1\w)
         ProcedureReturn 1
      EndIf
      
      If (h > *r1\y) And (h <= *r1\y+*r1\h)
         ProcedureReturn 1
      EndIf
      
      w = *r1\x + *r1\w
      h = *r1\y + *r1\h
      
      If (w > *r2\x) And (w <= *r2\x+*r2\w)
         ProcedureReturn 1
      EndIf
      
      If (h > *r2\y) And (h <= *r2\y+*r2\h)
         ProcedureReturn 1
      EndIf
   
      ProcedureReturn 0
   EndProcedure
   Procedure            rndCol()
      Protected.i       r, g ,b
      Protected.i       i, j
      Static.i          _r, _g, _b
      
      j = _r + _g + _b
      
      Repeat
         r = Random(255, Random(128,70))
         g = Random(255, Random(128,70))
         b = Random(255, Random(128,70))
         i = r + g + b
         
      Until Abs(i - j) > 64
      
      _r = r : _g = g : _b = b
      ProcedureReturn RGB(r,g,b)
   EndProcedure
   Procedure            RedrawButtons(screen)
      
      
   EndProcedure
   Procedure            SavePressed()
      Protected         i, j
      Protected         xml = CreateXML(#PB_Any)
      
      
      
      For i = 0 To appInfo\TotScreens
      
      
      Next
      
      FreeXML(xml)
   EndProcedure
   Procedure            SmallButtonClick()
      Protected         id.s
      Protected         *ptr.stCont
   
      Debug "SmallButtonClicked"
      
      id = Str(EventGadget())
      
      If FindMapElement(mapSmallButtons(),id)
         *ptr = mapSmallButtons()
         If *ptr
            Debug *ptr\key
            *ptr\bIsPressed = GetGadgetState(Val(MapKey(mapSmallButtons())))
         EndIf
      EndIf
      
   EndProcedure
   Procedure            AddPressed()
      Protected.i       i,j,k
      Protected.s       temp,coords
      Protected.stTree  *v
      
      i = GetGadgetState(#lvType)
      j = GetGadgetState(#TreeObjects)
      
      If j > -1
         *v             = GetGadgetItemData(#TreeObjects,j)
         temp           = arObjects(i)
         coords         = *v\code
         appInfo\Screen = *v\screen
         
         ;Debug "Screen->" + Str(*v\screen)
         ;Debug "Adding to-->"+coords +" ("+Str(j)+")"
         
         If FindMapElement(APM,*v\code)
            k        = APM\currObj
            
            If k + 1 > APM\maxObj
               MessageRequester(gszTitle,"Max objects per container",#PB_MessageRequester_Warning)
            Else
               APM\currObj + 1
               gLastObject + 1
               temp + Str(gLastObject)
               APM\obj(k)\type      = i
               APM\obj(k)\size      = 0
               APM\obj(k)\objName   = temp
               APM\obj(k)\Value     = ""
               APM\obj(k)\alignment = 0
    
               AddGadgetItem(#TreeObjects,j+1,temp,0,#LJD_Details)
               *v = MakeNode(#LJD_Details,coords,*v,*v\screen)
               *v\pos = k
               SetGadgetItemData(#TreeObjects,j+1, *v)
            EndIf
         Else
            Debug "Did not find --> "+coords
         EndIf
      EndIf
   
   EndProcedure
   ; Delete Screen
   Procedure            DeletePressed()
   
      If appInfo\TotScreens > 1
      
      Else
      
      EndIf
      
      If appInfo\TotScreens = 0
         DisableGadget(#BtnLock, 1)
         DisableGadget(#BtnClear, 1)
         DisableGadget(#BtnJoin, 1)
      EndIf
   
   EndProcedure
   Procedure            RemovePressed()
      Protected.i       i,j,k
      Protected.stTree  *p, *v, *t
      Protected.s       temp
      
      i = GetGadgetState(#TreeObjects)
      If i > -1
         j = GetGadgetItemAttribute(#TreeObjects,i, #PB_Tree_SubLevel)
         
         If j = #LJD_Details     ;Should not be required, but....
            *v = GetGadgetItemData(#TreeObjects,i)
            FindMapElement(APM,*v\code)
            k = *v\pos
            *p = *v\prev
            RemoveGadgetItem(#TreeObjects,i)
            
            ForEach llNodes()
               *t = llNodes()
               If *t\NodeType = #LJD_Details And *t\Screen = AppInfo\Screen
                  If *t = *v
                     FreeStructure(*t)
                     DeleteElement(llNodes())
                     *t = NextElement(llNodes())
                     
                     If *t
                        *t\prev = *p
                     EndIf
                     Break
                  EndIf
               EndIf
            Next
            
            Debug k
            Debug APM\CurrObj
            
            If k < APM\CurrObj - 1
               For i = k + 1 To APM\CurrObj - 1
                  CopyStructure(APM\Obj(i),APM\Obj(i-1),stObject)
               Next
            EndIf
            
            APM\CurrObj - 1
         EndIf
      EndIf
   EndProcedure
   Procedure            UpdatePressed()
      Protected.i       i,j,k
      Protected         *p.stTree
      Protected.s       temp
      
      i = GetGadgetState(#TreeObjects)
      If i > -1
         j = GetGadgetItemAttribute(#TreeObjects,i, #PB_Tree_SubLevel)
         
         If j = #LJD_Screens
            temp = Trim(GetGadgetText(#InpObjName))
            SetGadgetItemText(#TreeObjects,i,temp)
            APS\ScreenName = temp
         Else
            *p = GetGadgetItemData(#TreeObjects,i)
            FindMapElement(APM,*p\code)
            
            If j = #LJD_Container
               temp = Trim(GetGadgetText(#InpObjName))
               If temp > "" : APM\objName = temp : EndIf
               APM\objcolor = GetGadgetState(#InpColour)
               SetGadgetItemText(#TreeObjects,i,temp)
            Else
               k = *p\pos
               APM\obj(k)\size      = GetGadgetState(#InpSize)
               APM\obj(k)\objName   = Trim(GetGadgetText(#InpObjName))
               APM\obj(k)\Value     = Trim(GetGadgetText(#InpDefaultText))
               APM\obj(k)\alignment = GetGadgetState(#InpAlign)
               SetGadgetItemText(#TreeObjects,i,APM\obj(k)\objName)
            EndIf
         EndIf
      EndIf
   EndProcedure
   Procedure            TreeClick()
      Protected.i       i,j,k
      Protected         *p.stTree
      
      If EventType() = #PB_EventType_LeftClick
         i = GetGadgetState(#TreeObjects)
         If i = -1
            TreeInfoAllow(4)
            AllowAdd(1)
         Else
            j = GetGadgetItemAttribute(#TreeObjects,i, #PB_Tree_SubLevel)
            *p = GetGadgetItemData(#TreeObjects,i)
            appInfo\Screen = *p\screen
           
            If j = #LJD_Screens
               TreeInfoAllow(3)
               AllowAdd(1)
               DisableGadget(#BtnUpdate, 0)
               DisableGadget(#BtnRemove, 1)
               SetGadgetText(#InpObjName,APS\ScreenName)
               SetGadgetState(#InpColour,0)
               SetGadgetText(#InpType,"Screen")
               
               Debug "Screen clicked"
            ElseIf j = #LJD_Container
               TreeInfoAllow(2)
               AllowAdd(0)
               DisableGadget(#BtnRemove, 1)
               SetGadgetText(#InpType,"Container")

               If FindMapElement(APM,*p\code)
                  SetGadgetText(#InpObjName,APM\objName)
                  SetGadgetState(#InpColour,APM\objcolor)
               EndIf
            Else
               TreeInfoAllow(1)
               AllowAdd(1)
               DisableGadget(#BtnUpdate, 0)
               DisableGadget(#BtnRemove, 0)
               
               If FindMapElement(APM,*p\code)
                  k = *p\pos
                  Debug "Find -> "+*p\code+" ("+Str(k)+")"
                  
                  SetGadgetText(#InpObjName,APM\obj(k)\objName)
                  SetGadgetText(#InpDefaultText,APM\obj(k)\Value)
                  SetGadgetText(#InpType,arObjects(APM\obj(k)\type))
                  SetGadgetState(#InpAlign,APM\obj(k)\alignment)
                  SetGadgetState(#InpSize,APM\obj(k)\size)
               Else
                  Debug "Did not find->"+*p\code
               EndIf
            EndIf
         EndIf
      EndIf
   EndProcedure
   Procedure            CheckAdjacent(x,y)
      ;2 - Change but stop loop
      ;1 - Change continue loop
      ;0 Stop
      ;Debug "Checking: " + Str(x) + " / " + Str(y) + " ("+Str(arGrid(x,y)) +")"
      If arGrid(x,y)\i = 1
         ProcedureReturn 2
      ElseIf arGrid(x,y)\i = 0
         ProcedureReturn 0
      Else
         If x > 1
            If arGrid(x-1,y)\i = arGrid(x,y)\i
               ProcedureReturn 0
            EndIf
         EndIf
         
         If x < #LJD_MAXGRIDLINES
            If arGrid(x+1,y)\i = arGrid(x,y)\i
               ProcedureReturn 0
            EndIf
         EndIf
      EndIf
      
      ProcedureReturn 1
   EndProcedure
   Procedure            CheckBlock(x,y)
      Protected         i, j, l, m
      Protected         flag = 0
      ; 0 - No horizontal block in the next line
      ;Debug "Checking: " + Str(x) + " / " + Str(y) + " ("+Str(arGrid(x,y)) +")"
      
      i = x + 1 : j = y + 1
      m = arGrid(x,j)\i
      l = 0
      
      While i < #LJD_MAXGRIDLINES
         If arGrid(i,y)\i = arGrid(x,y)\i
            l + 1
            If m
               If arGrid(i,j)\i <> m : flag + 1 : EndIf
            EndIf
         Else : Break : EndIf
         i + 1
      Wend
      
      If m And flag = 0 And l
         m = x + l
         For i = x To m
            arGrid(i,j)\i = arGrid(x,y)\i
         Next
      EndIf
      
      ProcedureReturn l
   EndProcedure
   Procedure            LockPressed()
      ForEach APM
         With appInfo\scr(appInfo\Screen)\mapCont()
            If \bIsPressed
               \bIsPressed + 1
               \bLock = 1
            EndIf
         EndWith   
      Next
   EndProcedure
   Procedure            JoinPressed()
      Protected         i, j, k, l, m
      Protected         i1, j1
      Protected         w, h, nw1, nh1, nw2, nh2
      Protected         *p.stCont
      Protected         maxi, maxj, posi, posj, totcont
      Protected         status
      Protected.s       temp
      Protected NewList llVals()
      Protected NewList llDelete.stCount()
      Protected Dim     arCount.stCount(#LJD_MAXGRIDLINES*#LJD_MAXGRIDLINES)
      Protected Dim     arCont.stGrid2(120)
      
      Debug "[JoinPressed] Screen->"+ Str(appInfo\Screen)
      
      ClearGridInfo()

      ;We build an array of container names
      For j = 1 To #LJD_MAXGRIDLINES
         For i = 1 To #LJD_MAXGRIDLINES
            temp = Str(appInfo\Screen)+"/"+Str(i)+"/"+Str(j)
            
            If FindMapElement(APM,temp)
               arCont(totcont)\coord   = temp
               arCont(totcont)\i       = i
               arCont(totcont)\j       = j
               totcont + 1
               
               If i > maxi : maxi = i : EndIf
               If j > maxj : maxj = j : EndIf
            EndIf
         Next
      Next

      ;we make sure that every container in a group has same pressed status
      For i = 0 To totcont - 1
         *p = FindMapElement(APM,arCont(i)\coord)
         If APM\slave = 0 And APM\GroupID > 0 And APM\bIsPressed > 0 And APM\bLock = 0
            For j = 0 To totcont - 1
               If j <> i
                  FindMapElement(APM,arCont(j)\coord)
                  If APM\GroupID = *p\GroupID
                     APM\bIsPressed = *p\bIsPressed
                  EndIf
               EndIf
            Next
         EndIf
      Next

      ;Now we make a XbyY grid to easier navigate it
      For i = 0 To totcont - 1
         FindMapElement(APM,arCont(i)\coord)
         If APM\bLock = 0
            If APM\bIsPressed = 1
               arGrid(arCont(i)\i,arCont(i)\j)\i      = 1
            Else
               arGrid(arCont(i)\i,arCont(i)\j)\i = 0
            EndIf
         Else
            arGrid(arCont(i)\i,arCont(i)\j)\bLock = APM\bLock
         EndIf
      Next
      
      ;First pass 
      ;find connected blocks (horizontal)
      k = 1 : NewVal()
      
      For j = 1 To maxj
         For i = 1 To maxi
            If arGrid(i,j)\i > 0
               If i = maxi
                  arGrid(i,j)\i = k : NewVal()
               ElseIf arGrid(i+1,j)\i > arGrid(i,j)\i
                  arGrid(i,j)\i = arGrid(i+1,j)\i
               Else
                  arGrid(i,j)\i = k : NewVal()
                  For l = i + 1 To maxi
                     If arGrid(l,j)\i < 1 : Break : EndIf
                     If arGrid(l,j)\i > 0 : arGrid(l,j)\i = arGrid(i,j)\i : EndIf
                  Next
               
                  i = l
               EndIf
            EndIf
         Next
      Next
      
      ;DebugCoords("First pass")
      ;Second pass 
      ;find connected blocks (vertical)
      For j = 1 To maxj - 1
         For i = 1 To maxi
            If arGrid(i,j)\i = 1 And arGrid(i,j+1)\i = 1
               arGrid(i,j)\i = k : arGrid(i,j+1)\i = k : NewVal()
               For l = j + 2 To maxj
                  If arGrid(i,l)\i <> 1 And arGrid(i,l)\bLock = 0 : Break : EndIf
                  arGrid(i,l)\i = arGrid(i,j)\i
               Next
            EndIf
         Next
      Next
 
      ;DebugCoords("Second pass")
      ;Third pass - Remove single elements
      l        = k + 1
      DeleteElement(llVals())
      
      ForEach llVals()
         k = 0 : status = 0
         For j = 1 To maxj
            For i = 1 To maxi
               If arGrid(i,j)\i = llVals() 
                  If k = 0
                     k + 1
                     posi = i : posj = j
                     status = 1
                  Else
                     status = 0
                     Break
                  EndIf
               EndIf
            Next
         Next
         
         If status
            status = 0
            ;Debug "Analyzing: " + Str(llVals())

            If posj > 1
               For j = posj - 1 To 1 Step -1
                  k = CheckAdjacent(posi,j)
                  ;Debug "k = "+Str(k)
                  If Not k
                     Break
                  ElseIf k
                     arGrid(posi,j)\i = arGrid(posi,posj)\i
                     If k = 2 : Break : EndIf
                     status + 1
                  EndIf
               Next   
            EndIf

            If posj < maxj   
               For j = posj + 1 To maxj
                  k = CheckAdjacent(posi,j)
                  ;Debug "k = "+Str(k)
                  If Not k
                     Break
                  ElseIf k
                     arGrid(posi,j)\i = arGrid(posi,posj)\i
                     If k = 2 : Break : EndIf
                     status + 1
                  EndIf
               Next
            EndIf
            
            ;Debug "status="+Str(status)
            If Not status
               arGrid(posi,posj)\i = 0
            EndIf
         EndIf
      Next
      
      ;4th pass: join horizontal blocks
      For j = 1 To maxj - 1
         For i = 1 To maxi - 1
            If arGrid(i,j)\i
               k = CheckBlock(i,j)
               If k : i + k : EndIf
            EndIf
         Next
      Next
      
      ;5th pass: remove isolated blocks and find coords of blocks
      l = 0
      For j = 1 To maxj
         For i = 1 To maxi
            k = arGrid(i,j)\i
            If k > 0
               status = 0
               If i > 1 : If arGrid(i-1,j)\i = k : status + 1 : EndIf : EndIf
               If i < maxi : If arGrid(i+1,j)\i = k : status + 1 : EndIf : EndIf
               If j > 1 : If arGrid(i,j-1)\i = k : status + 1 : EndIf : EndIf
               If j < maxj : If arGrid(i,j+1)\i = k : status + 1 : EndIf : EndIf
               
               If status   
                  If k > l : l = k : EndIf
                  arCount(k)\count + 1
                  
                  If arCount(k)\count = 1
                     arCount(k)\x = i
                     arCount(k)\y = j
                  EndIf
               Else
                  AddElement(llDelete())
                  llDelete()\x = i : llDelete()\y = j
               EndIf
            EndIf
         Next
      Next

      ForEach llDelete()
         With llDelete()
            arGrid(\x,\y)\i = 0
         EndWith
      Next

      w = APS\x : h = APS\y
      
      For m = 2 To l
         With arCount(m)
            If \count > 1
               ;x,y is top left corner
               k = 0
               For j = \y To maxj
                  For i = \x To maxi
                     If arGrid(i,j)\i = m : k + 1 : EndIf
                     If k = \count
                        temp = Str(appInfo\Screen)+"/"+ Str(\x)+"/"+Str(\y)
                        *p = FindMapElement(APM,temp)
                        nw1 = i - \x : nh1 = j - \y
                        nw2 = nh1 : nh2 = nw1
                        
                        IfNotWide(nw1,w)
                        IfNotWide(nh1,h)
                        IfNotWide(nw2,w)
                        IfNotWide(nh2,h)

                        For j1 = j To \y Step -1
                           For i1 = i To \x Step -1
                              temp = Str(appInfo\Screen)+"/"+Str(i1)+"/"+Str(j1)
                              FindMapElement(APM,temp)
                              APM\slave = *p
                           Next
                        Next
                        
                        *p\slave = 0
                        *p\Box(0)\w   = nw1
                        *p\Box(0)\h   = nh1
                        *p\Box(1)\w   = nh2
                        *p\Box(1)\h   = nw2
                        i = maxi : j = maxj
                        Break
                     EndIf
                  Next
               Next
            EndIf
         EndWith
      Next 

      For i = 0 To totcont - 1
         FindMapElement(APM,arCont(i)\coord)
         APM\bIsPressed = 0
         
         If arGrid(arCont(i)\i,arCont(i)\j)\i > 0
            APM\GroupID    = arGrid(arCont(i)\i,arCont(i)\j)\i + 1
         EndIf
      Next

      DebugCoords("End result")
      RedrawApp()
   EndProcedure
   Procedure            FindPosInTree(coords.s)
      Protected         i,k
      Protected         *p.stTree
      
      k = CountGadgetItems(#TreeObjects)
      For i = 0 To k
         *p = GetGadgetItemData(#TreeObjects,i)
         
         If *p And coords = *p\code
            ProcedureReturn i
            Break
         EndIf
      Next
      
      Debug "Did not find -> " + coords
      ProcedureReturn -1
   EndProcedure
   Procedure            ClearPressed()
      Protected         i, j
      Protected.s       temp
      Protected.stCont  *p, *v
   
      For j = 0 To #LJD_MAXGRIDLINES
         For i = 0 To #LJD_MAXGRIDLINES
            arGrid(I,J)\i = -1
            arGrid(i,j)\bFlag = 0
            temp = Str(appInfo\Screen)+"/"+Str(i)+"/"+Str(j)
            
            If FindMapElement(APM,temp)
               APM\Box(0)\w = APM\Box(0)\ow
               APM\Box(1)\w = APM\Box(1)\ow
               APM\Box(0)\h = APM\Box(0)\oh
               APM\Box(1)\h = APM\Box(1)\oh
               
               APM\Slave      = 0
               APM\bIsPressed = 0
               APM\GroupID    = 0
               APM\bLock      = 0
            EndIf
         Next
      Next
      
      RedrawApp(1)
   EndProcedure
   Procedure            ExtractNumberFromEnd(string.s)
      Protected         i, j, found = 0
      Protected         Character$
      Protected         NumberString$
    
      j = Len(String)
    
      For i=j To 1 Step -1
         Character$ = Mid(String, i, 1)
         If Asc(Character$) > 47 And Asc(Character$) < 58
            found = i
         Else
            Break
         EndIf
      Next
      
      ProcedureReturn found
   EndProcedure
   Procedure            RedrawApp(bReset = 0)
      Debug "-- RedrawApp --"
      
      Protected         w,h,x,y,x1,y1
      Protected         i,j,k,l
      Protected         th, tw, cx, cy
      Protected         orientation
      Protected.s       coords, temp
      Protected         maxobj, pos, mapid, total
      Protected         *p.stCont
      Protected.stTree  *v, *t
      Protected Dim     *arP.stCont(120)

      ;Free all objects related to each position
      ForEach APM
         With appInfo\scr(appInfo\Screen)\mapCont()
            *arP(total) = APM
            total + 1
            
            If Not \slave
               If IsGadget(\imgID)
                  UnbindGadgetEvent(\imgID, @SmallButtonClick())
                  If IsImage(\image)   : FreeImage(\image)   : EndIf
                  If IsImage(\pressed) : FreeImage(\pressed) : EndIf
                  FreeGadget(\imgID)
               EndIf
            EndIf
         EndWith   
      Next

      If Not bReset
         ;This is a bug fix - find if any block intersects and reset if it does
        
         ;Second order of business is to consolidate all objects
         ForEach APM
            With appInfo\scr(appInfo\Screen)\mapCont()
               If \slave
                  *p = \slave
                  i = *p\maxObj * 2
                  ReDim *p\Obj(i)
                  *p\maxObj = i
                  *p\bFlag = 1
                  k = FindPosInTree(*p\key)
                  
                  If \currObj
                     For i = 0 To \currObj - 1
                        CopyStructure(\Obj(i),*p\Obj(*p\currObj),stObject)
                        *p\currObj + 1
                     Next
                  EndIf
   
                  \currObj = 0
                  k = FindPosInTree(\key)
                  *v = GetGadgetItemData(#TreeObjects,k)
                  If k > -1
                     RemoveGadgetItem(#TreeObjects,k)
                  EndIf
   
                  RemoveSubTree()
               EndIf
            EndWith
         Next
         
         ForEach APM
            If APM\bFlag
               With appInfo\scr(appInfo\Screen)\mapCont()
                  \bFlag = 0
   
                  l = FindPosInTree(\key)
                  i = l + 1
                  *v = GetGadgetItemData(#TreeObjects,l)
                  RemoveSubTree()
   
                  While #True
                     j = GetGadgetItemAttribute(#TreeObjects,i, #PB_Tree_SubLevel)
                     If j <> #LJD_Details : Break : EndIf
                     RemoveGadgetItem(#TreeObjects,i)
                  Wend
               
                  For i = 0 To \currObj - 1
                     AddGadgetItem(#TreeObjects,l+1,\Obj(i)\objName,0,#LJD_Details)
                     *p = MakeNode(#LJD_Details,\key,*v,*v\screen,i)
                     SetGadgetItemData(#TreeObjects,l+1, *p)
                  Next
               EndWith
            EndIf
         Next
      EndIf
      
      x = APS\width  / APS\gridx
      y = APS\height / APS\gridy
      w = APS\width
      h = APS\height
      orientation = appInfo\Orientation
      RandomSeed(appInfo\Seed)
      
      If appInfo\winid And IsWindow(appInfo\winid)
         CloseWindow(appInfo\winid)
      EndIf
   
      temp = appInfo\AppName + " (" + appInfo\scr(appInfo\Screen)\ScreenName +")"
   
      If appInfo\Orientation
         appInfo\winid = OpenWindow(#PB_Any,WindowX(#MainWindow)+#LJD_WindowWidth+5,WindowY(#MainWindow),h,w,temp)
      Else
         appInfo\winid = OpenWindow(#PB_Any,WindowX(#MainWindow)+#LJD_WindowWidth+5,WindowY(#MainWindow),w,h,temp)
      EndIf
      
      If appInfo\winid
         i     = APS\gridx * APS\gridy
         maxobj= #LJD_MAXOBJECTS / i
         If maxobj < #LJD_MINOBJECTS : maxobj = #LJD_MINOBJECTS : EndIf

         ForEach APM
            With appInfo\scr(appInfo\Screen)\mapCont()
               If Not \slave Or bReset
                  tw       = \Box(orientation)\w
                  th       = \Box(orientation)\h
                  cx       = \Box(orientation)\x
                  cy       = \Box(orientation)\y
                  \maxObj  = maxobj*3
                  coords = MapKey(APM)
                  mapid  = APM

                  \id         = ContainerGadget(#PB_Any,cx, cy,tw, th)
                  \image      = CreateImage(#PB_Any, tw,th)
                  StartDrawing( ImageOutput( \image ) )
                  Box( 0, 0, tw, th, \color )
                  
                  DrawingMode(#PB_2DDrawing_Default)
                  DrawText(4, 2,"("+coords+")", #Black,#Yellow)
                  StopDrawing()
                  
                  \pressed = CreateImage(#PB_Any, tw,th)
                  StartDrawing( ImageOutput( \pressed ) )
                  DrawingMode(#PB_2DDrawing_Outlined)
                  DrawAlphaImage(ImageID(\image), 0, 0,160)
                  MakeGrid()
                  StopDrawing()
                  
                  \imgID       = ButtonImageGadget(#PB_Any, 0, 0, tw, th,ImageID( \image ),#PB_Button_Toggle)
                  SetGadgetAttribute(\imgID,#PB_Button_PressedImage,ImageID(\pressed))
                  SetGadgetState(\imgID, \bIsPressed)
                  
                  BindGadgetEvent(\imgID, @SmallButtonClick())
                  temp = Str(\imgID)
                  
                  If Not FindMapElement(mapSmallButtons(),temp)
                     AddMapElement(mapSmallButtons(),temp,#PB_Map_NoElementCheck)
                  EndIf
                  
                  mapSmallButtons() = mapid
                  CloseGadgetList()
               EndIf
            EndWith
         Next
      EndIf
   EndProcedure
   Procedure            CreateScreen()
      Protected         w,h,x,y,x1,y1
      Protected         l,m,s,xtra,huge
      Protected         i, j, k
      Protected         maxobj, pos, mapid
      Protected         container, orientation
      Protected         gridx, gridy
      Protected         cx1, cy1, cx2, cy2,tw, th
      Protected.stTree  *p, *v
      Protected.s       coords
      Protected.s       temp
   
      Debug "-- CreateScreen --"
      AllowAdd(0)
   
      w              = Val(GetGadgetText(#InpWidth))
      h              = Val(GetGadgetText(#InpHeight))
   
      If appInfo\TotScreens = 0
         ExamineDesktops()
         appInfo\AppName   = Trim(GetGadgetText(#inpAppName))
         appInfo\Screen    = 0
         appInfo\TotScreens= 1
         pos               = 0
         BlockNewApp(1)
         RandomSeed(appInfo\Seed)
      Else
         If appInfo\winid
            CloseWindow(appInfo\winid)
            appInfo\winid = 0
         EndIf
         
         appInfo\Screen    = appInfo\TotScreens
         appInfo\TotScreens+ 1
         pos               = CountGadgetItems(#TreeObjects)
      EndIf
      
      appInfo\Seed   = Val(GetGadgetText(#InpSeed))
      orientation    = appInfo\Orientation
      gridx          = Val(GetGadgetText(#InpX))
      gridy          = Val(GetGadgetText(#Inpy))
      If w = 0 : w = DesktopWidth(0)  : EndIf
      If h = 0 : h = DesktopHeight(0) : EndIf
      
      With appInfo\scr(appInfo\Screen)
         \gridx      = gridx
         \gridy      = gridy
         \width      = w
         \height     = h
         \ScreenName = gszScreenBase + Str(appInfo\Screen+1)
      EndWith
      
      temp = appInfo\AppName + " (" + appInfo\scr(appInfo\Screen)\ScreenName +")"
   
      If orientation
         appInfo\winid = OpenWindow(#PB_Any,WindowX(#MainWindow)+#LJD_WindowWidth+5,WindowY(#MainWindow),h,w, temp)
      Else
         appInfo\winid = OpenWindow(#PB_Any,WindowX(#MainWindow)+#LJD_WindowWidth+5,WindowY(#MainWindow),w,h,temp)
      EndIf
      
      If appInfo\winid
         x           = w / gridx
         y           = h / gridy
         APS\x       = x
         APS\y       = y
         xtra        = y * 1.3
         huge        = y * 2.1
         l           = y * 0.85
         m           = y * 0.45
         s           = y / 3
         If s < #LJD_MINTEXTSIZE : s = #LJD_MINTEXTSIZE : EndIf

         With appInfo\scr(appInfo\Screen)
            \params(#GridX,0) = gridx  : \params(#GridX,1) = gridy
            \params(#GridY,0) = gridy  : \params(#GridY,1) = gridx
            \params(#x,0) = x          : \params(#Y,1) = y
            \params(#y,0) = y          : \params(#x,1) = x
            \params(#Width,0) = w      : \params(#Width,1) = h
            \params(#Height,0) = h     : \params(#Height,1) = w
            \params(#Large,0) = l      : \params(#Large,1) = l
            \params(#Medium,0) = m     : \params(#Medium,1) = m
            \params(#Small,0) = s      : \params(#Small,1) = s
            \params(#Extra,0) = xtra   : \params(#Extra,1) = xtra
            \params(#Huge,0) = huge    : \params(#Huge,1) = huge
         EndWith
      
         If MapSize(APM) > 0
            ClearMap(APM)
         EndIf
         
         i     = gridx * gridy
         maxobj= #LJD_MAXOBJECTS / i
         If maxobj < #LJD_MINOBJECTS : maxobj = #LJD_MINOBJECTS : EndIf
         cy1 = 1 : cy2 = 1
         
         AddGadgetItem(#TreeObjects,pos,gszScreenBase+Str(appInfo\Screen+1),0,#LJD_Screens)
         *v = MakeNode(#LJD_Screens,gszScreenBase+Str(appInfo\Screen+1), 0, appInfo\Screen )
         SetGadgetItemData(#TreeObjects,pos, *v)
         SetGadgetItemState(#TreeObjects,pos,#PB_Tree_Expanded | #PB_Tree_Selected)
         pos + 1
        
         For j = 1 To APS\params(#GridY,orientation)
            cx1 = 1 : cx2 = 1
            For i = 1 To APS\params(#GridX,orientation)
               coords = Str(appInfo\Screen)+"/"+Str(i)+"/"+Str(j)
               
               mapid = AddMapElement(APM,coords,#PB_Map_NoElementCheck)
               With appInfo\scr(appInfo\Screen)\mapCont()
                  \objName    = "Cont"+coords
                  \key        = coords
                  \maxObj     = maxobj
                  ReDim \Obj(maxobj)

                  \Box(0)\x   = cx1 : \Box(1)\x   = cx2
                  \Box(0)\y   = cy1 : \Box(1)\y   = cy2
                  \Box(0)\w   = x  : \Box(1)\w   = y
                  \Box(0)\h   = y  : \Box(1)\h   = x
                  \Box(0)\ow   = x  : \Box(1)\ow   = y
                  \Box(0)\oh   = y  : \Box(1)\oh   = x
         
                  tw = \Box(orientation)\w
                  th = \Box(orientation)\h
         
                  \id         = ContainerGadget(#PB_Any,cx1, cy1,tw, th)
                  \color      = rndCol()
                  
                  ;Normal Image
                  \image = CreateImage(#PB_Any, tw,th)
                  StartDrawing( ImageOutput( \image ) )
                  Box( 0, 0, tw, th, \color )
                  
                  DrawingMode(#PB_2DDrawing_Default)
                  DrawingFont(FontID(gSmallFont))
                  DrawText(4, 2,"("+coords+")", #Black,#Yellow)
                  StopDrawing()
                  
                  ;Pressed Image
                  \pressed = CreateImage(#PB_Any, tw,th)
                  StartDrawing( ImageOutput( \pressed ) )
                  DrawingMode(#PB_2DDrawing_Outlined)
                  DrawAlphaImage(ImageID(\image), 0, 0,160)
                  MakeGrid()
                  StopDrawing()
                  
                  ;\imgID      = ImageGadget( #PB_Any, 0, 0, tw, th, ImageID( \image ) )
                  \imgID       = ButtonImageGadget(#PB_Any, 0, 0, tw, th,ImageID( \image ),#PB_Button_Toggle)
                  SetGadgetAttribute(\imgID,#PB_Button_PressedImage,ImageID(\pressed))
                  
                  BindGadgetEvent(\imgID, @SmallButtonClick())
                  temp = Str(\imgID)
                  
                  If Not FindMapElement(mapSmallButtons(),temp)
                     AddMapElement(mapSmallButtons(),temp,#PB_Map_NoElementCheck)
                  EndIf
                  
                  mapSmallButtons() = mapid
               EndWith

               CloseGadgetList()
               
               AddGadgetItem(#TreeObjects,pos,"Cont"+coords,0,#LJD_Container)
               *p = MakeNode(#LJD_Container,coords,*v,appInfo\Screen)
               SetGadgetItemData(#TreeObjects,pos, *p)
               pos + 1
               
               cx1 + tw : cx2 + th
            Next
            
            cy1 + th : cy2 + tw
         Next
      EndIf
   EndProcedure
   Procedure            MakeNode(NodeType, code.s, *prev.stTree, screen, pos = -1 )
      Protected         *p.stTree = AllocateStructure( stTree )
      
      *p\NodeType    = NodeType
      *p\prev        = *prev
      *p\screen      = screen
      *p\code        = code
      *p\pos         = pos
      AddNode()
      
      ProcedureReturn *p
   EndProcedure
   Procedure            Landscape()
      If appInfo\Orientation = 0
         appInfo\Orientation = 1
         If appInfo\winid
            RedrawApp()
         EndIf
      EndIf
   EndProcedure
   Procedure            Portrait()
      If appInfo\Orientation = 1
         appInfo\Orientation = 0
         If appInfo\winid
            RedrawApp()
         EndIf
      EndIf
   EndProcedure
   Procedure            MainWindow()
      Protected         i, j
   
      MakeImage(#cbWhite,#White)
      MakeImage(#cbGreen,#Green)
      MakeImage(#cbBlack,#Black)
      MakeImage(#cbGrey,RGB(148,148,148))
      MakeImage(#cbBlue,#Blue)
      MakeImage(#cbOrange,$179FFF)
      MakeImage(#cbLightGrey,RGB(192,192,192))
   
      If OpenWindow( #MainWindow, #PB_Ignore, #PB_Ignore, #LJD_WindowWidth, #LJD_WindowHeight, GszTitle )
         ButtonGadget( #BtnScreen, #LJD_2NDROW,  5, #LJD_TextLabelW, 40, "ADD SCREEN" )
         ButtonGadget( #BtnDelete, #LJD_2NDROW+#LJD_TextLabelW,  5, #LJD_TextLabelW, 40, "DELETE" )
         ButtonGadget( #BtnLoad, #LJD_3RDDROW, 5, #LJD_TextLabelW, 40, "SAVE" )
         ButtonGadget( #BtnSave, #LJD_3RDDROW, 45, #LJD_TextLabelW, 40, "LOAD" )
         
         ButtonGadget(#BtnJoin,#LJD_2NDROW,#LJD_ButtonsHeight-35,#LJD_TextLabelW,35,"Join")
         ButtonGadget(#BtnClear,#LJD_2NDROW+#LJD_TextLabelW,#LJD_ButtonsHeight-35,#LJD_TextLabelW,35,"Reset")
         ButtonGadget(#BtnLock,#LJD_2NDROW+(#LJD_TextLabelW*2),#LJD_ButtonsHeight-35,#LJD_TextLabelW,35,"Lock")
         
         PanelGadget(#GridObjects,10, #LJD_ButtonsHeight, #LJD_PanelWidth, WindowHeight( #MainWindow ) - (#LJD_ButtonsHeight+5) )
         AddGadgetItem (#GridObjects, -1, "Objects")
            i = GetGadgetAttribute(#GridObjects,#PB_Panel_ItemHeight)
            j = GetGadgetAttribute(#GridObjects,#PB_Panel_ItemWidth )
            
            TreeGadget(#TreeObjects,5,0,#LJD_TREEWIDTH,i,#PB_Tree_AlwaysShowSelection )
            ButtonGadget( #BtnAdd,  #LJD_TREEWIDTH+10,  5, 110, 35, "Add Gadget" )
            ComboBoxGadget( #lvType,#LJD_TREEWIDTH+10,40, #LJD_DetailsWidth, #LJD_TextLabelH)
            ;ButtonGadget( #BtnScreen,#LJD_TREEWIDTH+175,  5, 110, 35, "Add Screen" )
            
            TextGadget(#txtDetails, #LJD_TREEWIDTH+10,75,(j-#LJD_TREEWIDTH)-5,#LJD_TextLabelH,"Details", #PB_Text_Center)
            ;SetGadgetColor(#txtDetails,#PB_Gadget_BackColor,$1D1DD8)
            SetGadgetColor(#txtDetails,#PB_Gadget_BackColor,$FF6B2E)
            SetGadgetColor(#txtDetails,#PB_Gadget_FrontColor,#White)
            
            TxtGadget(#txtType,25,"ObjectType")
            TxtGadget(#txtObjName,47,"ObjectName")
            TxtGadget(#txtColour,69,"Colour")
            TxtGadget(#txtDefaultText,91,"DefaultValue")
            TxtGadget(#txtSize,113,"Size")
            TxtGadget(#txtAlign,135,"Alignment")
            
            StringGadget(#InpType,#LJD_TREEWIDTH+100,100,130,#LJD_TextLabelH,"",#PB_String_ReadOnly)
            StringGadget(#InpObjName,#LJD_TREEWIDTH+100,122,130,#LJD_TextLabelH,"")
            ComboBoxGadget(#InpColour,#LJD_TREEWIDTH+100,144,130,#LJD_TextLabelH,#PB_ComboBox_Image )
            StringGadget(#InpDefaultText,#LJD_TREEWIDTH+100,166,130,#LJD_TextLabelH,"")
            ;StringGadget(#InpDefaultText,#LJD_TREEWIDTH+100,166,130,#LJD_TextLabelH,"(default)")
            ComboBoxGadget(#InpSize,#LJD_TREEWIDTH+100,188,130,#LJD_TextLabelH)
            ComboBoxGadget(#InpAlign,#LJD_TREEWIDTH+100,208,130,#LJD_TextLabelH)
            ButtonGadget(#BtnUpdate,#LJD_TREEWIDTH+10,320, 90,22,"Update")
            ButtonGadget(#BtnRemove,#LJD_TREEWIDTH+110,320, 90,22,"Remove")

            CloseGadgetList()
            
         StringGadget( #txtAppName, 10,5,#LJD_TextLabelW,#LJD_TextLabelH,"AppName", #PB_String_ReadOnly )
         StringGadget( #inpAppName, #LJD_TextLabelW+10,5,#LJD_TextLabelW,#LJD_TextLabelH,"Default" )
         StringGadget( #TxtSeed, 10,29,#LJD_TextLabelW,#LJD_TextLabelH,"Seed", #PB_String_ReadOnly )
         StringGadget( #InpSeed, #LJD_TextLabelW+10,29,#LJD_TextLabelW,#LJD_TextLabelH,Str(0) )
         StringGadget( #txtX, 10,53,#LJD_TextLabelW,#LJD_TextLabelH,"GridXSize", #PB_String_ReadOnly )
         StringGadget( #txtY, 10,77,#LJD_TextLabelW,#LJD_TextLabelH,"GridYSize", #PB_String_ReadOnly )
         ComboBoxGadget(#InpX,#LJD_TextLabelW+10,53,#LJD_TextLabelW,#LJD_TextLabelH)
         ComboBoxGadget(#InpY,#LJD_TextLabelW+10,77,#LJD_TextLabelW,#LJD_TextLabelH)
         
         ;StringGadget(#txtChooseScreen,10,127,#LJD_TextLabelW,#LJD_TextLabelH,"Active Screen", #PB_String_ReadOnly)
         ;ComboBoxGadget(#cbScreen,#LJD_TextLabelW+10,127,#LJD_TextLabelW+20,#LJD_TextLabelH)
         
         StringGadget( #txtWidth, #LJD_2NDROW,53,#LJD_TextLabelW,#LJD_TextLabelH,"Max Width", #PB_String_ReadOnly )
         StringGadget( #txtHeight, #LJD_2NDROW,77,#LJD_TextLabelW,#LJD_TextLabelH,"Max Height", #PB_String_ReadOnly )
         StringGadget( #InpWidth, #LJD_2NDROW+#LJD_TextLabelW,53,#LJD_TextLabelW,#LJD_TextLabelH,gszDefaultMaxX )
         StringGadget( #InpHeight, #LJD_2NDROW+#LJD_TextLabelW,77,#LJD_TextLabelW,#LJD_TextLabelH, gszDefaultMaxY )
    
         OptionGadget( #OptPortrait,#LJD_2NDROW,107,#LJD_TextLabelW,#LJD_TextLabelH,"Portrait")
         OptionGadget( #OptLandscape,#LJD_2NDROW+#LJD_TextLabelW,107,#LJD_TextLabelW,#LJD_TextLabelH,"Landscape")
    
         AddGadgetItem(#lvType,-1,"Text")
         AddGadgetItem(#lvType,-1,"Input")
         AddGadgetItem(#lvType,-1,"Image")
         AddGadgetItem(#lvType,-1,"ListView")
         AddGadgetItem(#lvType,-1,"Calendar")
         
         arObjects(0)   = "Text"
         arObjects(1)   = "Input"
         arObjects(2)   = "Image"
         arObjects(3)   = "ListView"
         arObjects(4)   = "Calendar"
         arObjects(5)   = ""
         arObjects(6)   = ""
         arObjects(7)   = ""
         arObjects(8)   = ""
         arObjects(9)   = ""
         arObjects(10)  = ""
         
         AddGadgetItem(#InpSize,-1,"(Default)")
         AddGadgetItem(#InpSize,-1,"Small")
         AddGadgetItem(#InpSize,-1,"Medium")
         AddGadgetItem(#InpSize,-1,"Large")
         AddGadgetItem(#InpSize,-1,"Extra Large")
         AddGadgetItem(#InpSize,-1,"Huge")
         
         AddGadgetItem(#InpAlign,-1,"(Default)")
         AddGadgetItem(#InpAlign,-1,"Left")
         AddGadgetItem(#InpAlign,-1,"Right")
         AddGadgetItem(#InpAlign,-1,"Centre")
         
         AddGadgetItem(#InpColour,-1,"(Default)",ImageID(#cbLightGrey))
         AddGadgetItem(#InpColour,-1,"White",ImageID(#cbWhite))
         AddGadgetItem(#InpColour,-1,"Black",ImageID(#cbBlack))
         AddGadgetItem(#InpColour,-1,"Grey",ImageID(#cbGrey))
         AddGadgetItem(#InpColour,-1,"Blue",ImageID(#cbBlue))
         AddGadgetItem(#InpColour,-1,"Green",ImageID(#cbGreen))
         AddGadgetItem(#InpColour,-1,"Orange",ImageID(#cbOrange))

         SetGadgetState(#InpColour, 0)
         SetGadgetState(#InpSize, 0)
         SetGadgetState(#InpAlign, 0)
         SetGadgetState(#lvType, 0)
         SetGadgetState(#OptPortrait, 1)
         
         AllowAdd(1)
         TreeInfoAllow(3)
         BlockNewApp(0)
         DisableGadget(#BtnRemove,1)
         DisableGadget(#BtnUpdate,1)
         
         For i = 1 To #LJD_MAXGRIDLINES
            AddGadgetItem(#InpX,-1,Str(i))
            AddGadgetItem(#InpY,-1,Str(i))
         Next
         
         SetGadgetState(#InpX, 4) : SetGadgetState(#InpY, 4)
         ProcedureReturn 1
      EndIf

      ProcedureReturn 0
   EndProcedure

   Procedure ResumeGadgetEvents()
      If EventData() <> #EventDataID
         PostEvent(#PB_Event_Gadget, EventWindow(), EventGadget(), EventType(), #EventDataID)
      EndIf
   EndProcedure
   ; ======================================================================================================
   ;- Entry Point
   ; -=====================================================================================================  
   
   Define               err, ExitApplication
   Define               e, w, Event, orientation

   If MainWindow()
      ;BindEvent(#PB_Event_Gadget, @ResumeGadgetEvents())
      BindGadgetEvent(#BtnClear, @ClearPressed())
      BindGadgetEvent(#BtnScreen,@CreateScreen())
      BindGadgetEvent(#BtnDelete,@DeletePressed())
      BindGadgetEvent(#BtnClear,@ClearPressed())
      BindGadgetEvent(#OptLandscape,@Landscape())
      BindGadgetEvent(#OptPortrait,@Portrait())
      BindGadgetEvent(#BtnJoin,@JoinPressed())
      BindGadgetEvent(#BtnLock,@LockPressed())
      BindGadgetEvent(#TreeObjects,@TreeClick())
      BindGadgetEvent(#BtnUpdate,@UpdatePressed())
      BindGadgetEvent(#BtnAdd,@AddPressed())
      BindGadgetEvent(#BtnRemove,@RemovePressed())
      
      gSmallFont = LoadFont(#PB_Any,"Arial",8)
   
      CompilerIf Defined(SB_Compiler_SpiderBasic, #PB_Constant)
         ; If there is something specific to SB
      CompilerElse
         Repeat
            Event = WaitWindowEvent()
            w = EventWindow()
            
            Select Event
               Case #PB_Event_CloseWindow 
                  If w = #MainWindow
                     ExitApplication = #True
                  Else
                     CloseWindow(appInfo\winid)
                     appInfo\winid = 0
                     AllowAdd(1)
                  EndIf
               
            EndSelect
           
         Until ExitApplication
      CompilerEndIf
   EndIf
   
EndModule

; IDE Options = PureBasic 5.73 LTS (Windows - x64)
; CursorPosition = 783
; FirstLine = 727
; Folding = --------
; Markers = 564,1128
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; CompileSourceDirectory
; Compiler = PureBasic 5.73 LTS (Windows - x64)
; EnablePurifier
; EnableCompileCount = 735
; EnableBuildCount = 0
; EnableExeConstant
; iOSAppOrientation = 0
; AndroidAppOrientation = 0