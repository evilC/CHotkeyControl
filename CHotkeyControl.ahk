/*
ToDo:
* Meta-Function to trap set of value and update gui

* Implement Default binding

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
		this.MyHotkey := new _CHotkeyControl(hwnd, "MyHotkey", callback, "x5 y5 w200", "F12")
		;this.MyHotkey.Value := "F10" ; test setter
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
		this.Value := ""			; AHK Syntax of current binding, eg ~*^!a
		this.HotkeyString := ""		; AHK Syntax of current binding, eg ^!a WITHOUT modes such as * or ~
		this.HumanReadable := ""	; Human Readable version of current binding, eg CTRL + SHIFT + A
		this.Wild := 0
		this.PassThrough := 0
		
		this._ParentHwnd := hwnd
		
		this.Name := name
		Gui, % this._ParentHwnd ":Add", DDL, % "hwndhDDL AltSubmit " options
		this._hwnd := hDDl
		this._BindingChanged()
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
	}
	
	/*
	__Set(aParam, aValue){
		if (aParam = "value"){
			;return this._parent.GuiControl(,this, aValue)
			;this.Value := aValue
			;this._BindingChanged()
		}
	}
	*/
	
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
			this._BindingChanged()
			this._callback.(this)
		} else if (option = 3){
			;ToolTip PassThrough Option Changed
			this.PassThrough := !this.PassThrough
			this._BindingChanged()
			this._callback.(this)
		} else if (option = 4){
			;ToolTip Remove Binding
			this.HumanReadable := ""
			this.HotkeyString := ""
			this._BindingChanged()
			this._callback.(this)		
		}
	}
	
	_BindMode(){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		static modifier_symbols := {91: "#", 92: "#", 160: "+", 161: "+", 162: "^", 163: "^", 164: "!", 165: "!"}
		static modifier_lr_variants := {91: "<", 92: ">", 160: "<", 161: ">", 162: "<", 163: ">", 164: "<", 165: ">"}


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
		Loop % this._SelectedInput.length(){
			i := A_Index
			if (this._SelectedInput[i].Type = "k" && this._SelectedInput[i].modifier){
				; modifier key
				end_modifier := i
			} else {
				; end key
				if (end_modifier){
					; Strip L/R prefix from modifiers previous to this key
					Loop % end_modifier {
						this._SelectedInput[A_Index].name := SubStr(this._SelectedInput[A_Index].name, 2)
					}
				}
			}
		}

		hotkey_string := ""
		hotkey_human := ""

		l := this._SelectedInput.length()
		Loop % l {
			i := A_Index
			if (i > 1 ){
				hotkey_human .= " + "
			}
			if (this._SelectedInput[i].Type = "k" && this._SelectedInput[i].modifier && A_Index != l){
				hotkey_string .= modifier_symbols[this._SelectedInput[i].code]
			} else {
				hotkey_string .= this._SelectedInput[i].name
			}
			hotkey_human .= this._SelectedInput[i].name
		}
		
		StringUpper, hotkey_human, hotkey_human
		; Set object properties
		this.HotkeyString := hotkey_string
		this.HumanReadable := hotkey_human
		
		; Update the ListBox
		this._BindingChanged()
		
		; Fire the OnChange callback
		this._callback.(this)
		;this._callback.(this._name, hotkey_human)
		;MsgBox % "You hit: " out
	}
	
	_BindingChanged(){
		modes := ""
		if (this.HotkeyString){
			if (this.Wild){
				modes .= "*"
			}
			if (this.PassThrough){
				modes .= "~"
			}
		}
		hotkey_string := modes this.HotkeyString
		
		modes := ""
		if (this.HumanReadable = ""){
			Text := "(Unbound)"
		} else {
			Text := this.HumanReadable
			if (this.Wild){
				modes .= "W"
			}
			if (this.PassThrough){
				modes .= "P"
			}
			if (modes){
				modes := "(" modes ") "
			}
		}
		this.Value := hotkey_string
		GuiControl, , % this._hwnd, % "|" modes Text this._MenuText
	}
	
	_SetWindowsHookEx(idHook, pfn){
		Return DllCall("SetWindowsHookEx", "Ptr", idHook, "Ptr", pfn, "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr")
	}
	
	_UnhookWindowsHookEx(idHook){
		Return DllCall("UnhookWindowsHookEx", "Ptr", idHook)
	}
	
	_GetKeyName(keycode){
		return GetKeyName(Format("vk{:x}", keycode))
	}
	
	; Process Keyboard messages from Hooks
	_ProcessKHook(wParam, lParam){
		; KBDLLHOOKSTRUCT structure: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644967%28v=vs.85%29.aspx
		; KeyboardProc function: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644984(v=vs.85).aspx
		
		; ToDo:
		; Use Repeat count, transition state bits from lParam to filter keys
		
		Critical
		
		if (this<0){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		
		keycode := NumGet(lParam+0,0,"Uint")
		
		; Find the key code and whether key went up/down
		if (wParam = 0x100) || (wParam = 0x101) {
			; WM_KEYDOWN || WM_KEYUP message received
			; Normal keys / Release of ALT
			if (wParam = 260){
				; L/R ALT released
				event := 0
			} else {
				; Down event message is 0x100, up is 0x100
				event := abs(wParam - 0x101)
			}
		} else if (wParam = 260){
			; Alt keys pressed
			event := 1
		}
		
		; We now know the keycode and the event - filter out repeat down events
		if (event){
			if (this._LastKeyCode = keycode){
				return 1
			}
			this._LastKeyCode := keycode
		}

	
		modifier := 0
		; Determine if key is modifier or normal key
		if ( (keycode >= 160 && keycode <= 165) || (keycode >= 91 && keycode <= 93) ) {
			modifier := 1
		}


		;OutputDebug, % "Key Code: " keycode ", event: " event ", name: " GetKeyName(Format("vk{:x}", keycode)) ", modifier: " modifier
		
		this._ProcessInput({Type: "k", name: this._GetKeyName(keycode) , code : keycode, event: event, modifier: modifier})
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
		OutputDebug % out
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