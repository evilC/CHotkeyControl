#include CHotkeyControl.ahk

; ----------------------------- Test script ---------------------------
#SingleInstance force
OutputDebug DBGVIEWCLEAR
test := new test()

return

GuiClose:
ExitApp

class test {
	__New(){
		Gui, new, hwndhwnd
		this._hwnd := hwnd
		
		this.Hotkeys := {}
		
		callback := this.HotkeyChanged.Bind(this)
		this.MyHotkey := new _CHotkeyControl(hwnd, "MyHotkey", callback, "x5 y5 w200", "F12")
		this.MyHotkey.Value := "~+a" ; test setter
		Gui, Show, x0 y0
	}
	
	HotkeyChanged(hkobj){
		;MsgBox % "Hotkey :" hkobj.Name "`nNew Human Readable: " hkobj.HumanReadable "`nNew Hotkey String: " hkobj.Value
		ToolTip % hkobj.Value
		if (IsObject(this.Hotkeys[hkobj.name]) && this.Hotkeys[hkobj.name].binding){
			; hotkey already bound, un-bind first
			hotkey, % this.Hotkeys[hkobj.name].binding, Off
			hotkey, % this.Hotkeys[hkobj.name].binding " up", Off
		}
		; Bind new hotkey
		this.Hotkeys[hkobj.name] := {binding: hkobj.Value}
		fn := this.HotkeyPressed.Bind(this, hkobj, 1)
		hotkey, % hkobj.Value, % fn
		hotkey, % hkobj.Value, On
		
		fn := this.HotkeyPressed.Bind(this, hkobj, 0)
		hotkey, % hkobj.Value " up", % fn
		hotkey, % hkobj.Value " up", On
		OutputDebug % "BINDING: " hkobj._Value
	}
	
	HotkeyPressed(hkobj, state){
		if (state){
			SoundBeep, 1000, 200
		} else {
			SoundBeep, 500, 200
		}
	}
}

