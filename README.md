# MobileHouseArrest Bridge (`mha-cli`)

A toolchain and client-server bridge exploiting the **MobileHouseArrest** vulnerability on iOS to provide arbitrary container sandbox escape, application enumeration, and interactive remote filesystem management from a PC.

---

## Architecture Overview

* **iOS Companion Daemon (`MobileHouseArrestBridge`):**
  * Operates on iOS with `CFBundleIdentifier` / `CodeDirectory` identity set to `com.apple.mobile.MobileHouseArrest`.
  * Communicates directly with `containermanagerd` via `/usr/lib/system/libsystem_containermanager.dylib`.
  * Dynamically consumes sandbox extensions (`sandbox_extension_consume`) for requested Application Containers (`Class 2`), App Groups (`Class 7`), and System Groups (`Class 13`).
  * Uses `LSApplicationWorkspace` (LaunchServices) to discover all installed system and user applications and their storage paths.
  * Runs a multi-threaded TCP daemon on port `8080`.

* **PC Client (`client.py` / `mha-cli`):**
  * A CLI client written in Python (zero external dependencies).
  * Connects over USB port-forwarding (`iproxy 8080 8080`).
  * Provides command-line subcommands with formatted table output, filtering, and JSON export.

---

## Quick Start

### 1. Build and Install iOS Daemon
Download the prebuilt `MobileHouseArrestBridge.ipa` from the [GitHub Actions Releases / Artifacts](https://github.com/vcvkk/MobileHouseArrestBridge/actions) and install it on your device using TrollStore, AltStore, or Sideloadly.

Or build manually via Xcode / Theos:
```bash
make
```

### 2. Forward USB Port
With your iOS device connected over USB, establish a tunnel using `iproxy` (part of `libimobiledevice` / `usbmuxd`):
```bash
iproxy 8080 8080
```

### 3. Launch App and Use CLI

#### Check Daemon Connectivity
```bash
python3 client.py ping
```

#### Enumerate Installed Applications & Containers
```bash
# List all applications with their container sandbox status
python3 client.py apps list

# List user-installed apps only
python3 client.py apps list --user-only

# Search by name or bundle identifier
python3 client.py apps list --filter telegram

# Export application list to JSON
python3 client.py apps list --json > apps.json
```

#### Activate & Escape Sandbox for Target Container
```bash
# Activate App Data container (Class 2)
python3 client.py container activate -c 2 com.apple.mobilenotes

# Activate App Group container (Class 7)
python3 client.py container activate -c 7 -g group.com.apple.notes

# Activate System Group (Class 13) - MobileGestalt Cache
python3 client.py container activate -c 13 systemgroup.com.apple.mobilegestaltcache
```

#### Remote Filesystem Management
```bash
# Detailed directory listing
python3 client.py fs ls /private/var/mobile/Containers/Data/Application/<UUID>/ -l

# View file content directly in terminal
python3 client.py fs cat /private/var/mobile/Containers/Data/Application/<UUID>/Library/Preferences/com.app.plist

# Pull/download file from iOS device
python3 client.py fs pull /private/var/mobile/Containers/Data/Application/<UUID>/Documents/database.sqlite ./database.sqlite

# Push/upload modified file to iOS device
python3 client.py fs push ./modified.sqlite /private/var/mobile/Containers/Data/Application/<UUID>/Documents/database.sqlite
```
