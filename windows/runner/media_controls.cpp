#include "media_controls.h"

#include <flutter/standard_method_codec.h>
#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <string>

namespace {

using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;

const char* ButtonName(SystemMediaTransportControlsButton button) {
  switch (button) {
    case SystemMediaTransportControlsButton::Play:
      return "play";
    case SystemMediaTransportControlsButton::Pause:
      return "pause";
    case SystemMediaTransportControlsButton::Next:
      return "next";
    case SystemMediaTransportControlsButton::Previous:
      return "previous";
    default:
      return nullptr;
  }
}

std::string String(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return "";
  if (auto* value = std::get_if<std::string>(&it->second)) return *value;
  return "";
}

int64_t Millis(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (auto* value = std::get_if<int64_t>(&it->second)) return *value;
  return 0;
}

bool Bool(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return false;
  if (auto* value = std::get_if<bool>(&it->second)) return *value;
  return false;
}

winrt::Windows::Foundation::TimeSpan Span(int64_t millis) {
  return std::chrono::duration_cast<winrt::Windows::Foundation::TimeSpan>(
      std::chrono::milliseconds(millis));
}

}  // namespace

struct MediaControls::State {
  HWND window;
  SystemMediaTransportControls smtc{nullptr};
  winrt::event_token button_token;
  winrt::event_token seek_token;
  int64_t duration = 0;  // The song's length, in milliseconds.
};

MediaControls::MediaControls(HWND window, flutter::BinaryMessenger* messenger)
    : state_(std::make_unique<State>()) {
  state_->window = window;
  try {
    // The controls belong to this window (how a desktop app gets them).
    auto interop = winrt::get_activation_factory<SystemMediaTransportControls,
                                                 ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(state_->smtc)));
    auto& smtc = state_->smtc;
    smtc.IsPlayEnabled(true);
    smtc.IsPauseEnabled(true);
    smtc.IsNextEnabled(true);
    smtc.IsPreviousEnabled(true);
    smtc.IsEnabled(false);  // Until something plays.
    // These come on Windows' own threads: hand them to the main thread.
    state_->button_token = smtc.ButtonPressed([window](auto&&, auto&& args) {
      PostMessage(window, kButtonMessage,
                  static_cast<WPARAM>(args.Button()), 0);
    });
    state_->seek_token =
        smtc.PlaybackPositionChangeRequested([window](auto&&, auto&& args) {
          auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(
                            args.RequestedPlaybackPosition())
                            .count();
          PostMessage(window, kSeekMessage, 0, static_cast<LPARAM>(millis));
        });
  } catch (const winrt::hresult_error&) {
    // No media controls on this Windows: the app still plays.
    state_->smtc = nullptr;
  }

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "dev.encore.app/media_controls",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    auto& smtc = state_->smtc;
    auto& length = state_->duration;
    if (!smtc) {
      result->Success();
      return;
    }
    try {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (call.method_name() == "item" && args) {
        // A new song: what it is, and how long.
        auto updater = smtc.DisplayUpdater();
        updater.Type(MediaPlaybackType::Music);
        auto music = updater.MusicProperties();
        music.Title(winrt::to_hstring(String(*args, "title")));
        music.Artist(winrt::to_hstring(String(*args, "artist")));
        music.AlbumTitle(winrt::to_hstring(String(*args, "album")));
        auto art = String(*args, "artUrl");
        // Fetched by Windows when shown, so this doesn't wait for it.
        updater.Thumbnail(
            art.empty()
                ? nullptr
                : winrt::Windows::Storage::Streams::RandomAccessStreamReference::
                      CreateFromUri(winrt::Windows::Foundation::Uri(
                          winrt::to_hstring(art))));
        updater.Update();
        length = Millis(*args, "duration");
        smtc.IsEnabled(true);
      } else if (call.method_name() == "state" && args) {
        // Playing or paused, and where: on play / pause and seeks.
        SystemMediaTransportControlsTimelineProperties timeline;
        timeline.StartTime(Span(0));
        timeline.MinSeekTime(Span(0));
        timeline.Position(Span(Millis(*args, "position")));
        timeline.EndTime(Span(length));
        timeline.MaxSeekTime(Span(length));
        smtc.UpdateTimelineProperties(timeline);
        smtc.PlaybackStatus(Bool(*args, "playing")
                                ? MediaPlaybackStatus::Playing
                                : MediaPlaybackStatus::Paused);
      } else if (call.method_name() == "clear") {
        smtc.DisplayUpdater().ClearAll();
        smtc.DisplayUpdater().Update();
        smtc.PlaybackStatus(MediaPlaybackStatus::Closed);
        smtc.IsEnabled(false);
      }
      result->Success();
    } catch (const winrt::hresult_error& e) {
      result->Error("media_controls", winrt::to_string(e.message()));
    }
  });
}

MediaControls::~MediaControls() {
  if (state_->smtc) {
    state_->smtc.ButtonPressed(state_->button_token);
    state_->smtc.PlaybackPositionChangeRequested(state_->seek_token);
  }
}

bool MediaControls::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kButtonMessage) {
    if (auto* name = ButtonName(
            static_cast<SystemMediaTransportControlsButton>(wparam))) {
      channel_->InvokeMethod("button",
                             std::make_unique<flutter::EncodableValue>(name));
    }
    return true;
  }
  if (message == kSeekMessage) {
    channel_->InvokeMethod("seek", std::make_unique<flutter::EncodableValue>(
                                       static_cast<int64_t>(lparam)));
    return true;
  }
  return false;
}
