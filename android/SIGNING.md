# Signing release builds

HikeGuide is distributed as a signed APK on **GitHub Releases** — people
download and sideload it. This doc sets up a stable signing key so the APKs you
publish can be **updated in place**: Android only accepts an update that's
signed with the same key as the already-installed app.

Release builds need this key: with `android/key.properties` absent,
`flutter build apk --release` (and `flutter run --release`) **fail**, so a
debug-signed APK can't be published by accident — the debug key isn't stable
across machines, and an APK signed with it can't update an existing install.
Debug builds (`flutter run`) need none of this. For a quick personal release
build without the key, opt in to debug signing, and don't hand the result to
anyone:

```powershell
$env:HIKEGUIDE_ALLOW_DEBUG_SIGNING = "1"; flutter build apk --release
```

None of these files are committed — `key.properties`, `*.jks`, and `*.keystore`
are all in `android/.gitignore`. **Keep the keystore safe and backed up
privately: if you lose it, you can't ship an update that installs over the old
version — people would have to uninstall and lose their saved trips.**

## 1. Create a signing keystore

Run this once and keep the output file safe (somewhere private, not this repo).

```powershell
keytool -genkey -v `
  -keystore $env:USERPROFILE\hikeguide-release.jks `
  -storetype JKS `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias hikeguide
```

It prompts for a keystore password, a key password, and your name/org. Remember
the two passwords and the alias (`hikeguide`).

## 2. Create android/key.properties

Make a file at `android/key.properties` (next to this one):

```properties
storePassword=<the keystore password from step 1>
keyPassword=<the key password from step 1>
keyAlias=hikeguide
storeFile=C:\\Users\\<you>\\hikeguide-release.jks
```

Use double backslashes in `storeFile` on Windows, or forward slashes. A relative
path also works (resolved from the `android/` folder).

## 3. Build the APK

```powershell
flutter build apk --release
```

The signed APK lands at `build/app/outputs/flutter-apk/app-release.apk`.
`build.gradle` detects `key.properties` automatically and signs with your key.
Without it the release build stops with an error (unless
`HIKEGUIDE_ALLOW_DEBUG_SIGNING=1` is set — see the top of this file).

## 4. Publish on GitHub Releases

Attach `app-release.apk` to a new GitHub Release, tagged with the version
(e.g. `v1.0.0`). People download and install it directly — no app store
involved. [Obtainium](https://github.com/ImranR98/Obtainium) can watch your
Releases page and auto-update installs for anyone who wants that.

Bump `version:` in `pubspec.yaml` before each release so updates are recognised
as newer.
