#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Konfiguracja ---
global ARTIFACT_NAME := "Affinity Keyboard"
global AffinityExe := "Affinity.exe"
global BTN_HEIGHT := 25, PADDING := 5
global FONT_FAMILY := "Segoe UI"
global IniFile := A_ScriptDir "\AffinityKeyboard_Settings.ini"

; --- Zmienne Globalne GDI+ (Caching) ---
global gdiplusToken := 0
global hdcScreen := 0, hdcMem := 0, hbm := 0, pGraphics := 0
global pFont := 0, pFormat := 0, pBrushText := 0
global guiWidth := 0, guiHeight := 0
global hoveredButtonIndex := 0

; --- Wczytywanie ustawień ---
global posX := IniRead(IniFile, "Position", "X", 200)
global posY := IniRead(IniFile, "Position", "Y", 200)

; --- Inicjalizacja GDI+ ---
if !(gdiplusToken := Gdip_Startup()) {
    MsgBox("Krytyczny błąd: Nie można uruchomić biblioteki GDI+!")
    ExitApp
}

; --- Definicje przycisków ---
global buttons := []
buttons_data := [
    {name:"New",     color:0xFF8BC34A, action:"^n"},
    {name:"Open",    color:0xFF03A9F4, action:"^o"},
    {name:"Copy",    color:0xFFFFC107, action:"^c"},
    {name:"Paste",   color:0xFFFFEB3B, action:"^v"},
    {name:"Undo",    color:0xFFFF7043, action:"^z"},
    {name:"Redo",    color:0xFFE91E63, action:"^+z"},
    {name:"Delete",  color:0xFF9E9E9E, action:"{Backspace}"},
    {name:"Invert",  color:0xFFC47DD0, action:"^i"},
    {name:"Fit",     color:0xFFADD8E6, action:"^0"},
    {name:"[",       color:0xFFEBEBEB, action:"["},
    {name:"]",       color:0xFFEBEBEB, action:"]"},
	{name:"Merge.S", color:0xFF32FD53, action:"^+e"},
    {name:"Inpainting", color:0xFF2BE6FF, action:"{Alt down}{Shift down}{Backspace}{Shift up}{Alt up}"},	
	{name:"Duplicate", color:0xFFFFA0F0, action:"^j"},
	{name:"Exp2JPG", color:0xFFFFEB3B, action:"^!+w"}
]

; --- Oblicz rozmiar czcionki ---
longest_name := ""
for _, btn_data in buttons_data {
    if StrLen(btn_data.name) > StrLen(longest_name)
        longest_name := btn_data.name
}

; Oblicz max rozmiar czcionki (targetW=100)
global maxFontSize := CalculateMaxFontSize(FONT_FAMILY, longest_name, 100, BTN_HEIGHT, 8)

; Inicjalizacja pędzla i czcionki (Caching)
pFontFamily := Gdip_FontFamilyCreate(FONT_FAMILY)
pFont := Gdip_FontCreate(pFontFamily, maxFontSize, 1)
pFormat := Gdip_StringFormatCreate()
Gdip_StringFormatSetAlign(pFormat, 1)
Gdip_StringFormatSetLineAlign(pFormat, 1)
pBrushText := Gdip_BrushCreateSolid(0xFF000000)
Gdip_DeleteFontFamily(pFontFamily)

x := PADDING
for _, btn_data in buttons_data {
    textWidth := MeasureTextWidth(btn_data.name, maxFontSize, FONT_FAMILY)
    nameLength := StrLen(btn_data.name)
    charPadding := (nameLength > 0) ? (textWidth / nameLength) : MeasureTextWidth("M", maxFontSize, FONT_FAMILY)
    btn_width := Round(textWidth + (2 * charPadding))

    btn_data.x := x, btn_data.y := PADDING, btn_data.w := btn_width, btn_data.h := BTN_HEIGHT
    buttons.Push(btn_data)
    x += btn_width + PADDING
}
; Przycisk wyjścia
buttons.Push({name: "X", color: 0xFFF44336, action: "ExitApp", x: x + 10, y: PADDING, w: 25, h: 25})

lastBtn := buttons[buttons.Length]
guiWidth := lastBtn.x + lastBtn.w + PADDING
guiHeight := BTN_HEIGHT + PADDING * 2

; --- Tworzenie GUI (Layered Window) ---
MyGui := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x80000") ; E0x80000 = WS_EX_LAYERED
MyGui.OnEvent("Close", CleanupAndExit)

; Przygotuj bufory GDI+ (DIB Section dla Layered Window)
hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
hbm := CreateDIBSection(guiWidth, guiHeight)
obm := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
pGraphics := Gdip_GraphicsFromHDC(hdcMem)
Gdip_SetSmoothingMode(pGraphics, 4)

; Wspieranie przesuwania i komunikatów
OnMessage(0x201, WM_LBUTTONDOWN)
OnMessage(0x200, WM_MOUSEMOVE)

UpdateUI()
MyGui.Show("x" posX " y" posY " w" guiWidth " h" guiHeight " NA")
return

; === GŁÓWNE FUNKCJE ===

UpdateUI() {
    global MyGui, pGraphics, hbm, hdcMem, hdcScreen, guiWidth, guiHeight, hoveredButtonIndex, buttons
    global pFont, pFormat, pBrushText

    try {
        Gdip_GraphicsClear(pGraphics, 0x00000000) ; Przezroczyste tło
        
        ; Tło paska (ciemne)
        pBrushMainBG := Gdip_BrushCreateSolid(0xFF404040)
        Gdip_FillRectangle(pGraphics, pBrushMainBG, 0, 0, guiWidth, guiHeight)
        Gdip_DeleteBrush(pBrushMainBG)

        for i, btn in buttons {
            color := btn.color
            if (i == hoveredButtonIndex) {
                ; Hover effect: lighter/dimmed
                color := (color & 0x00FFFFFF) | 0xB3000000 
            }
            
            pBrushBG := Gdip_BrushCreateSolid(color)
            Gdip_FillRectangle(pGraphics, pBrushBG, btn.x, btn.y, btn.w, btn.h)
            Gdip_DrawString(pGraphics, btn.name, pFont, pFormat, pBrushText, btn.x, btn.y, btn.w, btn.h)
            Gdip_DeleteBrush(pBrushBG)
        }

        ; Odśwież okno warstwowe
        UpdateLayeredWindow(MyGui.Hwnd, hdcMem, hdcScreen, guiWidth, guiHeight)
    } catch Error as err {
        ; Cichy błąd, żeby nie blokował UI
        OutputDebug("Redraw Error: " err.Message)
    }
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    Critical
    global MyGui, buttons, hoveredButtonIndex
    if (hwnd != MyGui.Hwnd)
        return

    x := lParam & 0xFFFF
    y := (lParam >> 16) & 0xFFFF
    
    currentlyHovered := 0
    for i, btn in buttons {
        if (x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h) {
            currentlyHovered := i
            break
        }
    }

    if (currentlyHovered != hoveredButtonIndex) {
        hoveredButtonIndex := currentlyHovered
        UpdateUI()
    }
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    Critical
    global MyGui, buttons, IniFile, posX, posY
    if (hwnd != MyGui.Hwnd)
        return

    x := lParam & 0xFFFF
    y := (lParam >> 16) & 0xFFFF
    
    for _, btn in buttons {
        if (x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h) {
            if (btn.action = "ExitApp") {
                CleanupAndExit()
            } else {
                SendToAffinity(btn.action)
            }
            return
        }
    }
    PostMessage(0xA1, 2, , , "A") ; Drag window
}

SendToAffinity(shortcut) {
    global AffinityExe
    if WinExist("ahk_exe " AffinityExe) {
        try {
            WinActivate("ahk_exe " AffinityExe)
            if WinActive("ahk_exe " AffinityExe)
                Send(shortcut)
        } catch Error as err {
            TrayTip("Błąd wysyłania: " err.Message, ARTIFACT_NAME)
        }
    } else {
        TrayTip("Nie można znaleźć procesu " AffinityExe, ARTIFACT_NAME, 2)
    }
}

CleanupAndExit(*) {
    global MyGui, IniFile, gdiplusToken
    global hdcScreen, hdcMem, hbm, pGraphics, pFont, pFormat, pBrushText

    ; Zapisz pozycję
    try {
        WinGetPos(&px, &py, , , MyGui.Hwnd)
        IniWrite(px, IniFile, "Position", "X")
        IniWrite(py, IniFile, "Position", "Y")
    }
    
    ; Zwolnij zasoby
    Gdip_DeleteGraphics(pGraphics)
    DllCall("SelectObject", "ptr", hdcMem, "ptr", obm)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdcMem)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)
    
    Gdip_DeleteFont(pFont)
    Gdip_DeleteStringFormat(pFormat)
    Gdip_DeleteBrush(pBrushText)
    
    Gdip_Shutdown(gdiplusToken)
    ExitApp
}

; --- POMOCNICZE FUNKCJE GDI+ ---

MeasureTextWidth(text, fontSize, fontFamily) {
    hdc := DllCall("GetDC", "ptr", 0)
    pGraphics := Gdip_GraphicsFromHDC(hdc)
    pFamilyObj := Gdip_FontFamilyCreate(fontFamily)
    pFont := Gdip_FontCreate(pFamilyObj, fontSize, 1)
    
    layoutRect := Buffer(16), NumPut("float", 0, "float", 0, "float", 1000, "float", 100, layoutRect)
    boundingBox := Buffer(16)
    Gdip_MeasureString(pGraphics, text, pFont, layoutRect, 0, boundingBox)
    measuredW := NumGet(boundingBox, 8, "float")
    
    Gdip_DeleteFont(pFont)
    Gdip_DeleteFontFamily(pFamilyObj)
    Gdip_DeleteGraphics(pGraphics)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return measuredW
}

CalculateMaxFontSize(fontFamily, textToMeasure, targetW, targetH, textPadding) {
    hdc := DllCall("GetDC", "ptr", 0)
    pg := Gdip_GraphicsFromHDC(hdc)
    pf := Gdip_FontFamilyCreate(fontFamily)
    lr := Buffer(16), NumPut("float", 0, "float", 0, "float", targetW, "float", targetH, lr)
    bb := Buffer(16)

    size := 16
    while (size >= 4) {
        f := Gdip_FontCreate(pf, size, 1)
        Gdip_MeasureString(pg, textToMeasure, f, lr, 0, bb)
        w := NumGet(bb, 8, "float")
        h := NumGet(bb, 12, "float")
        Gdip_DeleteFont(f)
        if (w < targetW - textPadding && h < targetH) {
            Gdip_DeleteFontFamily(pf)
            Gdip_DeleteGraphics(pg)
            DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
            return size
        }
        size -= 0.5
    }
    Gdip_DeleteFontFamily(pf)
    Gdip_DeleteGraphics(pg)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return 8
}

UpdateLayeredWindow(hwnd, hdcMem, hdcScreen, w, h) {
    DllCall("UpdateLayeredWindow", "ptr", hwnd, "ptr", hdcScreen, "ptr", 0, "int64*", w | (h << 32), "ptr", hdcMem, "int64*", 0, "uint", 0, "int*", 0xFF << 16 | 1 << 24, "uint", 2)
}

CreateDIBSection(w, h, hdc := 0) {
    hdc := hdc ? hdc : DllCall("GetDC", "ptr", 0, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", w, bi, 4)
    NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    NumPut("uint", 0, bi, 16)
    
    hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bi, "uint", 0, "ptr*", 0, "ptr", 0, "uint", 0, "ptr")
    if !hdc
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return hbm
}

; --- BIBLIOTEKA GDI+ (Zoptymalizowana pod v2) ---
Gdip_Startup() {
    if !DllCall("GetModuleHandle", "str", "gdiplus", "ptr")
        DllCall("LoadLibrary", "str", "gdiplus")
    pToken := Buffer(A_PtrSize)
    si := Buffer(24, 0), NumPut("int", 1, si)
    if DllCall("gdiplus\GdiplusStartup", "ptr", pToken, "ptr", si, "ptr", 0)
        return 0
    return NumGet(pToken, "ptr")
}
Gdip_Shutdown(pToken) => DllCall("gdiplus\GdiplusShutdown", "ptr", pToken)
Gdip_GraphicsFromHDC(hdc) {
    pGraphics := Buffer(A_PtrSize)
    DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc, "ptr", pGraphics)
    return NumGet(pGraphics, "ptr")
}
Gdip_GraphicsFromImage(hbm) {
    pGraphics := Buffer(A_PtrSize)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", hbm, "ptr", pGraphics)
    return NumGet(pGraphics, "ptr")
}
Gdip_CreateBitmap(w, h) {
    pBitmap := Buffer(A_PtrSize)
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h, "int", 0, "int", 0x26200A, "ptr", 0, "ptr", pBitmap)
    return NumGet(pBitmap, "ptr")
}
Gdip_GraphicsClear(pGraphics, color := 0) => DllCall("gdiplus\GdipGraphicsClear", "ptr", pGraphics, "uint", color)
Gdip_DeleteGraphics(pGraphics) => DllCall("gdiplus\GdipDeleteGraphics", "ptr", pGraphics)
Gdip_DisposeImage(pBitmap) => DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
Gdip_SetSmoothingMode(pGraphics, mode) => DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pGraphics, "int", mode)
Gdip_BrushCreateSolid(color) {
    pBrush := Buffer(A_PtrSize)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", color, "ptr", pBrush)
    return NumGet(pBrush, "ptr")
}
Gdip_DeleteBrush(pBrush) => DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
Gdip_FillRectangle(pGraphics, pBrush, x, y, w, h) => DllCall("gdiplus\GdipFillRectangle", "ptr", pGraphics, "ptr", pBrush, "float", x, "float", y, "float", w, "float", h)
Gdip_StringFormatCreate() {
    pFormat := Buffer(A_PtrSize)
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr", pFormat)
    return NumGet(pFormat, "ptr")
}
Gdip_DeleteStringFormat(pFormat) => DllCall("gdiplus\GdipDeleteStringFormat", "ptr", pFormat)
Gdip_StringFormatSetAlign(pFormat, align) => DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", pFormat, "int", align)
Gdip_StringFormatSetLineAlign(pFormat, align) => DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", pFormat, "int", align)
Gdip_DrawString(pGraphics, s, pFont, pFormat, pBrush, x, y, w, h) {
    r := Buffer(16), NumPut("float", x, "float", y, "float", w, "float", h, r)
    DllCall("gdiplus\GdipDrawString", "ptr", pGraphics, "str", s, "int", -1, "ptr", pFont, "ptr", r, "ptr", pFormat, "ptr", pBrush)
}
Gdip_FontFamilyCreate(sFamily) {
    pFamily := Buffer(A_PtrSize)
    if DllCall("gdiplus\GdipCreateFontFamilyFromName", "str", sFamily, "ptr", 0, "ptr", pFamily)
        return 0
    return NumGet(pFamily, "ptr")
}
Gdip_DeleteFontFamily(pFamily) => DllCall("gdiplus\GdipDeleteFontFamily", "ptr", pFamily)
Gdip_FontCreate(pFamily, nSize, nStyle := 0) {
    pFont := Buffer(A_PtrSize)
    DllCall("gdiplus\GdipCreateFont", "ptr", pFamily, "float", nSize, "int", nStyle, "int", 2, "ptr", pFont)
    return NumGet(pFont, "ptr")
}
Gdip_DeleteFont(pFont) => DllCall("gdiplus\GdipDeleteFont", "ptr", pFont)
Gdip_MeasureString(pGraphics, s, pFont, pLayoutRect, pFormat, pBoundingBox) {
    DllCall("gdiplus\GdipMeasureString", "ptr", pGraphics, "str", s, "int", -1, "ptr", pFont, "ptr", pLayoutRect, "ptr", pFormat, "ptr", pBoundingBox, "ptr*", 0, "ptr*", 0)
}
