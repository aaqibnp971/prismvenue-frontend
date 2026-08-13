# Packaging Prism Venues for Windows

Windows has no single-file equivalent of an APK. `flutter build windows` emits a
**folder** — an exe plus the Flutter runtime DLLs plus `data/` — and all of it
has to travel together. So "an installable file" means one of two shapes, and
both are produced from the same staged bundle:

| shape | what the user gets | needs |
|---|---|---|
| `dist/PrismVenues-windows-x64.zip` | extract, double-click `Install.cmd` | nothing |
| `dist/PrismVenuesSetup.exe` | one file, familiar wizard | Inno Setup 6 on the build machine |

The ZIP is the default and is fully self-sufficient — `Install.ps1` does real
per-user installation (shortcuts, Add/Remove Programs entry, upgrade in place).
The Inno route exists only when handing over a single file matters.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\build_windows_release.ps1
```

Flags: `-ApiBaseUrl <url>` to point at a different backend, `-NoEngine` to ship
without audio, `-SkipBuild` to repackage the existing `build\windows` output.

Then, optionally:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" packaging\PrismVenues.iss
```

## Two things that make a bundle look broken

**`PRISM_API_BASE_URL` is compile-time.** `lib/app/env.dart` reads it through
`const String.fromEnvironment`, so it is fixed when the exe is built — there is
no config file beside the exe to edit afterwards. A build made without the
`--dart-define` silently points at `http://localhost:8000/v1` and every request
fails with no clue why. Changing backend means rebuilding.

**`prism_core.dll` is copied by `windows/CMakeLists.txt`, for every
configuration.** `PrismCore.defaultLibrary()` calls
`DynamicLibrary.open('prism_core.dll')`, which resolves next to the executable.
Miss it and the app runs perfectly and the room stays silent — the engine seam
swallows the load failure into `EngineStatus.failed` on purpose, because a venue
dashboard must keep working when audio does not.

This script's own copy step predates that and is now belt-and-braces: it stages
the same DLL from `../prism-core/build/shared-win/core/Release/`, and `-NoEngine`
still produces a dashboard-only bundle. Note the CMake lookup runs at
**configure** time, so after building the engine for the first time you need a
`flutter clean` (or `-DPRISM_CORE_DLL=<path>`) before it is picked up.

`flutter run -d windows` in **debug** used to be the sharp edge here — the DLL
lived in the Release runner directory only, because this script was the one
thing that put it anywhere, and a debug run never invokes this script. That is
fixed at the CMake level rather than by asking people to remember a copy.
`PRISM_CORE_LIB=<path>` still overrides the lookup at runtime.

## Not signed

Both shapes trip SmartScreen on first run. Removing that needs an Authenticode
certificate from a CA and `signtool.exe` over `prism_venues.exe` and the
installer — a purchase, not a build flag. `README.txt` tells the user to click
through it.
