; A script to process all forms of input and generate events any time anything changes.
; Detects keyboard and mouse input using SetWindowsHookEx
; Detects Joystick  input using a combination of button hotkeys and a GetKeyState loop for POV Hat

#SingleInstance force
mc := new MyClass()
return

GuiClose:
	mc.Exit()
	ExitApp

class MyClass{
	__New(){
		fn := this._ProcessInput.Bind(this)
		this.hkhandler := new HkHandler(fn)
		Gui, Add, ListView, w280 h190, Type|Code|Name|Event
		LV_ModifyCol(3, 100)
		Gui, Show, w300 h200 x0 y0
	}
	
	; All Input events should flow through here
	_ProcessInput(obj){
		static mouse_lookup := ["Lbutton", "RButton", "MButton", "XButton1", "XButton2", "WheelU", "WheelD", "WheelL", "WheelR"]
		static pov_directions := ["U", "R", "D", "L"]
		static event_lookup := {0: "Release", 1: "Press"}
		
		if (obj.Type = "m"){
			; Mouse button
			key := mouse_lookup[obj.Code]
		} else if (obj.Type = "k") {
			; Keyboard Key
			key := GetKeyName(Format("sc{:x}", obj.Code))
		} else if (obj.Type = "j") {
			; Joystick button
			key := obj.joyid "Joy" obj.Code
		} else if (obj.Type = "h") {
			; Joystick hat
			key := obj.joyid "JoyPOV" pov_directions[obj.Code]
		}
		
		LV_Add(,obj.Type, obj.code, key, event_lookup[obj.event])
		
		; Do not block input
		return 0
	}

	; Gui Closed
	Exit(){
		this.hkhandler.Exit()
	}
}

; The hotkey handler class
class HkHandler {
	#MaxThreadsPerHotkey 1000
	__New(callback){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		; Lookup table to accelerate finding which mouse button was pressed

		this._Callback := callback
		
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
				}
				; Watch POVs
				if (instr(joyinfo, "p")){
					this._JoysticksWithHats.push(joyid)
				}
			}
		}
		fn := this._WatchJoystickPOV.Bind(this)
		SetTimer, % fn, 10
	}
	
	Exit(){
		; remove hooks
		this._UnhookWindowsHookEx(this._hHookKeybd)
		this._UnhookWindowsHookEx(this._hHookMouse)
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
		; Repeat filtering not working perfectly. Hold CTRL, then A, then release CTRL - A repeats.
		
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

