# KeyLock.ps1
# 넘버락(NumLock)은 항상 켜진 상태, 캡스락(CapsLock)은 항상 꺼진 상태로 고정합니다.
# 저단계 키보드 후크(WH_KEYBOARD_LL)로 두 키의 입력 자체를 막아 상태가 바뀌지 않게 합니다.
# 백그라운드에서 조용히 동작하며, 종료 전까지 계속 살아 있습니다.

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

    // 콜백/후크 핸들은 GC가 수거하지 않도록 static 으로 보관
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
                    // 키 입력을 삼켜서 토글 자체가 일어나지 않게 한다 -> 상태 고정
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

    // NumLock=ON, CapsLock=OFF 가 되도록 한 번 맞춰준다 (후크 설치 전에 호출해야 함)
    public static void EnforceState()
    {
        if ((GetKeyState(VK_NUMLOCK) & 1) == 0) Press((byte)VK_NUMLOCK); // 꺼져 있으면 켠다
        if ((GetKeyState(VK_CAPITAL) & 1) == 1) Press((byte)VK_CAPITAL); // 켜져 있으면 끈다
    }

    public static void Run()
    {
        EnforceState();
        _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
        MSG m;
        // 전역 저단계 후크는 메시지 펌프가 필요하므로 이 루프가 프로세스를 살려둔다
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
        UnhookWindowsHookEx(_hookID);
    }
}
'@

Add-Type -TypeDefinition $src -Language CSharp
[KeyLock]::Run()
