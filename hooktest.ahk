; A script to decode the results from SetWindowsHookEx
#SingleInstance force
ht := new HookTest()
return

GuiClose:
ExitApp

class HookTest {
	__New(){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		; Lookup table to accelerate finding which mouse button was pressed
		this._MouseLookup := {}
		this._MouseLookup[0x201] := { name: "LButton", event: 1 }
		this._MouseLookup[0x202] := { name: "LButton", event: 0 }
		this._MouseLookup[0x204] := { name: "RButton", event: 1 }
		this._MouseLookup[0x205] := { name: "RButton", event: 0 }
		this._MouseLookup[0x207] := { name: "MButton", event: 1 }
		this._MouseLookup[0x208] := { name: "MButton", event: 0 }

		Gui, Add, ListView, hwndhwnd w280 h190, Code|Name|Event
		LV_ModifyCol(2, 100)
		this._hLV := hwnd
		Gui, Show, w300 h200 x0 y0
		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback(this._ProcessKHook,"Fast",,&this))
		this._hHookMouse := this._SetWindowsHookEx(WH_MOUSE_LL, RegisterCallback(this._ProcessMHook,"Fast",,&this))
		
		;this._UnhookWindowsHookEx(this._hHookKeybd)
		;this._UnhookWindowsHookEx(this._hHookMouse)

	}

	_ProcessInput(obj){
		LV_Add(,obj.code, obj.name, obj.event)
	}
	
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
		key := GetKeyName(Format("sc{:x}", sc))
		event := wParam = WM_SYSKEYDOWN || wParam = WM_KEYDOWN
		
        if ( ! (sc = 541 || (last_event = event && last_sc = sc) ) ){		; ignore non L/R Control. This key never happens except eg with RALT
			this._ProcessInput({ Type: "k", Code: sc, event: event, name: key })
			last_sc := sc
			last_event := event
			
		}
		Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)
	}
	
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
		this._ProcessInput({Type: "m", Code: button, name: keyname, event: event})
		if (wParam = WM_MOUSEHWHEEL || wParam = WM_MOUSEWHEEL){
			; Mouse wheel does not generate up event, simulate it.
			this._ProcessInput({Type: "m", Code: button, name: keyname, event: 0})
		}
		;return 1
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

