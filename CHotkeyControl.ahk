/*
ToDo:

* Shift + Numpad (with numlock on) does not work
An up event is received for shift before down event.
eg turn numlock on, hold Shift, Hit Numpad8
Callback occurs for up event of shift before the callback occurs for the down event of NumPadUp
+Numpad8 as an AHK hotkey never triggers, so this is not a valid combo.

* Callback for pre-binding ?
May need to tell hotkey handler to disable all hotkeys while in Bind Mode.

* Callback after binding selected ?
Hotkey controls may need to be able to ensure uniqueness.

*/

; ----------------------------- Hotkey GuiControl class ---------------------------
class _CHotkeyControl {
	static _MenuText := "Select new Binding|Toggle Wild (*) |Toggle PassThrough (~)|Remove Binding"
	
	__New(hwnd, name, callback, options := "", default := ""){
		this._Value := default			; AHK Syntax of current binding, eg ~*^!a
		this.HotkeyString := ""		; AHK Syntax of current binding, eg ^!a WITHOUT modes such as * or ~
		this.ModeString := ""
		this.HumanReadable := ""	; Human Readable version of current binding, eg CTRL + SHIFT + A
		this.Wild := 0
		this.PassThrough := 0
		this._ParentHwnd := hwnd
		this.Name := name
		this._callback := callback
		
		; Lookup table to accelerate finding which mouse button was pressed
		this._MouseLookup := {}
		this._MouseLookup[0x201] := { name: "LButton", event: 1 }
		this._MouseLookup[0x202] := { name: "LButton", event: 0 }
		this._MouseLookup[0x204] := { name: "RButton", event: 1 }
		this._MouseLookup[0x205] := { name: "RButton", event: 0 }
		this._MouseLookup[0x207] := { name: "MButton", event: 1 }
		this._MouseLookup[0x208] := { name: "MButton", event: 0 }

		; Add the GuiControl
		Gui, % this._ParentHwnd ":Add", ComboBox, % "hwndhwnd AltSubmit " options, % this._MenuText
		this._hwnd := hwnd
		
		; Find hwnd of EditBox that is a child of the ComboBox
		this._hEdit := DllCall("GetWindow","PTR",this._hwnd,"Uint",5) ;GW_CHILD = 5
		
		; Bind an OnChange event
		fn := this.OptionSelected.Bind(this)
		GuiControl % "+g", % this._hwnd, % fn
				
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
		joy := StrSplit(arr[2], "Joy")
		if (joy[1] && joy[2]){
			this._IsJoystick := 1
		} else {
			this._IsJoystick := 0
		}
		this.HotkeyString := arr[2]
		this._HotkeySet()
	}
	
	; Change hotkey only and LEAVE modes
	_HotkeySet(){
		this.HumanReadable := this._BuildHumanReadable(this.HotkeyString)
		this._value := this.ModeString this.HotkeyString
		this._UpdateGuiControl()
		; Fire the OnChange callback
		this._callback.(this)

	}
	
	; ============== HOTKEY MANAGEMENT ============
	; An option was selected in the drop-down list
	OptionSelected(){
		GuiControlGet, option,, % this._hwnd
		GuiControl, Choose, % this._hwnd, 0
		if (option = 1){
			; Bind Mode
			;ToolTip Bind MODE
			this._BindMode()
			
		} else if (option = 2){
			;ToolTip Wild Option Changed
			this.Wild := !this.Wild
			this.ModeString := this._BuildModes()
			this._HotkeySet()
		} else if (option = 3){
			;ToolTip PassThrough Option Changed
			this.PassThrough := !this.PassThrough
			this.ModeString := this._BuildModes()
			this._HotkeySet()
		} else if (option = 4){
			;ToolTip Remove Binding
			this.Value := ""
		}
	}
	
	; Bind mode was enabled
	_BindMode(){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		static modifier_symbols := {91: "#", 92: "#", 160: "+", 161: "+", 162: "^", 163: "^", 164: "!", 165: "!"}
		;static modifier_lr_variants := {91: "<", 92: ">", 160: "<", 161: ">", 162: "<", 163: ">", 164: "<", 165: ">"}

		this._BindModeState := 1
		this._SelectedInput := []
		this._ModifiersUsed := []
		this._NonModifierCount := 0
		this._LastInput := {}
		
		Gui, new, hwndhPrompt -Border +AlwaysOnTop
		Gui, % hPrompt ":Add", Text, w300 h100 Center, BIND MODE`n`nPress the desired key combination.`n`nBinding ends when you release a key.`nPress Esc to exit.
		Gui,  % hPrompt ":Show"
		
		; Activate hooks
		; ToDo: why does JHook not fire if hotkeys declared after hooks declared?
		fn := this._ProcessJHook.Bind(this)
		; Activate joystick hotkeys
		Loop % 8 {
			joystr := A_Index "Joy"
			Loop % 32 {
				hotkey, % joystr A_Index, % fn
				hotkey, % joystr A_Index, On
			}
		}

		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback(this._ProcessKHook,"Fast",,&this)) ; fn)
		this._hHookMouse := this._SetWindowsHookEx(WH_MOUSE_LL, RegisterCallback(this._ProcessMHook,"Fast",,&this)) ; fn)
		
		; Wait for Bind Mode to end
		Loop {
			if (this._BindModeState = 0){
				break
			}
			Sleep 10
		}
		
		; Bind mode ended, remove hooks
		this._UnhookWindowsHookEx(this._hHookKeybd)
		this._UnhookWindowsHookEx(this._hHookMouse)
		hotkey, IfWinActive
		Loop % 8 {
			joystr := A_Index "Joy"
			Loop % 32 {
				hotkey, % joystr A_Index, Off
			}
		}
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
				; Convert keyboard modifiers from like LCtrl to ^ - do not do for last char as that is the "End Key"
				hotkey_string .= modifier_symbols[this._SelectedInput[A_Index].vk]
			} else {
				hotkey_string .= this._SelectedInput[A_Index].name
			}
		}
		
		; trigger __Set meta-func to configure control
		this.Value := hotkey_string
	}
	
	; Builds mode string from this.Wild and this.Passthrough
	_BuildModes(){
		str := ""
		if (this.Wild){
			str .= "*"
		}
		if (this.PassThrough){
			str .= "~"
		}
		return str
	}
	; Converts an AHK hotkey string (eg "^+a"), plus the state of WILD and PASSTHROUGH properties to Human Readable format (eg "(WP) CTRL+SHIFT+A")
	_BuildHumanReadable(hotkey_string){
		static modifier_names := {"+": "Shift", "^": "Ctrl", "!": "Alt", "#": "Win"}
		
		dbg := "TRANSLATING: " hotkey_string " : "
		
		if (hotkey_string = ""){
			return "(Select to Bind)"
		}
		
		JoyInfo := StrSplit(hotkey_string, "Joy")
		if (JoyInfo[1] != "" && JoyInfo[2] != ""){
			return "Joy " JoyInfo[1] " Btn " JoyInfo[2]
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
		static EM_SETCUEBANNER:=0x1501
		DllCall("User32.dll\SendMessageW", "Ptr", this._hEdit, "Uint", EM_SETCUEBANNER, "Ptr", True, "WStr", modes this.HumanReadable)
	}
	
	; ============= HOOK HANDLING =================
	_SetWindowsHookEx(idHook, pfn){
		Return DllCall("SetWindowsHookEx", "Ptr", idHook, "Ptr", pfn, "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr")
	}
	
	_UnhookWindowsHookEx(idHook){
		Return DllCall("UnhookWindowsHookEx", "Ptr", idHook)
	}
	
	; Process Keyboard messages from Hooks
	_ProcessKHook(wParam, lParam){
		; KBDLLHOOKSTRUCT structure: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644967%28v=vs.85%29.aspx
		; KeyboardProc function: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644984(v=vs.85).aspx
		
		; ToDo:
		; Use Repeat count, transition state bits from lParam to filter keys
		
		static WM_KEYDOWN := 0x100, WM_KEYUP := 0x101, WM_SYSKEYDOWN := 0x104
		
		Critical
		
		if (this<0){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		
		vk := NumGet(lParam+0, "UInt")
		Extended := NumGet(lParam+0, 8, "UInt") & 1
		sc := (Extended<<8)|NumGet(lParam+0, 4, "UInt")
		sc := sc = 0x136 ? 0x36 : sc
        key:=GetKeyName(Format("vk{1:x}sc{2:x}", vk,sc))
        
		event := wParam = WM_SYSKEYDOWN || wParam = WM_KEYDOWN
		
		;OutputDebug % "Processing Key Hook... " key " | event: " event " | WP: " wParam
	
		modifier := (vk >= 160 && vk <= 165) || (vk >= 91 && vk <= 93)
		obj := {Type: "k", name: key , vk : vk, event: event, modifier: modifier}
			
		; Filter repeated down events
		if (event) {
			if (this._InputCompare(obj, this._LastInput)){
				return 1
			}
			
			this._LastInput := obj
		}



		;OutputDebug, % "Key VK: " vk ", event: " event ", name: " GetKeyName(Format("vk{:x}", vk)) ", modifier: " modifier
		
		this._ProcessInput(obj)
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
		static button_map := {0x0201: 1, 0x0202: 1 , 0x0204: 2, 0x0205: 2, 0x0207: 3, x0208: 3}
		static button_event := {0x0201: 1, 0x0202: 0 , 0x0204: 1, 0x0205: 0, 0x0207: 1, x0208: 0}
		Critical
		if (this<0 || wParam = 0x200){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookMouse, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		out := "Mouse: " wParam " "
		
		keyname := ""
		event := 0
		button := 0
		
		if (IsObject(this._MouseLookup[wParam])){
			; L / R / M  buttons
			keyname := this._MouseLookup[wParam].name
			;event := 1
			button := button_map[wParam]
			event := button_event[wParam]
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
						keyname .= "Up"
						button := 6
					} else {
						keyname .= "Down"
						button := 7
					}
				} else {
					keyname .= "Wheel"
					if (mouseData < 1){
						keyname .= "Left"
						button := 8
					} else {
						keyname .= "Right"
						button := 9
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
				button := 3 + mouseData
			}
		}
		
		;OutputDebug % "Mouse: " keyname ", event: " event
		this._ProcessInput({Type: "m", button: button, name: keyname, event: event})
		if (wParam = WM_MOUSEHWHEEL || wParam = WM_MOUSEWHEEL){
			; Mouse wheel does not generate up event, simulate it.
			this._ProcessInput({Type: "m", button: button, name: keyname, event: 0})
		}
		return 1
	}

	_ProcessJHook(){
		this._ProcessInput({Type: "j", name: A_ThisHotkey, event: 1})
	}
	
	; All input (keyboard, mouse, joystick) should flow through here when in Bind Mode
	_ProcessInput(obj){
		;{Type: "k", name: keyname, code : keycode, event: event, modifier: modifier}
		;{Type: "m", name: keyname, event: event}
		; Do not process key if bind mode has been exited.
		; Prevents users from being able to hit multiple keys together and exceeding valid length
		static modifier_variants := {91: 92, 92: 91, 160: 161, 161: 160, 162: 163, 163: 162, 164: 165, 165: 164}
		
		if (!this._BindModeState){
			return
		}
		
		JoyUsed := 0
		modifier := 0
		out := "PROCESSINPUT: "
		if (obj.Type = "k"){
			out .= "key = " obj.name ", code: " obj.vk
			if (obj.vk == 27){
				;Escape
				this._BindModeState := 0
				return
			}
			modifier := obj.modifier
			; RALT sends CTRL, ALT continuously when held - ignore down events for already held modifiers
			Loop % this._ModifiersUsed.length(){
				if (obj.event = 1 && obj.vk = this._ModifiersUsed[A_Index]){
					;OutputDebug % "IGNORING : " obj.vk
					return
				}
				;OutputDebug % "ALLOWING : " obj.vk " - " this._ModifiersUsed.length()
			}
			this._ModifiersUsed.push(obj.vk)
			; Push l/r variant to used list
			this._ModifiersUsed.push(modifier_variants[obj.vk])
		} else if (obj.Type = "m"){
			out .= "mouse = " obj.name
		} else if (obj.Type = "j"){
			if (this._SelectedInput.length()){
				; joystick buttons can only be bound without other keys or modifiers
				SoundBeep, 500, 200
				return
			}
			this._BindModeState := 0
		}
		
		; Detect if Bind Mode should end
		;OutputDebug % out
		if (obj.event = 0){
			; key / button up
			if (!modifier){
				this._NonModifierCount--
			}
			if (this._InputCompare(obj, this._SelectedInput[this._SelectedInput.length()])){
				this._BindModeState := 0
			}
		} else {
			; key / button down
			if (!modifier){
				if (this._NonModifierCount){
					SoundBeep, 500, 200
					return
				}
				this._NonModifierCount++
			}
			this._SelectedInput.push(obj)
			; End if not modifier
			;if (!modifier){
			;	this._BindModeState := 0
			;}
		}
	}
	
	; Compares two Input objects (that came from hooks)
	_InputCompare(obj1, obj2){
		if (obj1.Type = obj2.Type){
			if (obj1.Type = "k"){
				if (obj1.vk = obj2.vk && obj1.sc = obj2.sc){
					return 1
				}
			} else if (obj1.Type = "m"){
				return obj1.button = obj2.button
			} else if (obj1.Type = "j"){
				
			}
		}
		return 0
	}
}