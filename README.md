# CHotkeyControl

## What?
A `Hotkey` GuiControl for AutoHotkey.

## Why?
Because the default AHK `Hotkey` GuiControl does not support many things, eg mouse input.

## How?
The code makes use of `SetWindowsHookEx` DLL calls to hook the keyboard and mouse.

## About
CHotkeyControl is a Class for AHK scripts that you can instantiate, which creates a GuiControl that can be used to select input (keyboard, mouse, joystick etc) that AHK supports (eg to pass to the `hotkey()` command).  
It consists of one ListBox - the current binding appears as the selected item, and the user can drop down the list to select various binding options such as Rebind, Toggle Wild Mode / Passthrough etc.

## Planned Features
* Able to recognize any input that AHK could declare a hotkey for.
Keyboard, mouse and joystick or any valid combination thereof.
* Fires a callback whenever the user changes the binding.
* Human readable hotkey description (eg `CTRL + ALT + LBUTTON`)
* Supports Wild (*), PassThrough (~) etc.
* Getter and Setters
The `value` property of the class will hold the current AHK hotkey string (eg `^!LButton`)  
Setting value will change the hotkey

**Note that CHotkeyControl does NOT actually bind hotkeys, It just replicates the functionality of the AHK Hotkey GuiControl**
