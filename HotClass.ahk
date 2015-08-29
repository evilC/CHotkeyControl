; Proof of concept for replacement for HotClass
OutputDebug, DBGVIEWCLEAR
;============================================================================================================
; Example user script
;============================================================================================================
#SingleInstance force
mc := new MyClass()
return

GuiClose:
	ExitApp

class MyClass {
	__New(){
		this.HotClass := new HotClass()
		this.HotClass.AddHotkey("hk1")
		Gui, Show, x0 y0
	}
}

;============================================================================================================
; Libraries
;============================================================================================================

;------------------------------------------------------------------------------------------------------------
; Class that manages ALL hotkeys for the script
;------------------------------------------------------------------------------------------------------------
class HotClass{
	#MaxThreadsPerHotkey 256	; required for joystick input as (8 * 32) hotkeys are declared to watch for button down events.
	
	; Constructor
	; startactive param decides 
	__New(options := 0){
		this.STATES := {IDLE: 0, ACTIVE: 1, BIND: 2}		; State Name constants, for human readibility
		
		; Set default options
		if (!IsObject(options) || options == 0){
			options := {StartActive: 1}
		}
		
		; Initialize the Library that detects input.
		this.CInputDetector := new CInputDetector(this._ProcessInput.Bind(this))

		; Initialize state
		if (options.StartActive){
			this.ChangeState(this.STATES.ACTIVE)
		} else {
			this.ChangeState(this.STATES.IDLE)
		}
		
	}
	
	; Handles all state transitions
	; Returns 1 if we transitioned to the specified state, 0 if not
	ChangeState(state, args*){
		if (state == this._State){
			return 1
		}
		if (!ObjHasKey(this, "_State")){
			; Initialize state
			this._State := this.STATES.IDLE			; Set state to IDLE
		}
		
		; Decide what to do, based upon state we wish to transition to
		if (state == this.STATES.IDLE){
			; Go idle / initialize, no args required
			this.CInputDetector.DisableHooks()
			this._State := state
			this._BindName := ""					; The name of the hotkey that is being bound
			this._Hotkeys := {}						; a name indexed array of hotkey objects
			this._HeldKeys := {}					; The list of keys that are currently held
			this._BindList := {}					; In Bind mode, the keys that are currently held
		} else if (state == this.STATES.ACTIVE ){
			; Enter ACTIVE state, no args required
			if (this._State == this.STATES.BIND){
				; Transition from BIND state - binding data will be in this._BindList etc.
			}
			; ToDo: Build ordered list of bound hotkeys
			this.CInputDetector.EnableHooks()
			this._HeldKeys := {}
			this._State := state
			return 1
		} else if (state == this.STATES.BIND ){
			; Enter BIND state.
			; args[1] = name of hotkey requesting state change
			this.CInputDetector.EnableHooks()
			if (args.length()){
				this._State := state
				this._BindName := args[1]
				this._BindList := []
				return 1
			}
		}
		; Default to Fail
		return 0
	}

	; All Input Events flow through here - ie an input device changes state
	; Encompasses keyboard keys, mouse buttons / wheel and joystick buttons or hat directions
	_ProcessInput(keyevent){
		if (this._State == this.STATES.BIND){
			; Bind mode - block all input and build up a list of held keys
			if (keyevent.event = 1){
				; Down event - add pressed key to list of held keys
				this._BindList.push(keyevent)
			} else {
				; Up event in bind mode - state change from bind mode to normal mode
				this.ChangeState(this.STATES.ACTIVE)
				
				;ToDo: Check if hotkey is duplicate, and if so, reject.
				
				; set state of hotkey class
				this._Hotkeys[this._BindName].SetBinding(this._BindList)
				
				; Build Bind List for fast matching in normal mode
			}
			return 1 ; block input
		} else if (this._State == this.STATES.ACTIVE){
			; ACTIVE state - aka "Normal Operation". Trigger hotkey callbacks as appropriate
			; As each key goes down, add it to the list of held keys
			; Then check the bound hotkeys (longest to shortest) to check if there is a match
			
			if (keyevent.event = 1){
				; down event
				this._HeldKeys.push(keyevent)	; add key to list of held keys
				
				; Check list of bound hotkeys for matches.
				; List must be indexed LONGEST (most keys in combination) to SHORTEST (least keys in combination) to ensure correct behavior
				; ie if CTRL+A and A are both bound, pressing CTRL+A should match CTRL+A before A.
			} else {
				; up event
				; Remove key from list of held keys
			}
		}
		; Default to not blocking input
		return 0 ; don't block input
	}

	; User command to add a new hotkey
	AddHotkey(name){
		; ToDo: Ensure unique name
		this._Hotkeys[name] := new this._Hotkey(this, name)
	}
	
	; Each hotkey is an instance of this class.
	; Handles the Gui control and routing of callbacks when the hotkey triggers
	class _Hotkey {
		__New(handler, name){
			this._handler := handler
			this.name := name
			this.BindList := {}
			
			Gui, Add, Edit, hwndhwnd w200 Disabled
			this.hEdit := hwnd
			Gui, Add, Button, hwndhwnd xp+210, Bind
			this.hBind := hwnd
			fn := this._handler.ChangeState.Bind(handler, this._handler.STATES.BIND, name)
			GuiControl +g, % hwnd, % fn
		}
		
		SetBinding(BindList){
			this.BindList := BindList
			GuiControl,, % this.hEdit, % this.BuildHumanReadable(BindList)
		}
		
		BuildHumanReadable(BindList){
			static mouse_lookup := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "WheelU", "WheelD", "WheelL", "WheelR"]
			static pov_directions := ["U", "R", "D", "L"]
			static event_lookup := {0: "Release", 1: "Press"}
			
			out := ""
			Loop % BindList.length(){
				if (A_Index > 1){
					out .= " + "
				}
				obj := BindList[A_Index]
				if (obj.Type = "m"){
					; Mouse button
					key := mouse_lookup[obj.Code]
				} else if (obj.Type = "k") {
					; Keyboard Key
					key := GetKeyName(Format("sc{:x}", obj.Code))
					if (StrLen(key) = 1){
						StringUpper, key, key
					}
				} else if (obj.Type = "j") {
					; Joystick button
					key := obj.joyid "Joy" obj.Code
				} else if (obj.Type = "h") {
					; Joystick hat
					key := obj.joyid "JoyPOV" pov_directions[obj.Code]
				}
				out .= key
			}
			return out
		}
	}
}

;------------------------------------------------------------------------------------------------------------
; Sets up the hooks etc to watch for input
;------------------------------------------------------------------------------------------------------------
class CInputDetector {
	__New(callback){
		this._HooksEnabled := 0
		this._Callback := callback
		
		this.EnableHooks()
	}
	
	EnableHooks(){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		
		if (this._HooksEnabled){
			return 1
		}
		
		this._HooksEnabled := 1

		; Hook Input
		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback(this._ProcessKHook,"Fast",,&this))
		this._hHookMouse := this._SetWindowsHookEx(WH_MOUSE_LL, RegisterCallback(this._ProcessMHook,"Fast",,&this))
		
		this._JoysticksWithHats := []
		Loop 8 {
			joyid := A_Index
			joyinfo := GetKeyState(joyid "JoyInfo")
			if (joyinfo){
				; watch buttons
				Loop % 32 {
					fn := this._ProcessJHook.Bind(this, joyid, A_Index)
					hotkey, % joyid "Joy" A_Index, % fn
					hotkey, % joyid "Joy" A_Index, On
				}
				; Watch POVs
				if (instr(joyinfo, "p")){
					this._JoysticksWithHats.push(joyid)
				}
			}
		}
		fn := this._WatchJoystickPOV.Bind(this)
		SetTimer, % fn, 10
		return 1
	}
	
	DisableHooks(){
		if (!this._HooksEnabled){
			return 1
		}
		
		this._HooksEnabled := 0

		this._UnhookWindowsHookEx(this._hHookKeybd)
		this._UnhookWindowsHookEx(this._hHookMouse)

		this._JoysticksWithHats := []
		Loop 8 {
			joyid := A_Index
			joyinfo := GetKeyState(joyid "JoyInfo")
			if (joyinfo){
				; stop watching buttons
				Loop % 32 {
					hotkey, % joyid "Joy" A_Index, Off
				}
			}
		}
		fn := this._WatchJoystickPOV.Bind(this)
		SetTimer, % fn, Off
		return 1
	}
	
	; Process Joystick button down events
	_ProcessJHook(joyid, btn){
		;ToolTip % "Joy " joyid " Btn " btn
		this._Callback.({Type: "j", Code: btn, joyid: joyid, event: 1})
		fn := this._WaitForJoyUp.Bind(this, joyid, btn)
		SetTimer, % fn, -0
	}
	
	; Emulate up events for joystick buttons
	_WaitForJoyUp(joyid, btn){
		str := joyid "Joy" btn
		while (GetKeyState(str)){
			sleep 10
		}
		this._Callback.({Type: "j", Code: btn, joyid: joyid, event: 0})
	}
	
	; A constantly running timer to emulate "button events" for Joystick POV directions (eg 2JoyPOVU, 2JoyPOVD...)
	_WatchJoystickPOV(){
		static pov_states := [-1, -1, -1, -1, -1, -1, -1, -1]
		static pov_strings := ["1JoyPOV", "2JoyPOV", "3JoyPOV", "4JoyPOV", "5JoyPOV", "6JoyPOV" ,"7JoyPOV" ,"8JoyPOV"]
		static pov_direction_map := [[0,0,0,0], [1,0,0,0], [1,1,0,0] , [0,1,0,0], [0,1,1,0], [0,0,1,0], [0,0,1,1], [0,0,0,1], [1,0,0,1]]
		static pov_direction_states := [[0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0]]
		Loop % this._JoysticksWithHats.length() {
			joyid := this._JoysticksWithHats[A_Index]
			pov := GetKeyState(pov_strings[joyid])
			if (pov = pov_states[joyid]){
				; do not process stick if nothing changed
				continue
			}
			if (pov = -1){
				state := 1
			} else {
				state := round(pov / 4500) + 2
			}
			
			Loop 4 {
				if (pov_direction_states[joyid, A_Index] != pov_direction_map[state, A_Index]){
					this._Callback.({Type: "h", Code: A_Index, joyid: joyid, event: pov_direction_map[state, A_Index]})
				}
			}
			pov_states[joyid] := pov
			pov_direction_states[joyid] := pov_direction_map[state]
		}
	}
	
	; Process Keyboard Hook messages
	_ProcessKHook(wParam, lParam){
		; KBDLLHOOKSTRUCT structure: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644967%28v=vs.85%29.aspx
		; KeyboardProc function: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644984(v=vs.85).aspx
		
		; ToDo:
		; Use Repeat count, transition state bits from lParam to filter keys
		
		static WM_KEYDOWN := 0x100, WM_KEYUP := 0x101, WM_SYSKEYDOWN := 0x104
		static last_sc := 0
		static last_event := 0
		
		Critical
		
		if (this<0){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		
		vk := NumGet(lParam+0, "UInt")
		Extended := NumGet(lParam+0, 8, "UInt") & 1
		sc := (Extended<<8)|NumGet(lParam+0, 4, "UInt")
		sc := sc = 0x136 ? 0x36 : sc
        ;key:=GetKeyName(Format("vk{1:x}sc{2:x}", vk,sc))
		event := wParam = WM_SYSKEYDOWN || wParam = WM_KEYDOWN
		
        if ( ! (sc = 541 || (last_event = event && last_sc = sc) ) ){		; ignore non L/R Control. This key never happens except eg with RALT
			block := this._Callback.({ Type: "k", Code: sc, event: event})
			last_sc := sc
			last_event := event
			if (block){
				return 1
			}
		}
		Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)

	}
	
	; Process Mouse Hook messages
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
		static button_map := {0x0201: 1, 0x0202: 1 , 0x0204: 2, 0x0205: 2, 0x0207: 3, 0x208: 3}
		static button_event := {0x0201: 1, 0x0202: 0 , 0x0204: 1, 0x0205: 0, 0x0207: 1, 0x208: 0}
		Critical
		if (this<0 || wParam = 0x200){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookMouse, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		out := "Mouse: " wParam " "
		
		keyname := ""
		event := 0
		button := 0
		
		;if (IsObject(this._MouseLookup[wParam])){
		if (ObjHasKey(button_map, wParam)){
			; L / R / M  buttons
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
					if (mouseData > 1){
						button := 6
					} else {
						button := 7
					}
				} else {
					if (mouseData < 1){
						button := 8
					} else {
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
				button := 3 + mouseData
			}
		}

		;OutputDebug % "Mouse: " keyname ", event: " event
		block := this._Callback.({Type: "m", Code: button, event: event})
		if (wParam = WM_MOUSEHWHEEL || wParam = WM_MOUSEWHEEL){
			; Mouse wheel does not generate up event, simulate it.
			this._Callback.({Type: "m", Code: button, event: 0})
		}
		if (block){
			return 1
		}
		Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookMouse, "int", this, "Uint", wParam, "Uint", lParam)
	}
	
	; ============= HOOK HANDLING =================
	_SetWindowsHookEx(idHook, pfn){
		Return DllCall("SetWindowsHookEx", "Ptr", idHook, "Ptr", pfn, "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr")
	}
	
	_UnhookWindowsHookEx(idHook){
		Return DllCall("UnhookWindowsHookEx", "Ptr", idHook)
	}

}