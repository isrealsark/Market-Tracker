#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
// Method channel and taskbar overlay support
#include <shobjidl.h>
#include <gdiplus.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Expose a MethodChannel to allow Dart to request a badge update.
  auto messenger = flutter_controller_->engine()->messenger();
  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, "market_tracker/badge",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("setBadge") == 0) {
          // Accept either an integer count or a string path to an .ico file.
          if (call.arguments() && !call.arguments()->IsNull()) {
            if (std::holds_alternative<int32_t>(*call.arguments())) {
              int count = std::get<int32_t>(*call.arguments());
              SetBadge(count);
              result->Success();
              return;
            }
            if (std::holds_alternative<std::string>(*call.arguments())) {
              std::string path = std::get<std::string>(*call.arguments());
              // Convert to wide string for Win32 API.
              std::wstring wpath(path.begin(), path.end());
              HICON custom_icon = nullptr;
              // If it's an .ico file, LoadImage can be used; otherwise try GDI+
              // to load PNG/JPEG and convert to an HICON.
              if (wpath.size() >= 4 &&
                  (wpath.substr(wpath.size() - 4) == L".ico" ||
                   wpath.substr(wpath.size() - 4) == L".ICO")) {
                custom_icon = reinterpret_cast<HICON>(
                    LoadImageW(nullptr, wpath.c_str(), IMAGE_ICON, 0, 0,
                               LR_LOADFROMFILE | LR_DEFAULTSIZE));
              } else {
                Gdiplus::Bitmap* bitmap = Gdiplus::Bitmap::FromFile(wpath.c_str());
                if (bitmap && bitmap->GetLastStatus() == Gdiplus::Ok) {
                  if (bitmap->GetHICON(&custom_icon) != Gdiplus::Ok) {
                    custom_icon = nullptr;
                  }
                }
                delete bitmap;
              }
              ITaskbarList3* taskbar = nullptr;
              if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                             CLSCTX_INPROC_SERVER,
                                             IID_PPV_ARGS(&taskbar)))) {
                taskbar->HrInit();
                taskbar->SetOverlayIcon(GetHandle(), custom_icon,
                                        L"badge");
                taskbar->Release();
              }
              if (custom_icon) DestroyIcon(custom_icon);
              result->Success();
              return;
            }
          }
          // No valid argument provided: clear the badge.
          SetBadge(0);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetBadge(int count) {
  if (!GetHandle()) {
    return;
  }

  HICON icon = nullptr;
  if (count > 0) {
    // Use a simple standard system icon as the overlay to indicate a badge.
    icon = LoadIcon(nullptr, IDI_APPLICATION);
  }

  ITaskbarList3* taskbar = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&taskbar)))) {
    taskbar->HrInit();
    taskbar->SetOverlayIcon(GetHandle(), icon, count > 0 ? L"badge" : nullptr);
    taskbar->Release();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
