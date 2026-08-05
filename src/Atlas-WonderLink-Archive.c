#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <strsafe.h>

/*
 * Windows 11 replacement for the four WonderLink exports imported by
 * Compton's 3D World Atlas Deluxe v3.2. The original 1998 DLL depended on
 * writable HKCR preferences, IE/Netscape DDE, and a service discontinued in
 * 2001. This shim never contacts the retired HTTP endpoints. It opens only
 * local files under the archive mirror; entry-specific requests are rendered
 * as local context pages carrying the original request data.
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

static void trace_request(const char *requested_url)
{
    char trace_path[2048];
    char line[4096];
    DWORD path_length;
    DWORD line_length;
    DWORD written;
    HANDLE file;

    path_length = GetEnvironmentVariableA(
        "ATLAS_WONDERLINK_TRACE",
        trace_path,
        (DWORD)sizeof(trace_path)
    );
    if (path_length == 0 || path_length >= (DWORD)sizeof(trace_path)) return;

    if (!requested_url) requested_url = "(null)";
    if (FAILED(StringCchPrintfA(
        line,
        sizeof(line),
        "WLBrowserLaunch: %s\r\n",
        requested_url
    ))) return;
    line_length = (DWORD)lstrlenA(line);

    file = CreateFileA(
        trace_path,
        FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );
    if (file == INVALID_HANDLE_VALUE) return;
    (void)WriteFile(file, line, line_length, &written, NULL);
    CloseHandle(file);
}

static int open_target(const WCHAR *target)
{
    HINSTANCE result;

    result = ShellExecuteW(NULL, L"open", target, NULL, NULL, SW_SHOWNORMAL);
    if ((INT_PTR)result > 32) return 0;
    if ((INT_PTR)result == SE_ERR_OOM) return -3;
    return -4;
}

static int get_archive_root(WCHAR *archive_root, size_t archive_root_cch)
{
    WCHAR local_app_data[2048];
    DWORD length;
    HRESULT format_result;

    length = GetEnvironmentVariableW(
        L"ATLAS_ARCHIVE_ROOT",
        archive_root,
        (DWORD)archive_root_cch
    );
    if (length > 0 && length < (DWORD)archive_root_cch) return 0;

    length = GetEnvironmentVariableW(
        L"LOCALAPPDATA",
        local_app_data,
        (DWORD)(sizeof(local_app_data) / sizeof(local_app_data[0]))
    );
    if (length == 0 || length >= (DWORD)(sizeof(local_app_data) / sizeof(local_app_data[0]))) {
        return -4;
    }

    format_result = StringCchPrintfW(
        archive_root,
        archive_root_cch,
        L"%s\\Comptons 3D World Atlas Deluxe\\Online Archive",
        local_app_data
    );
    return FAILED(format_result) ? -4 : 0;
}

static HRESULT append_text(WCHAR *target, size_t target_cch, size_t *used, const WCHAR *text)
{
    HRESULT result;
    size_t text_length;

    if (*used >= target_cch) return STRSAFE_E_INSUFFICIENT_BUFFER;
    text_length = lstrlenW(text);
    if (text_length >= target_cch - *used) return STRSAFE_E_INSUFFICIENT_BUFFER;
    result = StringCchCopyW(target + *used, target_cch - *used, text);
    if (SUCCEEDED(result)) *used += text_length;
    return result;
}

static HRESULT build_file_uri(
    WCHAR *target,
    size_t target_cch,
    const WCHAR *path,
    const char *query
)
{
    const WCHAR *cursor;
    WCHAR query_w[2048];
    WCHAR one[2];
    size_t used = 0;
    int query_length;
    HRESULT result;

    result = append_text(target, target_cch, &used, L"file:///");
    if (FAILED(result)) return result;

    for (cursor = path; *cursor; ++cursor) {
        if (*cursor == L'\\') {
            result = append_text(target, target_cch, &used, L"/");
        } else if (*cursor == L' ') {
            result = append_text(target, target_cch, &used, L"%20");
        } else if (*cursor == L'#') {
            result = append_text(target, target_cch, &used, L"%23");
        } else {
            one[0] = *cursor;
            one[1] = L'\0';
            result = append_text(target, target_cch, &used, one);
        }
        if (FAILED(result)) return result;
    }

    if (query && *query) {
        query_length = MultiByteToWideChar(
            CP_ACP,
            0,
            query,
            -1,
            query_w,
            (int)(sizeof(query_w) / sizeof(query_w[0]))
        );
        if (query_length == 0) return STRSAFE_E_INVALID_PARAMETER;
        result = append_text(target, target_cch, &used, L"#");
        if (FAILED(result)) return result;
        result = append_text(target, target_cch, &used, query_w);
        if (FAILED(result)) return result;
    }
    return S_OK;
}

static int open_local_archive(const WCHAR *relative_path)
{
    WCHAR archive_root[4096];
    WCHAR target[4096];
    HRESULT format_result;

    if (get_archive_root(archive_root, sizeof(archive_root) / sizeof(archive_root[0]))) {
        return -4;
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

static int hex_value(char value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

static void copy_context_name(const char *requested_url, char *name, size_t name_cch)
{
    const char *value = NULL;
    const char *cursor;
    size_t used = 0;

    if (requested_url) {
        value = strstr(requested_url, "pn=");
        if (value) {
            value += 3;
        } else {
            value = strstr(requested_url, "h=");
            if (value) value += 2;
        }
    }
    if (!value || !*value) value = "Atlas entry";

    for (cursor = value; *cursor && *cursor != '&' && *cursor != '#' && used + 1 < name_cch; ++cursor) {
        int high;
        int low;
        if (*cursor == '%' && cursor[1] && cursor[2] &&
            (high = hex_value(cursor[1])) >= 0 && (low = hex_value(cursor[2])) >= 0) {
            name[used++] = (char)((high << 4) | low);
            cursor += 2;
        } else if (*cursor == '+' || *cursor == '_') {
            name[used++] = ' ';
        } else {
            name[used++] = *cursor;
        }
    }
    name[used] = '\0';
    if (!used) StringCchCopyA(name, name_cch, "Atlas entry");
}

static int html_escape(const char *source, char *target, size_t target_cch)
{
    const char *cursor;
    size_t used = 0;
    const char *replacement;
    size_t replacement_length;

    for (cursor = source ? source : ""; *cursor; ++cursor) {
        switch (*cursor) {
            case '&': replacement = "&amp;"; break;
            case '<': replacement = "&lt;"; break;
            case '>': replacement = "&gt;"; break;
            case '"': replacement = "&quot;"; break;
            case 39: replacement = "&#39;"; break;
            default:
                if (used + 1 >= target_cch) return -1;
                target[used++] = *cursor;
                continue;
        }
        replacement_length = lstrlenA(replacement);
        if (used + replacement_length >= target_cch) return -1;
        CopyMemory(target + used, replacement, replacement_length);
        used += replacement_length;
    }
    if (target_cch == 0) return -1;
    target[used] = '\0';
    return 0;
}

static const char *country_page_for_name(const char *name)
{
    if (contains_ascii_ci(name, "new york") || contains_ascii_ci(name, "washington") ||
        contains_ascii_ci(name, "los angeles") || contains_ascii_ci(name, "united states")) {
        return "countries/co_usa.html";
    }
    if (contains_ascii_ci(name, "london") || contains_ascii_ci(name, "england")) {
        return "countries/co_england.html";
    }
    if (contains_ascii_ci(name, "paris") || contains_ascii_ci(name, "france")) {
        return "countries/co_france.html";
    }
    if (contains_ascii_ci(name, "berlin") || contains_ascii_ci(name, "germany")) {
        return "countries/co_germany.html";
    }
    if (contains_ascii_ci(name, "tokyo") || contains_ascii_ci(name, "japan")) {
        return "countries/co_japan.html";
    }
    if (contains_ascii_ci(name, "sydney") || contains_ascii_ci(name, "australia")) {
        return "countries/co_australia.html";
    }
    return "sitemap.html";
}

static int write_context_page(const WCHAR *path, const char *requested_url)
{
    char name[512];
    char escaped_name[1536];
    char escaped_url[4096];
    const char *country_page;
    char html[8192];
    HANDLE file;
    DWORD written;
    HRESULT format_result;

    copy_context_name(requested_url, name, sizeof(name));
    country_page = country_page_for_name(name);
    if (html_escape(name, escaped_name, sizeof(escaped_name)) ||
        html_escape(requested_url ? requested_url : "(null)", escaped_url, sizeof(escaped_url))) {
        return -4;
    }
    format_result = StringCchPrintfA(
        html,
        sizeof(html),
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>%s - Atlas Online Local Archive</title>"
        "<style>body{font:16px Segoe UI,Arial,sans-serif;max-width:900px;margin:40px auto;padding:0 24px;color:#eaf7ff;background:#071d48}"
        "h1{color:#64d8ff}h2{color:#ff9d35}.card{display:block;margin:12px 0;padding:14px;color:#eaf7ff;background:#0c2c59;border:1px solid #4094c2;border-radius:8px;text-decoration:none}"
        "pre{white-space:pre-wrap;color:#b9efff}</style></head><body><h1>%s — Online Links</h1>"
        "<p>This is a local, read-only replacement for the retired context-sensitive Atlas Online service.</p>"
        "<h2>Captured Atlas request</h2><pre>%s</pre>"
        "<h2>Preserved local material</h2>"
        "<a class=\"card\" href=\"%s\">Country and regional reference pages</a>"
        "<a class=\"card\" href=\"atlas/atlas.html\">3D Atlas pages and city screenshots</a>"
        "<a class=\"card\" href=\"topics/top_geo.html\">Geography topics</a>"
        "<a class=\"card\" href=\"sitemap.html\">Complete local archive site map</a>"
        "<p>The original dynamic CGI response was not preserved for every entry. No live URL or Wayback URL is opened.</p></body></html>",
        escaped_name,
        escaped_name,
        escaped_url,
        country_page
    );
    if (FAILED(format_result)) return -4;

    file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return -4;
    if (!WriteFile(file, html, (DWORD)lstrlenA(html), &written, NULL)) {
        CloseHandle(file);
        return -4;
    }
    CloseHandle(file);
    return 0;
}

static int open_local_context(const char *requested_url)
{
    static LONG sequence;
    WCHAR archive_root[4096];
    WCHAR path[8192];
    LONG current_sequence;
    HRESULT format_result;

    if (!requested_url || !strchr(requested_url, '?')) {
        return open_local_archive(L"3datlas\\sitemap.html");
    }
    if (get_archive_root(archive_root, sizeof(archive_root) / sizeof(archive_root[0]))) {
        return -4;
    }
    current_sequence = InterlockedIncrement(&sequence);
    format_result = StringCchPrintfW(
        path,
        sizeof(path) / sizeof(path[0]),
        L"%s\\Mirror\\3datlas\\entry-links-%lu-%ld.html",
        archive_root,
        GetTickCount(),
        current_sequence
    );
    if (FAILED(format_result)) return -4;
    if (write_context_page(path, requested_url)) return -4;
    return open_target(path);
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
        L"Windows 11 Archive Mode is enabled. Top-level pages and entry-specific requests now open read-only files copied or generated locally from preserved Internet Archive material.\n\n"
        L"No AOL software, Internet Explorer, legacy DDE connection, password, or obsolete plug-in is used.",
        L"Compton's 3D World Atlas Online - Archive Mode",
        MB_OK | MB_ICONINFORMATION
    );
    return 1;
}

__declspec(dllexport) int __cdecl WLBrowserLaunch(const char *requested_url)
{
    trace_request(requested_url);
    if (contains_ascii_ci(requested_url, "page=downloads")) {
        return open_local_archive(L"3datlas\\download\\f_main_dl.html");
    }
    if (contains_ascii_ci(requested_url, "page=atlashome")) {
        return open_local_archive(L"3datlas\\index.html");
    }
    if (contains_ascii_ci(requested_url, "comptons.com")) {
        return open_local_archive(L"comptons\\index.html");
    }

    if (contains_ascii_ci(requested_url, "atlas.cgi?") &&
        (contains_ascii_ci(requested_url, "p=") ||
         contains_ascii_ci(requested_url, "id=") ||
         contains_ascii_ci(requested_url, "pn="))) {
        return open_local_context(requested_url);
    }

    /* Unknown requests stay local and open the preserved site map. */
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
