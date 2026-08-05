#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <strsafe.h>

/*
 * Windows 11 replacement for the four WonderLink exports imported by
 * Compton's 3D World Atlas Deluxe v3.2. The original 1998 DLL depended on
 * writable HKCR preferences, IE/Netscape DDE, and a service discontinued in
 * 2001. This shim never contacts the retired HTTP endpoints. It opens only
 * allowlisted HTTPS Wayback snapshots through a modern Windows browser.
 */

static int ascii_lower(int value)
{
    if (value >= 'A' && value <= 'Z') return value + ('a' - 'A');
    return value;
}

static int contains_ascii_ci(const char *text, const char *needle)
{
    const char *start;
    const char *left;
    const char *right;

    if (!text || !needle || !*needle) return 0;
    for (start = text; *start; ++start) {
        left = start;
        right = needle;
        while (*left && *right && ascii_lower((unsigned char)*left) == ascii_lower((unsigned char)*right)) {
            ++left;
            ++right;
        }
        if (!*right) return 1;
    }
    return 0;
}

static int open_target(const WCHAR *target)
{
    HINSTANCE result;

    result = ShellExecuteW(NULL, L"open", target, NULL, NULL, SW_SHOWNORMAL);
    if ((INT_PTR)result > 32) return 0;
    if ((INT_PTR)result == SE_ERR_OOM) return -3;
    return -4;
}

static int open_local_archive(const WCHAR *relative_path)
{
    WCHAR local_app_data[2048];
    WCHAR archive_root[4096];
    WCHAR target[4096];
    DWORD length;
    HRESULT format_result;

    length = GetEnvironmentVariableW(
        L"ATLAS_ARCHIVE_ROOT",
        archive_root,
        (DWORD)(sizeof(archive_root) / sizeof(archive_root[0]))
    );
    if (length == 0 || length >= (DWORD)(sizeof(archive_root) / sizeof(archive_root[0]))) {
        length = GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data,
            (DWORD)(sizeof(local_app_data) / sizeof(local_app_data[0])));
        if (length == 0 || length >= (DWORD)(sizeof(local_app_data) / sizeof(local_app_data[0]))) {
            return -4;
        }
        format_result = StringCchPrintfW(
            archive_root,
            sizeof(archive_root) / sizeof(archive_root[0]),
            L"%s\\Comptons 3D World Atlas Deluxe\\Online Archive",
            local_app_data
        );
        if (FAILED(format_result)) return -4;
    }

    format_result = StringCchPrintfW(
        target,
        sizeof(target) / sizeof(target[0]),
        L"%s\\Mirror\\%s",
        archive_root,
        relative_path
    );
    if (FAILED(format_result)) return -4;
    return open_target(target);
}

__declspec(dllexport) void __cdecl WLSetProductName(const char *product_name)
{
    (void)product_name;
}

__declspec(dllexport) int __cdecl WLGetMaxURLStrlen(void)
{
    return 256;
}

__declspec(dllexport) int __cdecl WLShowPrefs(HWND owner)
{
    MessageBoxW(
        owner,
        L"The original Compton's 3D World Atlas Online service was discontinued in 2001.\n\n"
        L"Windows 11 Archive Mode is enabled. Online commands now open read-only pages copied locally from preserved Internet Archive snapshots. The retired context-sensitive CGI is replaced by the archived site map.\n\n"
        L"No AOL software, Internet Explorer, legacy DDE connection, password, or obsolete plug-in is used.",
        L"Compton's 3D World Atlas Online - Archive Mode",
        MB_OK | MB_ICONINFORMATION
    );
    return 1;
}

__declspec(dllexport) int __cdecl WLBrowserLaunch(const char *requested_url)
{
    if (contains_ascii_ci(requested_url, "page=downloads")) {
        return open_local_archive(L"3datlas\\download\\f_main_dl.html");
    }
    if (contains_ascii_ci(requested_url, "page=atlashome")) {
        return open_local_archive(L"3datlas\\index.html");
    }
    if (contains_ascii_ci(requested_url, "comptons.com")) {
        return open_local_archive(L"comptons\\index.html");
    }

    /* The context-sensitive atlas.cgi responses were not preserved. */
    return open_local_archive(L"3datlas\\sitemap.html");
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
