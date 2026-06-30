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
    const int  WM_KEYUP       = 0x0101;
    const int  WM_SYSKEYDOWN  = 0x0104;
    const int  WM_SYSKEYUP    = 0x0105;
    const uint WM_TIMER       = 0x0113;
    const int  VK_CAPITAL     = 0x14;   // CapsLock
    const int  VK_NUMLOCK     = 0x90;   // NumLock
    const int  VK_SCROLL      = 0x91;   // ScrollLock
    const int  VK_INSERT      = 0x2D;   // Insert
    const uint LLKHF_EXTENDED = 0x01;
    const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    const uint KEYEVENTF_KEYUP       = 0x0002;

    // Signature we stamp on our own injected presses, so the hook can tell them apart
    // from anyone else's NumLock/CapsLock events (e.g. Logitech Options injecting keys).
    const long SIG = 0x4B4C4F4B; // 'KLOK'

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

    // Map a numpad scan code to its numeric VK. Returns 0 for non-numpad keys.
    static byte NumpadVkFromScan(uint scan)
    {
        switch (scan)
        {
            case 0x47: return 0x67; // 7
            case 0x48: return 0x68; // 8
            case 0x49: return 0x69; // 9
            case 0x4B: return 0x64; // 4
            case 0x4C: return 0x65; // 5
            case 0x4D: return 0x66; // 6
            case 0x4F: return 0x61; // 1
            case 0x50: return 0x62; // 2
            case 0x51: return 0x63; // 3
            case 0x52: return 0x60; // 0
            case 0x53: return 0x6E; // .
            default:   return 0;
        }
    }

    static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = wParam.ToInt32();
            bool down = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
            bool up   = (msg == WM_KEYUP   || msg == WM_SYSKEYUP);
            if (down || up)
            {
                KBDLLHOOKSTRUCT kb = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));

                // Ignore our own injected events (they carry our signature).
                if (kb.dwExtraInfo.ToInt64() != SIG)
                {
                    // (1) Lock: block any NumLock/CapsLock/ScrollLock event that is not
                    //     ours (covers real presses and ones injected by other software).
                    if (kb.vkCode == VK_CAPITAL || kb.vkCode == VK_NUMLOCK || kb.vkCode == VK_SCROLL)
                        return (IntPtr)1;

                    // (1b) Disable the dedicated Insert key (it is extended). The numpad
                    //      "0" key is NOT extended, so it is left alone and still types 0.
                    if (kb.vkCode == VK_INSERT && (kb.flags & LLKHF_EXTENDED) != 0)
                        return (IntPtr)1;

                    // (2) Force the numpad to ALWAYS type digits, regardless of the
                    //     keyboard's own NumLock state (handles firmware-managed NumLock,
                    //     e.g. Lofree). A numpad key arriving as a navigation key has a
                    //     numpad scan code and is NOT extended (the real arrow/nav cluster
                    //     IS extended). Remap it to the matching numpad digit.
                    if ((kb.flags & LLKHF_EXTENDED) == 0)
                    {
                        byte np = NumpadVkFromScan(kb.scanCode);
                        if (np != 0 && kb.vkCode != np)
                        {
                            keybd_event(np, 0, down ? 0u : KEYEVENTF_KEYUP, (UIntPtr)(ulong)SIG);
                            return (IntPtr)1;
                        }
                    }
                }
            }
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    static void Press(byte vk)
    {
        UIntPtr sig = (UIntPtr)(ulong)SIG;
        keybd_event(vk, 0, KEYEVENTF_EXTENDEDKEY, sig);
        keybd_event(vk, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, sig);
    }

    public static void EnforceState()
    {
        if ((GetKeyState(VK_NUMLOCK) & 1) == 0) Press((byte)VK_NUMLOCK); // turn ON if off
        if ((GetKeyState(VK_CAPITAL) & 1) == 1) Press((byte)VK_CAPITAL); // turn OFF if on
        if ((GetKeyState(VK_SCROLL)  & 1) == 1) Press((byte)VK_SCROLL);  // turn OFF if on
    }

    // (Re)install the hook. Install the new one first, then drop the old one, so the
    // keyboard is never left unhooked. Keeps the old hook if a new install fails.
    static void InstallHook()
    {
        IntPtr h = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
        if (h != IntPtr.Zero)
        {
            IntPtr old = _hookID;
            _hookID = h;
            if (old != IntPtr.Zero && old != h) UnhookWindowsHookEx(old);
        }
    }

    static int _tick = 0;

    public static void Run()
    {
        EnforceState();
        InstallHook();
        SetTimer(IntPtr.Zero, (IntPtr)1, 250, IntPtr.Zero); // tick ~4x/sec
        MSG m;
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0)
        {
            if (m.message == WM_TIMER)
            {
                EnforceState();
                // Watchdog: Windows silently removes a low-level hook if any callback ever
                // exceeds LowLevelHooksTimeout (e.g. a GC pause). Re-install periodically so
                // the lock always recovers instead of staying dead.
                if ((++_tick % 8) == 0) InstallHook(); // ~every 2 seconds
            }
        }
        UnhookWindowsHookEx(_hookID);
    }
}
'@

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
"started: $(Get-Date -Format o)`r`nPID: $PID`r`nelevated: $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))" |
    Set-Content -Path (Join-Path $logDir 'started.log')

Add-Type -TypeDefinition $src -Language CSharp

Write-Host '[KeyLock] Hook running. NumLock is locked ON, CapsLock locked OFF.'
Write-Host '[KeyLock] Try pressing NumLock/CapsLock now. Close this window to stop.'
[KeyLock]::Run()

} catch {
    $msg = $_ | Out-String
    Write-Host "[KeyLock] ERROR: $msg" -ForegroundColor Red
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
        $msg | Set-Content -Path (Join-Path $logDir 'error.log')
    } catch {}
    Start-Sleep -Seconds 30
}
