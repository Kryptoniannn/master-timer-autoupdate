#Requires AutoHotkey v2.0
#SingleInstance Force
global ProtectionEnabled := true

; --- Auto-update configuration (GitHub raw, public repo) ---
Global AppVersion := "1.0.2"
Global UpdateRepo := "Kryptoniannn/master-timer-autoupdate"
Global UpdateExeName := "Reload reminder Ultra.exe"
Global UpdateCheckURL := "https://raw.githubusercontent.com/" UpdateRepo "/main/version.txt"
Global UpdateExeURL := "https://raw.githubusercontent.com/" UpdateRepo "/main/" UpdateExeName
Global UpdateTempDir := A_Temp "\master_timer_update"

; --- Settings (saved to INI, auto-loaded on next run) ---
Global SettingsFile := A_AppData "\alert_timer\settings.ini"
Global CfgInterval := "4:15"
Global CfgMode := "Fixed"
Global CfgMinInterval := "3:00"
Global CfgMaxInterval := "6:00"
Global CfgKillTime := "3:15 PM"
Global CfgInfinite := false
Global CfgShowTimer := true
Global CfgColorMode := "RGB"
Global CfgFixedColor := "FF0000"
Global CfgColorEffect := "Round"
Global CfgResetTrigger := "Mouse"
Global CfgLogging := true
Global CfgWordBreaker := true
Global TimersStarted := false

; Critical globals needed before GUI creation / early hotkey use
Global AlertActive := false
Global AlertGui := unset
Global Hue := 0

; --- Input Director watcher settings ---
Global IDExePath := "C:\Program Files\Input Director\InputDirector.exe"
Global IDWatchEnabled := true
Global IDRecovering := false
Global IDRecoverDeadline := 0
Global IDNudgeUntil := 0
Global IDLastState := ""
Global IDOldPid := 0
Global IDLastStart := 0

LoadSettings()

; --- Alert dismiss via keyboard (F5/Ctrl+R) ---
DismissAlertKey() {
    global AlertActive
    if (AlertActive)
        DismissAlert()
}

; Register hotkeys based on saved setting
if (CfgResetTrigger = "F5" || CfgResetTrigger = "Combined")
    Hotkey "~F5", (*) => DismissAlertKey(), "On"
if (CfgResetTrigger = "CtrlR" || CfgResetTrigger = "Combined")
    Hotkey "~^r", (*) => DismissAlertKey(), "On"

; --- Custom Setup GUI ---
ShowSetupGui()

; Global variables
Global TargetInterval := 0
Global CurrentIntervalTime := 0
Global TimerGui := unset
Global TimerText := unset
Global KillTimeStr := ""
Global InfiniteMode := false
Global MinInterval := 180
Global MaxInterval := 360
Global IsRandomMode := false
Global TimerMinimized := false
Global TimerSavedX := 0
Global TimerSavedY := 0
Global DraggingTimer := false

; --- Create on-screen timer GUI ---
CreateTimerGui() {
    global TimerGui, TimerText, BtnMin, HndDrag, TargetInterval, CurrentIntervalTime
    TimerGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    TimerGui.BackColor := "Black"
    TimerGui.MarginX := 0
    TimerGui.MarginY := 0
    DispMins := Floor(CurrentIntervalTime / 60)
    DispSecs := Mod(CurrentIntervalTime, 60)
    TimerGui.SetFont("s12 w700", "Segoe UI")
    BtnMin := TimerGui.Add("Text", "x0 y0 w18 h20 cCCCCCC Center", "-")
    TimerGui.SetFont("s14 w700", "Segoe UI")
    TimerText := TimerGui.Add("Text", "x+4 yp cWhite Center w80 h30", Format("{:02}:{:02}", DispMins, DispSecs))
    HndDrag := TimerGui.Add("Progress", "x+4 yp w18 h30 -Border BackgroundFF9800 cFF9800 Smooth", 100)
    BtnMin.OnEvent("Click", MinimizeTimer)
    MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
    TimerGui.Show("x" (Left + 20) " y" (Bottom - 50) " NoActivate")
}

; --- Tray menu: open settings while running ---
OpenSettings(*) {
    ShowSetupGui()
}
A_TrayMenu.Delete()
A_TrayMenu.Add("Show Timer", ShowTimerFromTray)
A_TrayMenu.Add("Settings", OpenSettings)
A_TrayMenu.Add("Input Director watcher (2s)", ToggleIDWatcher)
A_TrayMenu.Check("Input Director watcher (2s)")
A_TrayMenu.Add()
A_TrayMenu.AddStandard()

; --- Mouse drag support for the on-screen timer ---
OnMessage(0x201, DragTimer)
ToggleInfinite(*) {
    global InfiniteMode
    InfiniteMode := InfiniteCheck.Value
    EditKillClock.Enabled := !InfiniteMode
}

; --- Random Interval Generator ---
GetNextInterval() {
    global IsRandomMode, MinInterval, MaxInterval, TargetInterval
    if (IsRandomMode)
        return Random(MinInterval, MaxInterval)
    return TargetInterval
}

; --- Parse "M:S" (or plain seconds) to seconds ---
ParseTimeToSeconds(str) {
    parts := StrSplit(Trim(str), ":")
    if (parts.Length == 2)
        return (Number(parts[1]) * 60) + Number(parts[2])
    return Number(str)
}

ProcessSetup(*) {
    global TargetInterval, CurrentIntervalTime, TimerGui, TimerText, KillTimeStr, InfiniteMode
    global MinInterval, MaxInterval, IsRandomMode, BtnMin, HndDrag, IDWatchEnabled
    global CfgInterval, CfgMode, CfgMinInterval, CfgMaxInterval, CfgKillTime, CfgInfinite
    global CfgShowTimer, CfgColorMode, CfgFixedColor, CfgColorEffect, CfgResetTrigger, CfgLogging, CfgWordBreaker, TimersStarted
    global EditInterval, EditMin, EditMax, EditKillClock, ShowTimerCheck, InfiniteCheck, IDWatchCheck
    global RadioFixed, RadioRandom, RadioFixedColor, RadioBlink, RadioResetMouse, RadioResetF5, RadioResetCtrlR, RadioResetCombined, LogCheck, WordBreakerCheck, ProtectionEnabled
    
    IntervalInput := EditInterval.Value
    KillInput := EditKillClock.Value
    IsVisible := ShowTimerCheck.Value
    InfiniteMode := InfiniteCheck.Value

    ; --- Alert color / effect / reset trigger / logging ---
    CfgColorMode := RadioFixedColor.Value ? "Fixed" : "RGB"
    CfgFixedColor := SelectedFixedColor
    CfgColorEffect := RadioBlink.Value ? "Blink" : "Round"
    if (RadioResetMouse.Value)
        CfgResetTrigger := "Mouse"
    else if (RadioResetF5.Value)
        CfgResetTrigger := "F5"
    else if (RadioResetCtrlR.Value)
        CfgResetTrigger := "CtrlR"
    else
        CfgResetTrigger := "Combined"
    CfgLogging := LogCheck.Value
    CfgWordBreaker := WordBreakerCheck.Value
    ProtectionEnabled := CfgWordBreaker

    if (IntervalInput == "" || !InfiniteMode && KillInput == "") {
        MsgBox "Please fill in both fields correctly!"
        return
    }

    ; 1. Setup Interval (Fixed or Random)
    IsRandomMode := RadioRandom.Value

    if (IsRandomMode) {
        MinInterval := ParseTimeToSeconds(EditMin.Value)
        MaxInterval := ParseTimeToSeconds(EditMax.Value)

        if (MinInterval < 10 || MaxInterval < 10 || MinInterval > MaxInterval) {
            MsgBox "Please enter valid random Min/Max values."
            return
        }

        TargetInterval := Random(MinInterval, MaxInterval)
    } else {
        TargetInterval := ParseTimeToSeconds(IntervalInput)
    }
    CurrentIntervalTime := TargetInterval

    ; 2. Setup System Kill Time (Specific Clock Time like 3:15 PM)
    if (InfiniteMode) {
        KillTimeStr := ""
    } else if RegExMatch(KillInput, "i)^(\d{1,2})[:\s]?(\d{0,2})\s*(AM|PM)?$", &match) {
        Hour := Number(match[1])
        Mins := match[2] == "" ? 0 : Number(match[2])
        AMPM := StrUpper(match[3])

        ; 12-hour format ke 24-hour e convert
        if (AMPM == "PM" && Hour < 12)
            Hour += 12
        else if (AMPM == "AM" && Hour == 12)
            Hour := 0

        Now := A_Now
        KillTimeStr := FormatTime(Now, "yyyyMMdd") . Format("{:02}", Hour) . Format("{:02}", Mins) . "00"
        
        ; If the given time has passed, use tomorrow's time
        if (DateDiff(KillTimeStr, Now, "Seconds") < 0)
            KillTimeStr := DateAdd(KillTimeStr, 1, "Days")
    } else {
        MsgBox "Please enter a valid off time! (Example: 3:15 PM)"
        return
    }

    IDWatchEnabled := IDWatchCheck.Value

    ; --- Save settings for next run ---
    CfgInterval := IntervalInput
    CfgMode := IsRandomMode ? "Random" : "Fixed"
    CfgMinInterval := EditMin.Value
    CfgMaxInterval := EditMax.Value
    CfgKillTime := KillInput
    CfgInfinite := InfiniteMode
    CfgShowTimer := IsVisible
    SaveSettings()

    ; --- Re-register dismiss hotkeys per new setting ---
    try Hotkey "~F5", "Off"
    try Hotkey "~^r", "Off"
    if (CfgResetTrigger = "F5" || CfgResetTrigger = "Combined")
        Hotkey "~F5", (*) => DismissAlertKey(), "On"
    if (CfgResetTrigger = "CtrlR" || CfgResetTrigger = "Combined")
        Hotkey "~^r", (*) => DismissAlertKey(), "On"

    ; --- Live apply if already running ---
    if (TimersStarted) {
        ; ID watcher toggle
        if (IDWatchEnabled)
            SetTimer WatchInputDirector, 2000
        else
            SetTimer WatchInputDirector, 0
        ; Show/hide timer
        if (IsVisible) {
            if (!IsSet(TimerGui))
                CreateTimerGui()
        } else {
            if (IsSet(TimerGui)) {
                TimerGui.Destroy()
                TimerGui := unset
                TimerText := unset
            }
        }
        ; Update timer text
        if (IsSet(TimerText))
            TimerText.Value := Format("{:02}:{:02}", Floor(CurrentIntervalTime / 60), Mod(CurrentIntervalTime, 60))
        AppLog("settings applied live")
    }

    SetupGui.Destroy()

    ; --- Input Director auto-recovery watcher (every 2 seconds) ---
    if (IDWatchEnabled && !TimersStarted) {
        WatchInputDirector()
        SetTimer WatchInputDirector, 2000
    }

    if (IsVisible && !TimersStarted) {
        CreateTimerGui()
    }

    if (!TimersStarted) {
        SetTimer UpdateTimer, 1000
        SetTimer CheckHover, 100
        TimersStarted := true
    }

    AppLog("setup applied")
}

CheckHover() {
    global TimerGui, TimerText, AlertActive, CurrentIntervalTime, TargetInterval, TimerMinimized, DraggingTimer, HndDrag, BtnMin
    CoordMode("Mouse", "Screen")
    if (!IsSet(TimerGui) || !IsSet(TimerText) || AlertActive || TimerMinimized)
        return
    if (DraggingTimer) {
        if (!GetKeyState("LButton", "P"))
            DraggingTimer := false
        else
            return
    }
    static wasHovering := false
    static logFile := A_Temp "\alert_hover.log"
    try {
        MouseGetPos(&mx, &my, &hoverHwnd, &hoverCtl)
        ; GUI client-area origin in screen coords (robust even with thin borders)
        pt := Buffer(8)
        NumPut("int", 0, pt, 0)
        NumPut("int", 0, pt, 4)
        DllCall("ClientToScreen", "ptr", TimerGui.Hwnd, "ptr", pt)
        cox := NumGet(pt, 0, "int")
        coy := NumGet(pt, 4, "int")
        TimerText.GetPos(&cx, &cy, &cw, &ch)
        scx := cox + cx
        scy := coy + cy
        pad := 6
        coordHit := (mx >= scx - pad && mx <= scx + cw + pad && my >= scy - pad && my <= scy + ch + pad)
        ; Hovering the drag handle never resets the timer
        overHandle := false
        if (IsSet(HndDrag)) {
            if (hoverCtl && hoverCtl = HndDrag.Hwnd) {
                overHandle := true
            } else {
                HndDrag.GetPos(&dhx, &dhy, &dhw, &dhh)
                overHandle := (mx >= cox + dhx && mx <= cox + dhx + dhw && my >= coy + dhy && my <= coy + dhy + dhh)
            }
        }
        ; Hovering the "-" (minimize) zone never resets the timer either
        overMin := false
        if (IsSet(BtnMin)) {
            if (hoverCtl && hoverCtl = BtnMin.Hwnd) {
                overMin := true
            } else {
                BtnMin.GetPos(&bnx, &bny, &bnw, &bnh)
                overMin := (mx >= cox + bnx && mx <= cox + bnx + bnw && my >= coy + bny && my <= coy + bny + bnh)
            }
        }
        hwndHit := (hoverHwnd = TimerGui.Hwnd)
        hovering := !overHandle && !overMin && (coordHit || hwndHit)

        ; Debug: write to log file every call (throttled by only logging state changes + every 2s)
        static lastLog := 0
        if (A_TickCount - lastLog > 2000) {
            FileAppend "mx=" mx " my=" my " cox=" cox " coy=" coy " scx=" scx " scy=" scy " cw=" cw " ch=" ch " ctl=" hoverCtl " hnd=" (IsSet(HndDrag) ? HndDrag.Hwnd : "?") " overHandle=" overHandle " overMin=" overMin " hwndHit=" hwndHit " coordHit=" coordHit "`n", logFile
            lastLog := A_TickCount
        }

        if (hovering) {
            if (!wasHovering) {
                ; Write a marker
                FileAppend ">>> HOVER START at " A_Now "`n", logFile
            }
            wasHovering := true
            ; Glow effect while hovered
            try TimerText.SetFont("cFFFF00 s14 w700", "Segoe UI")
            ; Reset timer while hovering (always on, original behavior)
            if (CurrentIntervalTime != TargetInterval) {
                CurrentIntervalTime := TargetInterval
                Mins := Floor(CurrentIntervalTime / 60)
                Secs := Mod(CurrentIntervalTime, 60)
                TimerText.Value := Format("{:02}:{:02}", Mins, Secs)
            }
        } else {
            if (wasHovering) {
                try TimerText.SetFont("cWhite s14 w700", "Segoe UI")
                FileAppend "<<< HOVER END at " A_Now "`n", logFile
            }
            wasHovering := false
        }
    } catch as e {
        try FileAppend "CheckHover ERROR: " e.Message "`n", logFile
    }
}

UpdateTimer() {
    global CurrentIntervalTime, TargetInterval, AlertActive, TimerText, KillTimeStr, InfiniteMode
    
    ; System Kill Logic (Specific Clock Time Check) - skipped when InfiniteMode
    if (!InfiniteMode && KillTimeStr != "" && DateDiff(KillTimeStr, A_Now, "Seconds") <= 0) {
        ExitApp()
    }

    if (AlertActive)
        return

    CurrentIntervalTime -= 1

    if (CurrentIntervalTime <= 0) {
        if IsSet(TimerText)
            TimerText.Value := "00:00"
        ShowRainbowEdgeOnMonitor2()
    } else {
        if IsSet(TimerText) {
            Mins := Floor(CurrentIntervalTime / 60)
            Secs := Mod(CurrentIntervalTime, 60)
            TimerText.Value := Format("{:02}:{:02}", Mins, Secs)
        }
    }
}

ShowRainbowEdgeOnMonitor2() {
    global AlertActive, AlertGui, Hue, AlertBlinkState, CfgColorMode, CfgColorEffect, CfgFixedColor
    AlertActive := true
    Hue := 0
    AlertBlinkState := true
    if MonitorGetCount() >= 2
        MonitorGet(2, &M2Left, &M2Top, &M2Right, &M2Bottom)
    else
        MonitorGet(1, &M2Left, &M2Top, &M2Right, &M2Bottom)

    W := M2Right - M2Left, H := M2Bottom - M2Top, Thickness := 12
    AlertGui := Gui("+AlwaysOnTop -Caption +LastFound +ToolWindow +E0x20")
    OuterRect := "0-0 " W "-0 " W "-" H " 0-" H " 0-0"
    InnerRect := Thickness "-" Thickness " " (W-Thickness) "-" Thickness " " (W-Thickness) "-" (H-Thickness) " " Thickness "-" (H-Thickness) " " Thickness "-" Thickness
    WinSetRegion(OuterRect "  " InnerRect, AlertGui)
    ; Initial color
    if (CfgColorMode = "Fixed")
        AlertGui.BackColor := CfgFixedColor
    else
        AlertGui.BackColor := HueToRGB(0)
    AlertGui.Show("x" M2Left " y" M2Top " w" W " h" H " NA")
    if (CfgColorEffect = "Blink")
        SetTimer RainbowFlow, 500
    else if (CfgColorMode = "RGB")
        SetTimer RainbowFlow, 20
}

RainbowFlow() {
    global AlertGui, Hue, AlertBlinkState, CfgColorMode, CfgColorEffect, CfgFixedColor
    if !AlertActive
        return
    if (CfgColorEffect = "Blink") {
        AlertBlinkState := !AlertBlinkState
        if (AlertBlinkState) {
            if (CfgColorMode = "Fixed") {
                try AlertGui.BackColor := CfgFixedColor
            } else {
                try AlertGui.BackColor := HueToRGB(Hue)
            }
        } else {
            try AlertGui.BackColor := "000000"
        }
    } else {
        ; Round
        if (CfgColorMode = "RGB") {
            Hue := Mod(Hue + 2, 360)
            try AlertGui.BackColor := HueToRGB(Hue)
        }
        ; Fixed + Round: constant color, no update needed
    }
}

HueToRGB(h) {
    s := 1, v := 1, c := v * s, x := c * (1 - Abs(Mod(h / 60, 2) - 1)), m := v - c, r := 0, g := 0, b := 0
    if (h < 60) {
        r := c, g := x, b := 0
    } else if (h < 120) {
        r := x, g := c, b := 0
    } else if (h < 180) {
        r := 0, g := c, b := x
    } else if (h < 240) {
        r := 0, g := x, b := c
    } else if (h < 300) {
        r := x, g := 0, b := c
    } else {
        r := c, g := 0, b := x
    }
    return Format("{:02X}{:02X}{:02X}", Round((r + m) * 255), Round((g + m) * 255), Round((b + m) * 255))
}

; --- Dismiss alert + pick next (random) interval ---
DismissAlert() {
    global AlertActive, AlertGui, CurrentIntervalTime, TargetInterval, TimerText
    if (!AlertActive)
        return
    SetTimer(RainbowFlow, 0)
    if IsSet(AlertGui)
        AlertGui.Destroy()
    AlertActive := false
    ; --- Next Random Interval After Alert Dismiss ---
    CurrentIntervalTime := GetNextInterval()
    TargetInterval := CurrentIntervalTime
    if IsSet(TimerText) {
        TimerText.Value := Format("{:02}:{:02}", Floor(CurrentIntervalTime/60), Mod(CurrentIntervalTime,60))
    }
}

~LButton:: {
    global CfgResetTrigger
    if (AlertActive && (CfgResetTrigger = "Mouse" || CfgResetTrigger = "Combined"))
        DismissAlert()
}

; --- Minimize on-screen timer (hide; restore from tray) ---
MinimizeTimer(*) {
    global TimerGui, TimerMinimized, TimerSavedX, TimerSavedY
    if !IsSet(TimerGui)
        return
    TimerGui.GetPos(&TimerSavedX, &TimerSavedY)
    TimerGui.Hide()
    TimerMinimized := true
    A_IconTip := "Timer minimized - Right-click tray icon > Show Timer"
}

; --- Show timer again from tray menu ---
ShowTimerFromTray(*) {
    global TimerGui, TimerMinimized, TimerSavedX, TimerSavedY
    if (!IsSet(TimerGui) || !TimerMinimized)
        return
    pos := IsSet(TimerSavedX) ? "x" TimerSavedX " y" TimerSavedY : ""
    TimerGui.Show(pos " NoActivate")
    TimerMinimized := false
    A_IconTip := ""
}

; --- Drag the timer: only by holding the colored handle strip on the right ---
DragTimer(wParam, lParam, msg, hwnd) {
    global TimerGui, HndDrag, DraggingTimer
    if (IsSet(TimerGui) && IsSet(HndDrag) && hwnd = HndDrag.Hwnd) {
        DraggingTimer := true
        PostMessage(0xA1, 2, 0,, "ahk_id " TimerGui.Hwnd)
        return 0
    }
}

; ============================================================
;      INPUT DIRECTOR AUTO-RECOVERY WATCHER (every 2s)
;  Input Director crash/close hole process ta abar start kore
;  ebong taskbar e minimized obosthay rakhe.
; ============================================================
IDWatcherLog(msg) {
    static f := A_Temp "\input_director_watch.log"
    try FileAppend FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " | " msg "`n", f
}

; Main window ber kore (hidden window o dhore, class #32770 + title "Input Director")
IDMainWindow(pid) {
    if (!pid)
        return 0
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    found := 0
    try {
        for hwnd in WinGetList("ahk_pid " pid) {
            if (WinGetClass("ahk_id " hwnd) != "#32770")
                continue
            if RegExMatch(WinGetTitle("ahk_id " hwnd), "i)^\s*Input Director\s*$") {
                found := hwnd
                break
            }
        }
    }
    DetectHiddenWindows prev
    return found
}

; Input Director ShowWindow() mane na, kintu SC_MINIMIZE process kore
IDMinimizeToTaskbar(hwnd) {
    if (!hwnd || !DllCall("IsWindow", "ptr", hwnd))
        return
    try {
        if (!DllCall("IsWindowVisible", "ptr", hwnd))
            DllCall("ShowWindow", "ptr", hwnd, "int", 4)   ; SW_SHOWNOACTIVATE
        DllCall("PostMessageW", "ptr", hwnd, "uint", 0x112, "ptr", 0xF020, "ptr", 0)  ; WM_SYSCOMMAND / SC_MINIMIZE
    }
}

WatchInputDirector() {
    global IDWatchEnabled, IDExePath, IDRecovering, IDRecoverDeadline, IDNudgeUntil, IDLastState, IDOldPid, IDLastStart
    if (!IDWatchEnabled)
        return

    try {
        if (!IsSet(IDOldPid))
            IDOldPid := 0
        if (!IsSet(IDLastStart))
            IDLastStart := 0

        pid := ProcessExist("InputDirector.exe")
        hwnd := IDMainWindow(pid)

        if (!pid)
            state := "none"
        else if (!hwnd)
            state := "no-window"
        else if (!DllCall("IsWindowVisible", "ptr", hwnd))
            state := "hidden(tray)"
        else if (DllCall("IsIconic", "ptr", hwnd))
            state := "visible+minimized"
        else
            state := "visible+normal"

        if (state != IDLastState) {
            IDWatcherLog("state=" state " pid=" pid " hwnd=" hwnd)
            IDLastState := state
        }

        ; --- recovery cholche: purono process jay, notun ta ashe, then minimize ---
        if (IDRecovering) {
            if (!pid || (IDOldPid && pid = IDOldPid)) {
                ; old (hidden) process still running / new instance not started yet
                if (A_TickCount > IDRecoverDeadline) {
                    IDWatcherLog("recovery TIMEOUT: new instance did not start")

                    IDRecovering := false
                }
                return
            }
            if (!hwnd) {
                if (A_TickCount > IDRecoverDeadline) {
                    IDWatcherLog("recovery TIMEOUT: window did not appear")

                    IDRecovering := false
                }
                return
            }
            if (DllCall("IsIconic", "ptr", hwnd)) {
                IDWatcherLog("recovered: minimized (pid " pid ")")
                IDRecovering := false
            } else if (A_TickCount < IDNudgeUntil) {
                IDMinimizeToTaskbar(hwnd)
            } else {
                IDWatcherLog("recovered: window normal (minimize did not apply)")
                IDRecovering := false
            }
            return
        }

        ; --- When to start ---
        local needStart := false
        local reason := ""
        if (!pid) {
            needStart := true
            reason := "process closed"
        } else if (!hwnd) {
            needStart := true
            reason := "main window nei"
        } else if (!DllCall("IsWindowVisible", "ptr", hwnd)) {
            needStart := true
            reason := "hidden in tray"
        }

        if (needStart) {
            ; Wait 15s after a start to avoid loop restarts
            if (IDLastStart && A_TickCount - IDLastStart < 15000)
                return
            IDWatcherLog(reason " -> starting Input Director")
            IDOldPid := pid
            IDLastStart := A_TickCount
            IDRecovering := true
            IDRecoverDeadline := A_TickCount + 30000
            IDNudgeUntil := A_TickCount + 25000
            try
                Run('"' IDExePath '"')
            catch as e {
                IDWatcherLog("start FAILED: " e.Message)
                IDRecovering := false
            }
        }
    } catch as e {
        IDWatcherLog("ERROR: " e.Message " (line " e.Line ")")
    }
}

; Tray menu theke watcher ON/OFF
ToggleIDWatcher(*) {
    global IDWatchEnabled
    IDWatchEnabled := !IDWatchEnabled
    A_TrayMenu.ToggleCheck("Input Director watcher (2s)")
    if (IDWatchEnabled) {
        WatchInputDirector()
        SetTimer WatchInputDirector, 2000
        ToolTip "Input Director watcher ON"
    } else {
        SetTimer WatchInputDirector, 0
        ToolTip "Input Director watcher OFF"
    }
    SetTimer(() => ToolTip(), -1500)
}
; --- Admin permission check and request ---
; --- Settings load/save (INI) ---
LoadSettings() {
    global
    if (!FileExist(SettingsFile))
        return
    CfgInterval := IniRead(SettingsFile, "Settings", "Interval", CfgInterval)
    CfgMode := IniRead(SettingsFile, "Settings", "Mode", CfgMode)
    CfgMinInterval := IniRead(SettingsFile, "Settings", "MinInterval", CfgMinInterval)
    CfgMaxInterval := IniRead(SettingsFile, "Settings", "MaxInterval", CfgMaxInterval)
    CfgKillTime := IniRead(SettingsFile, "Settings", "KillTime", CfgKillTime)
    CfgInfinite := (IniRead(SettingsFile, "Settings", "Infinite", "0") = "1")
    CfgShowTimer := (IniRead(SettingsFile, "Settings", "ShowTimer", "1") = "1")
    CfgColorMode := IniRead(SettingsFile, "Settings", "ColorMode", CfgColorMode)
    CfgFixedColor := IniRead(SettingsFile, "Settings", "FixedColor", CfgFixedColor)
    SelectedFixedColor := CfgFixedColor
    CfgColorEffect := IniRead(SettingsFile, "Settings", "ColorEffect", CfgColorEffect)
    CfgResetTrigger := IniRead(SettingsFile, "Settings", "ResetTrigger", CfgResetTrigger)
    CfgLogging := (IniRead(SettingsFile, "Settings", "Logging", "1") = "1")
    CfgWordBreaker := (IniRead(SettingsFile, "Settings", "WordBreaker", "1") = "1")
    ProtectionEnabled := CfgWordBreaker
    IDWatchEnabled := (IniRead(SettingsFile, "Settings", "IDWatch", "1") = "1")
}

SaveSettings() {
    global
    DirCreate(A_AppData "\alert_timer")
    IniWrite CfgInterval, SettingsFile, "Settings", "Interval"
    IniWrite CfgMode, SettingsFile, "Settings", "Mode"
    IniWrite CfgMinInterval, SettingsFile, "Settings", "MinInterval"
    IniWrite CfgMaxInterval, SettingsFile, "Settings", "MaxInterval"
    IniWrite CfgKillTime, SettingsFile, "Settings", "KillTime"
    IniWrite (CfgInfinite ? "1" : "0"), SettingsFile, "Settings", "Infinite"
    IniWrite (CfgShowTimer ? "1" : "0"), SettingsFile, "Settings", "ShowTimer"
    IniWrite CfgColorMode, SettingsFile, "Settings", "ColorMode"
    IniWrite CfgFixedColor, SettingsFile, "Settings", "FixedColor"
    IniWrite CfgColorEffect, SettingsFile, "Settings", "ColorEffect"
    IniWrite CfgResetTrigger, SettingsFile, "Settings", "ResetTrigger"
    IniWrite (CfgLogging ? "1" : "0"), SettingsFile, "Settings", "Logging"
    IniWrite (CfgWordBreaker ? "1" : "0"), SettingsFile, "Settings", "WordBreaker"
    IniWrite (IDWatchEnabled ? "1" : "0"), SettingsFile, "Settings", "IDWatch"
}

; --- Logging helper ---
AppLog(msg) {
    global CfgLogging
    if (!CfgLogging)
        return
    static f := A_AppData "\alert_timer\app.log"
    try FileAppend FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " | " msg "`n", f
}

; --- Settings panel (reusable while running) ---
ShowSetupGui() {
    global
    SelectedFixedColor := CfgFixedColor
    ; If already open, just focus
    try {
        if (IsSet(SetupGui) && SetupGui.Hwnd) {
            SetupGui.Show()
            return
        }
    }
    SetupGui := Gui("-MinimizeBox -MaximizeBox", "Reload reminder Ultra")
    SetupGui.SetFont("s9", "Segoe UI")

    ; ---- Interval ----
    SetupGui.Add("Text", "xm", "Alert Interval (M:S)   e.g. 4:15")
    EditInterval := SetupGui.Add("Edit", "xm y+2 w160", CfgInterval)
    RadioFixed := SetupGui.Add("Radio", "xm y+6 Group" (CfgMode = "Fixed" ? " Checked" : ""), "Fixed interval")
    RadioRandom := SetupGui.Add("Radio", "x+110 yp" (CfgMode = "Random" ? " Checked" : ""), "Random interval")
    SetupGui.Add("Text", "xm y+6", "Random Min:")
    EditMin := SetupGui.Add("Edit", "x+4 yp w70", CfgMinInterval)
    SetupGui.Add("Text", "x+8 yp", "Max:")
    EditMax := SetupGui.Add("Edit", "x+4 yp w70", CfgMaxInterval)
    EditMin.Enabled := (CfgMode = "Random")
    EditMax.Enabled := (CfgMode = "Random")
    EditInterval.Enabled := (CfgMode = "Fixed")
    ToggleMode(*) {
        isRandom := RadioRandom.Value
        EditInterval.Enabled := !isRandom
        EditMin.Enabled := isRandom
        EditMax.Enabled := isRandom
    }
    RadioFixed.OnEvent("Click", ToggleMode)
    RadioRandom.OnEvent("Click", ToggleMode)

    ; ---- System off / runtime ----
    SetupGui.Add("Text", "xm y+10", "System off time   e.g. 3:15 PM")
    EditKillClock := SetupGui.Add("Edit", "xm y+2 w120", CfgKillTime)
    ShowTimerCheck := SetupGui.Add("Checkbox", "xm y+6" (CfgShowTimer ? " Checked" : ""), "Show timer on screen")
    InfiniteCheck := SetupGui.Add("Checkbox", "xm y+4" (CfgInfinite ? " Checked" : ""), "Run indefinitely (Infinite)")
    InfiniteCheck.OnEvent("Click", ToggleInfinite)
    EditKillClock.Enabled := !CfgInfinite
    IDWatchCheck := SetupGui.Add("Checkbox", "xm y+4" (IDWatchEnabled ? " Checked" : ""), "Auto-restart Input Director (2s)")

    ; ---- Alert color ----
    SetupGui.Add("Text", "xm y+10", "Alert Color")
    RadioRGB := SetupGui.Add("Radio", "xm y+4 Group" (CfgColorMode = "RGB" ? " Checked" : ""), "RGB (Rainbow)")
    RadioFixedColor := SetupGui.Add("Radio", "x+110 yp" (CfgColorMode = "Fixed" ? " Checked" : ""), "Fixed color")
    ColorPreview := SetupGui.Add("Text", "x+8 yp w22 h20 0x100", "")
    ColorPreview.BackColor := CfgFixedColor
    BtnPickColor := SetupGui.Add("Button", "x+6 yp w80 h20", "Pick color")
    BtnPickColor.Enabled := (CfgColorMode = "Fixed")
    ColorPreview.Enabled := (CfgColorMode = "Fixed")
    ToggleColorMode(*) {
        BtnPickColor.Enabled := RadioFixedColor.Value
        ColorPreview.Enabled := RadioFixedColor.Value
    }
    RadioRGB.OnEvent("Click", ToggleColorMode)
    RadioFixedColor.OnEvent("Click", ToggleColorMode)
    BtnPickColor.OnEvent("Click", PickColorDirect)
    SetupGui.Add("Text", "xm y+4", "Quick colors:")
    swatchColors := ["FF0000", "00FF00", "0000FF", "FFFF00", "FF8800", "800080", "FF00FF", "00FFFF", "FFFFFF", "000000", "808080", "FFC0CB", "008000", "000080", "800000", "008080"]
    for c in swatchColors {
        sw := SetupGui.Add("Text", "x+2 yp w18 h18 0x100", "")
        sw.BackColor := c
        sw.ToolTip := c
        sw.OnEvent("Click", SwatchClick)
    }

    ; ---- Alert effect ----
    SetupGui.Add("Text", "xm y+10", "Alert Effect")
    RadioRound := SetupGui.Add("Radio", "xm y+4 Group" (CfgColorEffect = "Round" ? " Checked" : ""), "Round (rotate)")
    RadioBlink := SetupGui.Add("Radio", "x+110 yp" (CfgColorEffect = "Blink" ? " Checked" : ""), "Blink (flash)")

    ; ---- Alert dismiss trigger ----
    SetupGui.Add("Text", "xm y+10", "Alert Dismiss Trigger")
    SetupGui.Add("Text", "xm y+2 c808080", "Timer reset on hover: always on (separate)")
    RadioResetMouse := SetupGui.Add("Radio", "xm y+4 Group" (CfgResetTrigger = "Mouse" ? " Checked" : ""), "Mouse click")
    RadioResetF5 := SetupGui.Add("Radio", "x+110 yp" (CfgResetTrigger = "F5" ? " Checked" : ""), "F5 key")
    RadioResetCtrlR := SetupGui.Add("Radio", "x+60 yp" (CfgResetTrigger = "CtrlR" ? " Checked" : ""), "Ctrl+R")
    RadioResetCombined := SetupGui.Add("Radio", "x+65 yp" (CfgResetTrigger = "Combined" ? " Checked" : ""), "Combined")

    ; ---- Protection / logging ----
    LogCheck := SetupGui.Add("Checkbox", "xm y+10" (CfgLogging ? " Checked" : ""), "Enable logging")
    WordBreakerCheck := SetupGui.Add("Checkbox", "xm y+4" (CfgWordBreaker ? " Checked" : ""), "Smart Word Breaker (typing + copy-paste)")
    SetupGui.Add("Text", "x+8 yp c808080", "Shortcut: Ctrl + Alt + P")

    BtnOk := SetupGui.Add("Button", "xm y+12 w80", "OK")
    BtnOk.OnEvent("Click", ProcessSetup)

    if (TimersStarted)
        SetupGui.OnEvent("Close", (*) => SetupGui.Destroy())
    else
        SetupGui.OnEvent("Close", (*) => ExitApp())
    SetupGui.Show()
}

; --- Pick color: directly open Windows color dialog ---
PickColorDirect(*) {
    global SelectedFixedColor, ColorPreview, SetupGui
    hex := SelectedFixedColor
    hex := StrReplace(hex, "#", "")
    if (StrLen(hex) != 6)
        hex := "FF0000"
    r := Number("0x" SubStr(hex, 1, 2))
    g := Number("0x" SubStr(hex, 3, 2))
    b := Number("0x" SubStr(hex, 5, 2))
    rgbResult := r | (g << 8) | (b << 16)

    static custColors := Buffer(16 * 4, 0)
    cc := Buffer(72, 0)
    NumPut("uint", 72, cc, 0)
    try NumPut("ptr", SetupGui.Hwnd, cc, 8)
    NumPut("ptr", 0, cc, 16)
    NumPut("uint", rgbResult, cc, 24)
    NumPut("ptr", custColors.Ptr, cc, 32)
    NumPut("uint", 0x00000003, cc, 40)
    NumPut("int64", 0, cc, 48)
    NumPut("ptr", 0, cc, 56)
    NumPut("ptr", 0, cc, 64)

    if (DllCall("comdlg32\ChooseColor", "ptr", cc.Ptr, "int")) {
        res := NumGet(cc, 24, "uint")
        r := res & 0xFF
        g := (res >> 8) & 0xFF
        b := (res >> 16) & 0xFF
        SelectedFixedColor := Format("{:02X}{:02X}{:02X}", r, g, b)
        ColorPreview.BackColor := SelectedFixedColor
    }
}

; --- Color swatch click handler ---
SwatchClick(ctrl, *) {
    global SelectedFixedColor, ColorPreview
    if (ctrl.ToolTip != "") {
        SelectedFixedColor := ctrl.ToolTip
        ColorPreview.BackColor := SelectedFixedColor
    }
}

if !(A_IsAdmin) {
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
    }
    ExitApp()
}

; ============================================================
;               AUTO-UPDATER (GitHub raw, public repo)
;  Startup-e version check kore, naya version thakle exe replace kore restart kore
; ============================================================
VersionCompare(v1, v2) {
    a := StrSplit(v1, "."), b := StrSplit(v2, ".")
    Loop 3 {
        x := (a.Has(A_Index) ? Number(a[A_Index]) : 0)
        y := (b.Has(A_Index) ? Number(b[A_Index]) : 0)
        if (x > y)
            return 1
        if (x < y)
            return -1
    }
    return 0
}

CheckForUpdate() {
    global AppVersion, UpdateCheckURL, UpdateExeURL, UpdateTempDir, UpdateExeName
    try {
        DirCreate(UpdateTempDir)
        localV := AppVersion
        ; cache-buster query param jate CDN stale na dey
        local vurl := UpdateCheckURL "?t=" A_TickCount
        local vf := UpdateTempDir "\version.txt"
        try {
            Download(vurl, vf)
        } catch {
            AppLog("update check failed: cannot download version")
            return
        }
        local remoteV := Trim(FileRead(vf), " `t`r`n")
        if (remoteV = "" || VersionCompare(remoteV, localV) <= 0)
            return  ; no new version

        AppLog("update available: " localV " -> " remoteV " - downloading")
        local eurl := UpdateExeURL "?t=" A_TickCount
        local newExe := UpdateTempDir "\new.exe"
        try {
            Download(eurl, newExe)
        } catch {
            AppLog("update download failed")
            return
        }
        if (FileGetSize(newExe) < 100000) {
            AppLog("update failed: file too small")
            return
        }
        ; Write batch updater: wait -> replace -> restart
        local bat := UpdateTempDir "\updater.bat"
        local l1 := '@echo off'
        local l2 := 'timeout /t 5 /nobreak >nul'
        local l3 := ':copyloop'
        local l4 := 'copy /Y "' newExe '" "' A_ScriptFullPath '" >nul 2>&1'
        local l5 := 'if errorlevel 1 ('
        local l6 := '  timeout /t 1 /nobreak >nul'
        local l7 := '  goto copyloop'
        local l8 := ')'
        local l9 := 'start "" "' A_ScriptFullPath '"'
        local l10 := 'del "' bat '" >nul 2>&1'
        local batText := l1 "`r`n" l2 "`r`n" l3 "`r`n" l4 "`r`n" l5 "`r`n" l6 "`r`n" l7 "`r`n" l8 "`r`n" l9 "`r`n" l10 "`r`n"
        FileAppend(batText, bat, "UTF-8")
        AppLog("update staged - restarting via updater")
        Run('cmd /c "' bat '"',, "Hide")
        ExitApp()
    } catch as e {
        AppLog("update error: " e.Message)
    }
}

; Run update check at startup (before setup GUI)
try CheckForUpdate()

; ============================================================
;               SMART WORD BREAKER (only this section changes)
; ============================================================

; Breaks while typing (does not wait for Space) - respects ProtectionEnabled
#HotIf ProtectionEnabled
:?*:email::e-mail
:?*:whatsapp::w-hatsapp
:?*:pay::p-ay
:?*:payment::p-ayment
:?*:paypal::P-ayPal
#HotIf

; --- Smart copy-paste protection ---
OnClipboardChange(UpdateClip)

UpdateClip(Type) {
    global ProtectionEnabled
    
    if (!ProtectionEnabled || Type != 1)
        return

    static isWorking := false
    if (isWorking)
        return
    isWorking := true

    try {
        text := A_Clipboard
        
        if (StrLen(text) < 3) {
            isWorking := false
            return
        }

        ; Skip code / links / files entirely
        if (
            RegExMatch(text, "i)(<\?php|<\?=|function\s|class\s|const\s|let\s|var\s|import\s|require\(|include\(|=>|\{|\}|\[|\]|;|\.php|\.js|\.py|\.css|\.html|\.ts|\.jsx|\.tsx)")
            || RegExMatch(text, "i)(https?://|www\.|ftp://|mailto:)")
            || RegExMatch(text, "i)\b(pay|email|whatsapp|paypal)[\w_]*\s*[=\(\[\{]")
            || RegExMatch(text, "i)^[a-z]:\\") || RegExMatch(text, "i)\\\\[a-z0-9]")
            || (StrLen(text) > 120 && RegExMatch(text, "[\{\}\(\)\[\];=<>`]"))
            || RegExMatch(text, 'i)"\s*:\s*"')
        ) {
            isWorking := false
            return
        }

        ; Break plain text
        newText := text
        newText := RegExReplace(newText, "i)\bpayment\b", "p-ayment")
        newText := RegExReplace(newText, "i)\bpay\b", "p-ay")
        newText := RegExReplace(newText, "i)\bemail\b", "e-mail")
        newText := RegExReplace(newText, "i)\bwhatsapp\b", "w-hatsapp")
        newText := RegExReplace(newText, "i)\bpaypal\b", "P-ayPal")
        ; Normalize em dash to space (preserve word-breaker hyphens)
        newText := StrReplace(newText, Chr(0x2014), " ")

        if (newText != text) {
            A_Clipboard := newText
            Sleep(120)
        }
    } catch {
        ; Ignore on error
    }

    isWorking := false
}

; Emergency Toggle (Ctrl + Alt + P)
^!p:: {
    global ProtectionEnabled, CfgWordBreaker
    ProtectionEnabled := !ProtectionEnabled
    CfgWordBreaker := ProtectionEnabled
    try SaveSettings()
    ToolTip ProtectionEnabled ? "Word Breaker ON" : "Word Breaker OFF"
    SetTimer(() => ToolTip(), -1500)
}

