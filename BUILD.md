# Building

All commands run from the repository root. These are the exact steps used to
produce `builds/marble-run-debug.apk` on Manjaro Linux (Godot 4.7.2, OpenJDK 27,
Android build-tools 36.1.0). Nothing needs root.

## 1. Godot export templates (4.7.2)

```sh
mkdir -p /tmp/godot-tpl && cd /tmp/godot-tpl
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/SHA512-SUMS.txt
grep "Godot_v4.7.2-stable_export_templates.tpz" SHA512-SUMS.txt | sha512sum -c
T=~/.local/share/godot/export_templates/4.7.2.stable
mkdir -p "$T"
unzip -q -o Godot_v4.7.2-stable_export_templates.tpz 'templates/android*' 'templates/linux_*x86_64*' 'templates/version.txt'
cp templates/* "$T"/
cat "$T"/version.txt            # -> 4.7.2.stable
```

(Alternatively: Godot editor → Editor → Manage Export Templates → Download.)

## 2. Android SDK (command-line tools only, no Android Studio)

```sh
SDK=~/Android/Sdk
mkdir -p $SDK/cmdline-tools /tmp/sdk && cd /tmp/sdk
curl -LO https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
echo "e025545c62a8e64c7559119566a569fb1dec5f60  commandlinetools-linux-16111833_latest.zip" | sha1sum -c
unzip -q commandlinetools-linux-16111833_latest.zip
mv cmdline-tools $SDK/cmdline-tools/latest
yes | $SDK/cmdline-tools/latest/bin/sdkmanager --licenses
$SDK/cmdline-tools/latest/bin/sdkmanager "platform-tools" "build-tools;36.1.0"
```

The project uses the **prebuilt** (non-Gradle) Android template, so no NDK,
platform SDK or Gradle is required — only `apksigner` (build-tools) and `adb`
(platform-tools).

## 3. Godot editor settings

Godot's Android exporter needs the SDK and a Java path in
`~/.config/godot/editor_settings-4.7.tres` (set once; or via Editor → Editor
Settings → Export → Android):

```
export/android/android_sdk_path = "/home/<you>/Android/Sdk"
export/android/java_sdk_path = "/usr/lib/jvm/java-27-openjdk"
```

Any installed JDK works for the non-Gradle export (it only runs `keytool` and
`apksigner`). Godot's documentation recommends JDK 17, which is required if you
switch to Gradle builds.

## 4. Debug APK

```sh
ANDROID_HOME=~/Android/Sdk tools/build_android.sh debug
```

The script creates the standard debug keystore (`~/.android/debug.keystore`,
alias `androiddebugkey`, password `android`) if missing, exports with

```sh
GODOT_ANDROID_KEYSTORE_DEBUG_PATH=~/.android/debug.keystore \
GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey \
GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android \
godot --headless --path . --export-debug "Android" builds/marble-run-debug.apk
```

and verifies the signature with `apksigner verify --print-certs`.

Result of the last build: `builds/marble-run-debug.apk`, 28.5 MB, arm64-v8a only,
package `io.github.kubow.marblerun`, targetSdk 36, **no permissions requested**
(checked with `aapt2 dump badging`). A release-template build of the same
project is 26.7 MB; ~25 MB of either is the Godot engine library.

## 5. Install and run on a device

Enable USB debugging on the device, connect it, then:

```sh
ANDROID_HOME=~/Android/Sdk tools/build_android.sh debug --install
# equivalent to:
~/Android/Sdk/platform-tools/adb install -r builds/marble-run-debug.apk
~/Android/Sdk/platform-tools/adb shell monkey -p io.github.kubow.marblerun -c android.intent.category.LAUNCHER 1
~/Android/Sdk/platform-tools/adb logcat -s godot      # engine log
```

To check performance on the device, enable *Settings → Show FPS* in the game, or
the debug overlay (frame rate, generation time, collision triangle count).

**Status:** the APK was built and its signature/manifest verified, but no device
was connected during development, so installation, touch input and on-device
performance have **not** been tested.

## 6. Release APK

Create a private keystore and pass it via environment variables:

```sh
keytool -genkeypair -v -keystore ~/keys/marble-release.keystore -alias marble \
  -keyalg RSA -keysize 2048 -validity 10000
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/keys/marble-release.keystore \
GODOT_ANDROID_KEYSTORE_RELEASE_USER=marble \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=... \
ANDROID_HOME=~/Android/Sdk tools/build_android.sh release
```

## Linux desktop build

```sh
godot --headless --path . --export-release "Linux" builds/linux/marble-run.x86_64
builds/linux/marble-run.x86_64
```

## Renderer

The project uses the Mobile renderer (Vulkan) with
`rendering/rendering_device/fallback_to_opengl3=true`, so devices without usable
Vulkan fall back to the Compatibility (OpenGL ES 3) renderer. Both were run on
desktop; to force Compatibility for testing:
`godot --path . --rendering-method gl_compatibility`.

## GitHub Actions

`.github/workflows/android.yml` runs on pushes/PRs to `main`, manual dispatch and
`v*` tags. It installs Godot 4.7.2 + Android templates (SHA-512 verified, cached),
uses the runner's preinstalled Android SDK with Temurin JDK 17, runs the test
suite, sets `version/code` to the run number, and builds the debug APK.

* Every run: APK available as the `marble-run-debug-apk` workflow artifact
  (Actions tab → run → Artifacts; requires GitHub login, kept 90 days).
* Tags: `git tag v0.3.0 && git push origin v0.3.0` builds with version name
  `0.3.0` and publishes a GitHub Release with `marble-run-v0.3.0.apk` and
  install instructions — a public link you can open on the phone.
* Actions are pinned to their Node 24 majors (checkout v7, setup-java v6,
  cache v6, upload-artifact v7, action-gh-release v3).

Optional but recommended — sign every CI build with the same key, so new builds
install over old ones:

```sh
base64 -w0 ~/.android/debug.keystore | gh secret set ANDROID_DEBUG_KEYSTORE_BASE64
```

Without that secret each run generates a new debug key and Android will refuse to
update an installed copy (uninstall first).
