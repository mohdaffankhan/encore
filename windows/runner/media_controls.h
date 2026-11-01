#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Windows' own media controls for Encore (System Media Transport Controls):
// the media overlay that the volume and media keys bring up, the lock
// screen, and the hardware media keys (Windows sends them to the app that is
// playing, focused or not). The app sends what is playing over the
// "dev.encore.app/media_controls" channel and gets the buttons back.
class MediaControls {
 public:
  MediaControls(HWND window, flutter::BinaryMessenger* messenger);
  ~MediaControls();

  // A message of ours, posted to the window from Windows' own threads, so
  // the app is told on the main thread (the only one Flutter allows).
  static constexpr UINT kButtonMessage = WM_APP + 0x4e;
  static constexpr UINT kSeekMessage = WM_APP + 0x4f;

  // Handles kButtonMessage / kSeekMessage; true if it was one.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct State;
  std::unique_ptr<State> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
