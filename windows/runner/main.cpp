#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance check using a named mutex.
  // If another instance is already running, bring it to foreground and exit.
  HANDLE hMutex = ::CreateMutexW(nullptr, FALSE, L"GaboothAssistant_SingleInstance");
  if (hMutex == nullptr || ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is running - find its window and bring to foreground.
    // The window may be hidden in the tray, so force-show it as well.
    HWND existingWindow = ::FindWindowW(nullptr, L"Gabooth Assistant");
    if (existingWindow != nullptr) {
      if (::IsIconic(existingWindow)) {
        ::ShowWindow(existingWindow, SW_RESTORE);
      } else {
        ::ShowWindow(existingWindow, SW_SHOW);
      }
      ::SetForegroundWindow(existingWindow);
    }
    if (hMutex != nullptr) {
      ::CloseHandle(hMutex);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

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
  if (!window.Create(L"Gabooth Assistant", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::ReleaseMutex(hMutex);
  ::CloseHandle(hMutex);
  return EXIT_SUCCESS;
}
