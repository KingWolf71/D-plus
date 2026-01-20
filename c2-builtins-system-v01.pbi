; -- CX Language Compiler
; System/Utility Built-in Functions
; Version: 01
; V1.039.45
;
; Functions:
;   delay(ms)      - pause execution for milliseconds
;   elapsed()      - milliseconds since program start
;   date()         - current date as YYYYMMDD integer
;   time()         - seconds since midnight
;   year()/month()/day()/hour()/minute()/second() - date/time components
;   randomseed(n)  - seed the random number generator
;   getenv(name)   - get environment variable
;
; Based on PureBasic/SpiderBasic library functions
;

; Global to track program start time
Global gProgramStartTime.q = 0

; Initialize start time (call this from vmInitVM)
Procedure InitSystemBuiltins()
   gProgramStartTime = ElapsedMilliseconds()
EndProcedure

;- Time Functions

; delay(ms) - Pause execution for specified milliseconds
Procedure C2BUILTIN_DELAY()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected ms.i

   If paramCount >= 1
      ms = gEvalStack(sp - 1)\i
      If ms > 0
         Delay(ms)
      EndIf
      vm_PopParams(paramCount)
   EndIf

   pc + 1
EndProcedure

; elapsed() - Returns milliseconds since program start
Procedure C2BUILTIN_ELAPSED()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.q

   result = ElapsedMilliseconds() - gProgramStartTime

   If paramCount > 0
      vm_PopParams(paramCount)
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; date() - Returns current date as YYYYMMDD integer
Procedure C2BUILTIN_DATE()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected d.i = Date()

   ; Format: YYYYMMDD
   result = Year(d) * 10000 + Month(d) * 100 + Day(d)

   If paramCount > 0
      vm_PopParams(paramCount)
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; time() - Returns seconds since midnight
Procedure C2BUILTIN_TIME()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected d.i = Date()

   ; Seconds since midnight
   result = Hour(d) * 3600 + Minute(d) * 60 + Second(d)

   If paramCount > 0
      vm_PopParams(paramCount)
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; year() or year(date) - Get year component
Procedure C2BUILTIN_YEAR()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected dateVal.i

   If paramCount >= 1
      ; year(YYYYMMDD) - extract year from date integer
      dateVal = gEvalStack(sp - 1)\i
      result = dateVal / 10000
      vm_PopParams(paramCount)
   Else
      ; year() - current year
      result = Year(Date())
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; month() or month(date) - Get month component (1-12)
Procedure C2BUILTIN_MONTH()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected dateVal.i

   If paramCount >= 1
      ; month(YYYYMMDD) - extract month from date integer
      dateVal = gEvalStack(sp - 1)\i
      result = (dateVal / 100) % 100
      vm_PopParams(paramCount)
   Else
      ; month() - current month
      result = Month(Date())
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; day() or day(date) - Get day component (1-31)
Procedure C2BUILTIN_DAY()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected dateVal.i

   If paramCount >= 1
      ; day(YYYYMMDD) - extract day from date integer
      dateVal = gEvalStack(sp - 1)\i
      result = dateVal % 100
      vm_PopParams(paramCount)
   Else
      ; day() - current day
      result = Day(Date())
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; hour() or hour(time) - Get hour component (0-23)
Procedure C2BUILTIN_HOUR()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected timeVal.i

   If paramCount >= 1
      ; hour(seconds since midnight) - extract hour
      timeVal = gEvalStack(sp - 1)\i
      result = timeVal / 3600
      vm_PopParams(paramCount)
   Else
      ; hour() - current hour
      result = Hour(Date())
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; minute() or minute(time) - Get minute component (0-59)
Procedure C2BUILTIN_MINUTE()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected timeVal.i

   If paramCount >= 1
      ; minute(seconds since midnight) - extract minute
      timeVal = gEvalStack(sp - 1)\i
      result = (timeVal / 60) % 60
      vm_PopParams(paramCount)
   Else
      ; minute() - current minute
      result = Minute(Date())
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

; second() or second(time) - Get second component (0-59)
Procedure C2BUILTIN_SECOND()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i
   Protected timeVal.i

   If paramCount >= 1
      ; second(seconds since midnight) - extract second
      timeVal = gEvalStack(sp - 1)\i
      result = timeVal % 60
      vm_PopParams(paramCount)
   Else
      ; second() - current second
      result = Second(Date())
   EndIf

   vm_PushInt(result)
   pc + 1
EndProcedure

;- System Functions

; randomseed(n) - Seed the random number generator
Procedure C2BUILTIN_RANDOMSEED()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected seed.i

   If paramCount >= 1
      seed = gEvalStack(sp - 1)\i
      RandomSeed(seed)
      vm_PopParams(paramCount)
   Else
      ; No parameter - seed with current time
      RandomSeed(ElapsedMilliseconds())
   EndIf

   pc + 1
EndProcedure

; getenv(name) - Get environment variable value
Procedure C2BUILTIN_GETENV()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.s = ""
   Protected varName.s

   If paramCount >= 1
      varName = gEvalStack(sp - 1)\ss
      result = GetEnvironmentVariable(varName)
      vm_PopParams(paramCount)
   EndIf

   vm_PushString(result)
   pc + 1
EndProcedure
