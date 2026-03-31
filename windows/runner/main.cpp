#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include <iostream>
#include <string>

// Register the custom URI scheme in the Windows Registry
void RegisterProtocol(const std::wstring& scheme) {
    WCHAR path[MAX_PATH];
    GetModuleFileNameW(NULL, path, MAX_PATH);
    std::wstring command(path);
    command = L"\"" + command + L"\" \"%1\"";

    HKEY hKey;
    std::wstring keyPath = L"Software\\Classes\\" + scheme;
    
    if (RegCreateKeyExW(HKEY_CURRENT_USER, keyPath.c_str(), 0, NULL, 
        REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        
        const wchar_t* protocolDesc = L"URL:magiccrm Protocol";
        RegSetValueExW(hKey, NULL, 0, REG_SZ, (BYTE*)protocolDesc, (DWORD)((wcslen(protocolDesc) + 1) * sizeof(WCHAR)));
        RegSetValueExW(hKey, L"URL Protocol", 0, REG_SZ, (BYTE*)L"", sizeof(WCHAR));
        
        HKEY hCommandKey;
        std::wstring commandKeyPath = keyPath + L"\\shell\\open\\command";
        if (RegCreateKeyExW(HKEY_CURRENT_USER, commandKeyPath.c_str(), 0, NULL, 
            REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, NULL, &hCommandKey, NULL) == ERROR_SUCCESS) {
            RegSetValueExW(hCommandKey, NULL, 0, REG_SZ, (BYTE*)command.c_str(), (DWORD)((command.length() + 1) * sizeof(WCHAR)));
            RegCloseKey(hCommandKey);
        }
        RegCloseKey(hKey);
    }
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Register deep link protocol
  RegisterProtocol(L"magiccrm");

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"magic_music_crm", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
