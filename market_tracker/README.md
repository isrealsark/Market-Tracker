# Market Tracker

Market Tracker is a Windows-only Flutter desktop application.

## Run on Windows

Install Flutter and Visual Studio with the **Desktop development with C++** workload, then run these commands from this directory:

```powershell
flutter pub get
flutter run -d windows
```

To create a release build:

```powershell
flutter build windows --release
```

The app intentionally stops at startup on non-Windows platforms. Its local database uses SQLite FFI for Windows.
