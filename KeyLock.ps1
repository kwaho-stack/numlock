# KeyLock.ps1
# Keeps NumLock = ON and CapsLock = OFF and blocks the physical NumLock/CapsLock keys.
# A low-level keyboard hook swallows real NumLock/CapsLock key presses (so they cannot
# toggle), while letting our own injected presses through so we can still set the state.
# A periodic timer re-asserts NumLock = ON in case some app bypasses the hook.
# Runs quietly in the background until terminated. Errors are logged to error.log.

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:LOCALAPPDATA 'KeyLock'

try {

$src = @'
using System;
using System.Runtime.InteropServices;

public static class KeyLock
{
    const int  WH_KEYBOARD_LL = 13;
    const int  WM_KEYDOWN     = 0x0100;
    const int  WM_SYSKEYDOWN  = 0x0104;
    const uint WM_TIMER       = 0x0113;
    const int  VK_CAPITAL     = 0x14;   // CapsLock
    const int  VK_NUMLOCK     = 0x90;   // NumLock
    const uint LLKHF_INJECTED = 0x10;
    const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    const uint KEYEVENTF_KEYUP       = 0x0002;

    delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    static readonly LowLevelKeyboardProc _proc = HookCallback;  // keep alive (no GC)
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
    [DllImport("user32.dll")]
    static extern IntPtr SetTimer(IntPtr hWnd, IntPtr nIDEvent, uint uElapse, IntPtr lpTimerFunc);

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
                    // Block only real (non-injected) presses, so our own keybd_event still works.
                    if ((kb.flags & LLKHF_INJECTED) == 0)
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

    public static void EnforceState()
    {
        if ((GetKeyState(VK_NUMLOCK) & 1) == 0) Press((byte)VK_NUMLOCK); // turn ON if off
        if ((GetKeyState(VK_CAPITAL) & 1) == 1) Press((byte)VK_CAPITAL); // turn OFF if on
    }

    public static void Run()
    {
        EnforceState();
        _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
        SetTimer(IntPtr.Zero, (IntPtr)1, 250, IntPtr.Zero); // re-assert state ~4x/sec
        MSG m;
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0)
        {
            if (m.message == WM_TIMER) EnforceState();
        }
        UnhookWindowsHookEx(_hookID);
    }
}
'@

Add-Type -TypeDefinition $src -Language CSharp
[KeyLock]::Run()

} catch {
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
        $_ | Out-String | Set-Content -Path (Join-Path $logDir 'error.log')
    } catch {}
}
