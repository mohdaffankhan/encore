#ifndef RUNNER_DESKTOP_WINDOW_H_
#define RUNNER_DESKTOP_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// What makes Encore behave like a desktop music player, with Windows' own
// APIs (no extra libraries):
//  - the window title shows the song ("Get Lucky – Daft Punk");
//  - the window opens where it was left, at the size it was (or maximized);
//  - a tray icon: closing the window keeps the music playing there; click
//    it to bring Encore back, right-click for play/pause, next, previous
//    and quit;
//  - one Encore at a time: opening it again shows the one already running.
// The app talks to it over the "dev.encore.app/window" channel.
class DesktopWindow {
 public:
  DesktopWindow(HWND window, flutter::BinaryMessenger* messenger);
  ~DesktopWindow();

  // Before the window first shows: back where it was. Returns whether it
  // was maximized, to show it so.
  static bool RestorePlacement(HWND window);

  // Handles the tray's and the window's own messages; true if handled
  // (|result| is then the answer to give Windows).
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam,
                     LRESULT* result);

  // Another Encore was started: it asks this one to show instead. Returns
  // false when this is the first, which should carry on starting.
  static bool HandOverToRunningCopy();

 private:
  void ShowWindowAgain();
  void ShowMenu();
  void AddIcon();
  void SetTip(const std::wstring& tip);
  void SavePlacement();
  void Send(const char* command);

  HWND window_;
  bool close_to_tray_ = true;
  bool icon_added_ = false;
  std::wstring tip_ = L"Encore";
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_WINDOW_H_
