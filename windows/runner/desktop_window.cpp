#include "desktop_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include "resource.h"

namespace {

// The tray icon tells the window about clicks with this message.
constexpr UINT kTrayMessage = WM_APP + 0x50;
constexpr UINT kTrayId = 1;

enum MenuItem : UINT {
  kPlayPause = 1,
  kNext,
  kPrevious,
  kShow,
  kQuit,
};

// Where the window's place is kept between runs.
constexpr wchar_t kKey[] = L"Software\\Encore";
constexpr wchar_t kPlacement[] = L"WindowPlacement";

// Explorer was restarted (or crashed): every tray icon has to be added
// again.
UINT TaskbarCreated() {
  static UINT message = RegisterWindowMessageW(L"TaskbarCreated");
  return message;
}

// Sent by a second Encore to the running one. Named after this exe, so a
// build being tested doesn't hand over to the installed app.
std::wstring ExeName() {
  wchar_t path[MAX_PATH];
  DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring name(path, length);
  for (auto& c : name) {
    if (c == L'\\' || c == L':') c = L'_';
  }
  return name;
}

UINT ShowMessage() {
  static UINT message = RegisterWindowMessageW((L"Encore.Show." + ExeName()).c_str());
  return message;
}

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return L"";
  int length = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), length);
  return wide;
}

}  // namespace

DesktopWindow::DesktopWindow(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "dev.encore.app/window",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "title") {
      if (auto* title = std::get_if<std::string>(call.arguments())) {
        auto wide = Wide(*title);
        SetWindowTextW(window_, wide.c_str());
        SetTip(wide);
      }
    } else if (call.method_name() == "closeToTray") {
      if (auto* on = std::get_if<bool>(call.arguments())) close_to_tray_ = *on;
    }
    result->Success();
  });
  AddIcon();
}

DesktopWindow::~DesktopWindow() {
  if (icon_added_) {
    NOTIFYICONDATAW data{sizeof(data)};
    data.hWnd = window_;
    data.uID = kTrayId;
    Shell_NotifyIconW(NIM_DELETE, &data);
  }
}

void DesktopWindow::AddIcon() {
  NOTIFYICONDATAW data{sizeof(data)};
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  wcsncpy_s(data.szTip, tip_.c_str(), _TRUNCATE);
  icon_added_ = Shell_NotifyIconW(NIM_ADD, &data);
  if (icon_added_) {
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
  if (data.hIcon) DestroyIcon(data.hIcon);
}

void DesktopWindow::SetTip(const std::wstring& tip) {
  tip_ = tip;
  if (!icon_added_) return;
  NOTIFYICONDATAW data{sizeof(data)};
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_TIP | NIF_SHOWTIP;
  wcsncpy_s(data.szTip, tip_.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void DesktopWindow::ShowWindowAgain() {
  if (IsIconic(window_)) {
    ShowWindow(window_, SW_RESTORE);
  } else {
    ShowWindow(window_, SW_SHOW);
  }
  SetForegroundWindow(window_);
}

void DesktopWindow::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kPlayPause, L"Play / pause");
  AppendMenuW(menu, MF_STRING, kNext, L"Next");
  AppendMenuW(menu, MF_STRING, kPrevious, L"Previous");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kShow, L"Show Encore");
  AppendMenuW(menu, MF_STRING, kQuit, L"Quit");
  SetMenuDefaultItem(menu, kShow, FALSE);
  POINT at;
  GetCursorPos(&at);
  // Without this the menu stays open after clicking elsewhere.
  SetForegroundWindow(window_);
  UINT chosen = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON |
                                         TPM_BOTTOMALIGN,
                               at.x, at.y, 0, window_, nullptr);
  DestroyMenu(menu);
  switch (chosen) {
    case kPlayPause:
      Send("playPause");
      break;
    case kNext:
      Send("next");
      break;
    case kPrevious:
      Send("previous");
      break;
    case kShow:
      ShowWindowAgain();
      break;
    case kQuit:
      SavePlacement();
      DestroyWindow(window_);
      break;
  }
}

void DesktopWindow::Send(const char* command) {
  channel_->InvokeMethod("tray",
                         std::make_unique<flutter::EncodableValue>(command));
}

bool DesktopWindow::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam,
                                  LRESULT* result) {
  *result = 0;
  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case NIN_SELECT:
      case NIN_KEYSELECT:
        ShowWindowAgain();
        break;
      case WM_CONTEXTMENU:
      case WM_RBUTTONUP:
        ShowMenu();
        break;
    }
    return true;
  }
  if (message == ShowMessage()) {
    ShowWindowAgain();
    return true;
  }
  if (message == TaskbarCreated()) {
    AddIcon();
    return true;
  }
  switch (message) {
    case WM_CLOSE:
      SavePlacement();
      if (close_to_tray_ && icon_added_) {
        // Music keeps playing; the tray icon brings the window back.
        ShowWindow(window_, SW_HIDE);
        return true;
      }
      return false;
    case WM_QUERYENDSESSION:
    case WM_ENDSESSION:
      // Windows shutting down, or an installer updating Encore: the
      // place is kept, and the window really closes.
      SavePlacement();
      return false;
  }
  return false;
}

void DesktopWindow::SavePlacement() {
  WINDOWPLACEMENT placement{sizeof(placement)};
  if (!GetWindowPlacement(window_, &placement)) return;
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kKey, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  RegSetValueExW(key, kPlacement, 0, REG_BINARY,
                 reinterpret_cast<const BYTE*>(&placement), sizeof(placement));
  RegCloseKey(key);
}

// static
bool DesktopWindow::RestorePlacement(HWND window) {
  WINDOWPLACEMENT placement{};
  DWORD size = sizeof(placement);
  if (RegGetValueW(HKEY_CURRENT_USER, kKey, kPlacement, RRF_RT_REG_BINARY,
                   nullptr, &placement, &size) != ERROR_SUCCESS ||
      size != sizeof(placement) || placement.length != sizeof(placement)) {
    return false;
  }
  // Only on a screen that is still there (a monitor may be unplugged).
  if (!MonitorFromRect(&placement.rcNormalPosition, MONITOR_DEFAULTTONULL)) {
    return false;
  }
  bool maximized = placement.showCmd == SW_SHOWMAXIMIZED;
  placement.showCmd = SW_HIDE;  // Shown once the first frame is ready.
  placement.flags = 0;
  SetWindowPlacement(window, &placement);
  return maximized;
}

// static
bool DesktopWindow::HandOverToRunningCopy() {
  // Kept for the life of the process: the next Encore sees it.
  static HANDLE mutex =
      CreateMutexW(nullptr, FALSE, (L"Encore.Running." + ExeName()).c_str());
  if (GetLastError() != ERROR_ALREADY_EXISTS) return false;
  // The running one may bring itself to the front (this process has the
  // user's click that started it).
  AllowSetForegroundWindow(ASFW_ANY);
  PostMessageW(HWND_BROADCAST, ShowMessage(), 0, 0);
  return true;
}
