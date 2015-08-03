/*
ToDo:
* Remove Focus
Down Arrow will move selection

* Callback for pre-binding ?
May need to tell hotkey handler to disable all hotkeys while in Bind Mode.

* Callback after binding selected ?
Hotkey controls may need to be able to ensure uniqueness.

*/
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
		
		callback := this.HotkeyChanged.Bind(this)
		this.MyHotkey := new _CHotkeyControl(hwnd, "MyHotkey", callback, "x5 y5 w200", "~F12")
		this.MyHotkey.Value := "*^F10" ; test setter
		Gui, Show, x0 y0
	}
	
	HotkeyChanged(hkobj){
		;MsgBox % "Hotkey :" hkobj.Name "`nNew Human Readable: " hkobj.HumanReadable "`nNew Hotkey String: " hkobj.Value
		ToolTip % hkobj.Value
	}
}

; ----------------------------- Hotkey GuiControl class ---------------------------
class _CHotkeyControl {
	static _MenuText := "||Toggle Wild (*) |Toggle PassThrough (~)|Remove Binding"
	
	__New(hwnd, name, callback, options := "", default := ""){
		this._Value := default			; AHK Syntax of current binding, eg ~*^!a
		this.HotkeyString := ""		; AHK Syntax of current binding, eg ^!a WITHOUT modes such as * or ~
		this.ModeString := ""
		this.HumanReadable := ""	; Human Readable version of current binding, eg CTRL + SHIFT + A
		this.Wild := 0
		this.PassThrough := 0
		
		this._ParentHwnd := hwnd
		
		this.Name := name
		Gui, % this._ParentHwnd ":Add", DDL, % "hwndhDDL AltSubmit " options
		this._hwnd := hDDl
		fn := this.OptionSelected.Bind(this)
		GuiControl % "+g", % this._hwnd, % fn
		
		this._callback := callback
		
		; Lookup table to accelerate finding which mouse button was pressed
		this._MouseLookup := {}
		this._MouseLookup[0x201] := { name: "LButton", event: 1 }
		this._MouseLookup[0x202] := { name: "LButton", event: 0 }
		this._MouseLookup[0x204] := { name: "RButton", event: 1 }
		this._MouseLookup[0x205] := { name: "RButton", event: 0 }
		this._MouseLookup[0x207] := { name: "MButton", event: 1 }
		this._MouseLookup[0x208] := { name: "MButton", event: 0 }
		
		this.Value := this._Value	; trigger __Set meta-func to configure control
	}
	
	; value was set
	__Set(aParam, aValue){
		if (aParam = "value"){
			this._ValueSet(aValue)
			return this._Value
		}
	}
	
	; Read of value
	__Get(aParam){
		if (aParam = "value"){
			return this._Value
		}
	}

	; Change hotkey AND modes to new values
	_ValueSet(hotkey_string){
		arr := this._SplitModes(hotkey_string)
		this._SetModes(arr[1])
		this.HotkeyString := arr[2]
		this._HotkeySet()
	}
	
	; Change hotkey only and LEAVE modes
	_HotkeySet(){
		this.HumanReadable := this._BuildHumanReadable(this.HotkeyString)
		this._value := this.ModeString this.HotkeyString
		this._UpdateGuiControl()
	}
	
	; ============== HOTKEY MANAGEMENT ============
	; An option was selected in the drop-down list
	OptionSelected(){
		GuiControlGet, option,, % this._hwnd
		GuiControl, Choose, % this._hwnd, 1
		if (option = 1){
			; Bind Mode
			;ToolTip Bind MODE
			this._BindMode()
			
		} else if (option = 2){
			;ToolTip Wild Option Changed
			this.Wild := !this.Wild
			this._HotkeySet()
			this._callback.(this)
		} else if (option = 3){
			;ToolTip PassThrough Option Changed
			this.PassThrough := !this.PassThrough
			this._HotkeySet()
			this._callback.(this)
		} else if (option = 4){
			;ToolTip Remove Binding
			this.Value := ""
			this._callback.(this)		
		}
	}
	
	; Bind mode was enabled
	_BindMode(){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		static modifier_symbols := {91: "#", 92: "#", 160: "+", 161: "+", 162: "^", 163: "^", 164: "!", 165: "!"}
		;static modifier_lr_variants := {91: "<", 92: ">", 160: "<", 161: ">", 162: "<", 163: ">", 164: "<", 165: ">"}


		this._BindModeState := 1
		this._SelectedInput := []
		this._LastKeyCode := 0
		
		Gui, new, hwndhPrompt -Border +AlwaysOnTop
		Gui, % hPrompt ":Add", Text, w300 h100 Center, BIND MODE`n`nPress the desired key combination.`n`nBinding ends when you release a key.`nPress Esc to exit.
		Gui,  % hPrompt ":Show"
		
		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback(this._ProcessKHook,"Fast",,&this)) ; fn)
		this._hHookMouse := this._SetWindowsHookEx(WH_MOUSE_LL, RegisterCallback(this._ProcessMHook,"Fast",,&this)) ; fn)
		Loop {
			if (this._BindModeState = 0){
				break
			}
			Sleep 10
		}	
		this._UnhookWindowsHookEx(this._hHookKeybd)
		this._UnhookWindowsHookEx(this._hHookMouse)
		Gui,  % hPrompt ":Destroy"
		
		out := ""
		end_modifier := 0
		
		if (this._SelectedInput.length() < 1){
			return
		}

		; Prefix with current modes
		hotkey_string := ""
		if (this.Wild){
			hotkey_string .= "*"
		}
		if (this.PassThrough){
			hotkey_string .= "~"
		}

		; build hotkey string
		l := this._SelectedInput.length()
		Loop % l {
			if (this._SelectedInput[A_Index].Type = "k" && this._SelectedInput[A_Index].modifier && A_Index != l){
				hotkey_string .= modifier_symbols[this._SelectedInput[A_Index].code]
			} else {
				hotkey_string .= this._SelectedInput[A_Index].name
			}
		}
		
		; trigger __Set meta-func to configure control
		this.Value := hotkey_string
		
		; Fire the OnChange callback
		this._callback.(this)
	}
	
	; Converts an AHK hotkey string (eg "^+a"), plus the state of WILD and PASSTHROUGH properties to Human Readable format (eg "(WP) CTRL+SHIFT+A")
	_BuildHumanReadable(hotkey_string){
		static modifier_names := {"+": "Shift", "^": "Ctrl", "!": "Alt", "#": "Win"}
		
		dbg := "TRANSLATING: " hotkey_string " : "
		
		if (hotkey_string = ""){
			return "(Select to Bind)"
		}
		str := ""
		mode_str := ""
		idx := 1
		; Add mode indicators
		if (this.Wild){
			mode_str .= "W"
		}
		if (this.PassThrough){
			mode_str .= "P"
		}
		
		if (mode_str){
			str := "(" mode_str ") " str
		}
		
		idx := 1
		; Parse modifiers
		Loop % StrLen(hotkey_string) {
			chr := SubStr(hotkey_string, A_Index, 1)
			if (ObjHasKey(modifier_names, chr)){
				str .= modifier_names[chr] " + "
				idx++
			} else {
				break
			}
		}
		str .= SubStr(hotkey_string, idx)
		StringUpper, str, str
		
		;OutputDebug % "BHR: " dbg hotkey_string
		return str
	}

	; Splits a hotkey string (eg *~^a" into an array with 1st item modes (eg "*~") and 2nd item the rest of the hotkey (eg "^a")
	_SplitModes(hotkey_string){
		mode_str := ""
		idx := 0
		Loop % StrLen(hotkey_string) {
			chr := SubStr(hotkey_string, A_Index, 1)
			if (chr = "*" || chr = "~"){
				idx++
			} else {
				break
			}
		}
		if (idx){
			mode_str := SubStr(hotkey_string, 1, idx)
		}
		return [mode_str, SubStr(hotkey_string, idx + 1)]
	}
	
	; Sets modes from a mode string (eg "*~")
	_SetModes(hotkey_string){
		this.Wild := 0
		this.PassThrough := 0
		this.ModeString := ""
		Loop % StrLen(hotkey_string) {
			chr := SubStr(hotkey_string, A_Index, 1)
			if (chr = "*"){
				this.Wild := 1
			} else if (chr = "~"){
				this.PassThrough := 1
			} else {
				break
			}
			this.ModeString .= chr
		}
	}
	
	; The binding changed - update the GuiControl
	_UpdateGuiControl(){
		GuiControl, , % this._hwnd, % "|" modes this.HumanReadable this._MenuText
	}
	
	; ============= HOOK HANDLING =================
	_SetWindowsHookEx(idHook, pfn){
		Return DllCall("SetWindowsHookEx", "Ptr", idHook, "Ptr", pfn, "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr")
	}
	
	_UnhookWindowsHookEx(idHook){
		Return DllCall("UnhookWindowsHookEx", "Ptr", idHook)
	}
	
	; Converts a virtual key code / scan code to a key name
	_GetKeyName(keycode,scancode){
		return GetKeyName(Format("vk{1:x}sc{2:x}", keycode,scancode))
	}
	
	
	; Process Keyboard messages from Hooks
	_ProcessKHook(wParam, lParam){
		; KBDLLHOOKSTRUCT structure: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644967%28v=vs.85%29.aspx
		; KeyboardProc function: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644984(v=vs.85).aspx
		
		; ToDo:
		; Use Repeat count, transition state bits from lParam to filter keys
		
		static WM_KEYDOWN := 0x100, WM_KEYUP := 0x101, WM_SYSKEYDOWN
		
		Critical
		
		if (this<0){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		
		keycode := NumGet(lParam+0,0,"Uint")
		scanCode:= NumGet(lparam+0,4,"UInt")
		
		vk := NumGet(lParam+0, "UInt")
		Extended := NumGet(lParam+0, 8, "UInt") & 1
		sc := (Extended<<8)|NumGet(lParam+0, 4, "UInt")
		sc := sc = 0x136 ? 0x36 : sc

		
		OutputDebug % "Processing Key Hook... VK: " vk " | SC: " sc " | WP: " wParam
		
		; Find out if key went up or down, plus filter repeated down events
		if (wParam = WM_SYSKEYDOWN || wParam = WM_KEYDOWN) {
			event := 1
			if (this._LastKeyCode = keycode){
				return 1
			}
			this._LastKeyCode := keycode
		} else if (wParam = WM_KEYUP) {
			event := 0
		}

		modifier := (keycode >= 160 && keycode <= 165) || (keycode >= 91 && keycode <= 93)

		;OutputDebug, % "Key Code: " keycode ", event: " event ", name: " GetKeyName(Format("vk{:x}", keycode)) ", modifier: " modifier
		
		this._ProcessInput({Type: "k", name: this._GetKeyName(vk, sc) , code : vk, event: event, modifier: modifier})
		return 1	; block key
	}
	
	; Process Mouse messages from Hooks
	_ProcessMHook(wParam, lParam){
		/*
		typedef struct tagMSLLHOOKSTRUCT {
		  POINT     pt;
		  DWORD     mouseData;
		  DWORD     flags;
		  DWORD     time;
		  ULONG_PTR dwExtraInfo;
		}
		*/
		; MSLLHOOKSTRUCT structure: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644970(v=vs.85).aspx
		static WM_LBUTTONDOWN := 0x0201, WM_LBUTTONUP := 0x0202 , WM_RBUTTONDOWN := 0x0204, WM_RBUTTONUP := 0x0205, WM_MBUTTONDOWN := 0x0207, WM_MBUTTONUP := 0x0208, WM_MOUSEHWHEEL := 0x20E, WM_MOUSEWHEEL := 0x020A, WM_XBUTTONDOWN := 0x020B, WM_XBUTTONUP := 0x020C
		Critical
		if (this<0 || wParam = 0x200){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookMouse, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		out := "Mouse: " wParam " "
		
		keyname := ""
		event := 0
		
		if (IsObject(this._MouseLookup[wParam])){
			; L / R / M  buttons
			keyname := this._MouseLookup[wParam].name
			event := 1
		} else {
			; Wheel / XButtons
			; Find HiWord of mouseData from Struct
			mouseData := NumGet(lParam+0, 10, "Short")
			
			if (wParam = WM_MOUSEHWHEEL || wParam = WM_MOUSEWHEEL){
				; Mouse Wheel - mouseData indicate direction (up/down)
				event := 1	; wheel has no up event, only down
				if (wParam = WM_MOUSEWHEEL){
					keyname .= "Wheel"
					if (mouseData > 1){
						keyname .= "U"
					} else {
						keyname .= "D"
					}
				} else {
					keyname .= "Wheel"
					if (mouseData > 1){
						keyname .= "R"
					} else {
						keyname .= "L"
					}
				}
			} else if (wParam = WM_XBUTTONDOWN || wParam = WM_XBUTTONUP){
				; X Buttons - mouseData indicates Xbutton 1 or Xbutton2
				if (wParam = WM_XBUTTONDOWN){
					event := 1
				} else {
					event := 0
				}
				keyname := "XButton" mouseData
			}
		}
		
		;OutputDebug % "Mouse: " keyname ", event: " event
		this._ProcessInput({Type: "m", name: keyname, event: event})
		return 1
	}

	; All input (keyboard, mouse, joystick) should flow through here when in Bind Mode
	_ProcessInput(obj){
		;{Type: "k", name: keyname, code : keycode, event: event, modifier: modifier}
		;{Type: "m", name: keyname, event: event}
		modifier := 0
		out := "PROCESSINPUT: "
		if (obj.Type = "k"){
			out .= "key = " obj.name ", code: " obj.code
			if (obj.code == 27){
				;Escape
				this._BindModeState := 0
				return
			}
			modifier := obj.modifier
		} else if (obj.Type = "m"){
			out .= "mouse = " obj.name
		} else if (obj.Type = "j"){
			
		}
		
		; Detect if Bind Mode should end
		;OutputDebug % out
		if (obj.event = 0){
			; key / button up
			this._BindModeState := 0
		} else {
			; key / button down
			this._SelectedInput.push(obj)
			; End if not modifier
			if (!modifier){
				this._BindModeState := 0
			}
		}
	}
}