# masko-code Build & Package (macOS 26)

## Build

```zsh
swift build -c release
```

## Assemble .app bundle (SPM does not do this fully)

```zsh
APP=".build/release/Masko Code.app/Contents"
cp -R .build/release/masko-code_masko-code.bundle/Fonts      "$APP/Resources/"
cp -R .build/release/masko-code_masko-code.bundle/Images     "$APP/Resources/"
cp -R .build/release/masko-code_masko-code.bundle/Defaults   "$APP/Resources/"
cp -R .build/release/masko-code_masko-code.bundle/Extensions "$APP/Resources/"
cp -R .build/release/Sparkle.framework "$APP/Frameworks/"
```

## Fix rpath (must run every time the binary is replaced)

```zsh
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "/Applications/Masko Code.app/Contents/MacOS/masko-code"
```

## Sign with entitlements (required for network server on macOS 26)

```zsh
codesign --force --deep --sign - \
  --entitlements Sources/masko-desktop.entitlements \
  "/Applications/Masko Code.app"
```

## Clear Gatekeeper quarantine

```zsh
xattr -cr "/Applications/Masko Code.app"
```

## Install to /Applications

```zsh
cp -R ".build/release/Masko Code.app" /Applications/
```

## Create DMG

Requires Pillow in conda base env (`pip install Pillow`).

```zsh
zsh -c "source ~/.zshrc; conda activate base && bash scripts/create-dmg.sh \
  '.build/release/Masko Code.app' \
  '.build/release/MaskoCode.dmg' \
  'Masko Code' \
  'scripts/dmg-background.py'"
```

## Known macOS 26 issues (already fixed in this fork)

1. **NWListener broken (POSIX 22)** — all `NWListener` TCP configs fail on macOS 26.
   Fixed by replacing with BSD sockets + GCD in `Sources/Services/LocalServer.swift`
   and new `Sources/Services/ClientConnection.swift`.
   `NWConnection` removed from `Sources/Stores/PendingPermissionStore.swift`.

2. **Missing Sparkle rpath** — `swift build` does not add `@executable_path/../Frameworks`
   to the binary. Must patch with `install_name_tool` after every binary replacement.
   Permanent fix: add to `Package.swift` target:
   ```swift
   swiftSettings: [.unsafeFlags(["-Xlinker", "-rpath",
                                  "-Xlinker", "@executable_path/../Frameworks"])]
   ```

3. **Entitlements not embedded** — `masko-desktop.entitlements` is listed under `exclude:`
   in `Package.swift` so SPM never bundles it. Without `com.apple.security.network.server`
   the server silently fails to bind. Always pass `--entitlements` to `codesign`.
