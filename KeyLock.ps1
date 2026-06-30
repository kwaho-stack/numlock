# KeyLock.ps1
# Backup helper: forces NumLock = ON and CapsLock = OFF, and (until the Scancode Map
# takes effect after reboot) blocks the NumLock/CapsLock keys with a low-level hook.
# Runs quietly in the background until terminated.

$ErrorActionPreference = 'Stop'

$src = @'
using System;
using System.Runtime.InteropServices;

public static class KeyLock
{
    const int  WH_KEYBOARD_LL = 13;
    const int  WM_KEYDOWN     = 0x0100;
    const int  WM_SYSKEYDOWN  = 0x0104;
    const int  VK_CAPITAL     = 0x14;   // CapsLock
    const int  VK_NUMLOCK     = 0x90;   // NumLock
    const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    const uint KEYEVENTF_KEYUP       = 0x0002;

    delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    // Keep the callback/hook handle alive so the GC does not collect them.
    static readonly LowLevelKeyboardProc _proc = HookCallback;
    static IntPtr _hookID = IntPtr.Zero;

    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetModuleHandle(string lpModuleName);
    [DllImport("user32.dll")]
    static extern short GetKeyState(int nVirtKey);
    [DllImport("user32.dll")]
    static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode; public uint scanCode; public uint flags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int pt_x; public int pt_y; }
    [DllImport("user32.dll")]
    static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint min, uint max);

    static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = wParam.ToInt32();
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                KBDLLHOOKSTRUCT kb = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                if (kb.vkCode == VK_CAPITAL || kb.vkCode == VK_NUMLOCK)
                {
                    // Swallow the keystroke so the toggle never happens -> state stays fixed.
                    return (IntPtr)1;
                }
            }
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    static void Press(byte vk)
    {
        keybd_event(vk, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
        keybd_event(vk, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    // Make NumLock = ON, CapsLock = OFF (call this before installing the hook).
    public static void EnforceState()
    {
        if ((GetKeyState(VK_NUMLOCK) & 1) == 0) Press((byte)VK_NUMLOCK); // turn on if off
        if ((GetKeyState(VK_CAPITAL) & 1) == 1) Press((byte)VK_CAPITAL); // turn off if on
    }

    public static void Run()
    {
        EnforceState();
        _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
        MSG m;
        // A global low-level hook needs a message pump; this loop keeps the process alive.
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
        UnhookWindowsHookEx(_hookID);
    }
}
'@

Add-Type -TypeDefinition $src -Language CSharp
[KeyLock]::Run()
