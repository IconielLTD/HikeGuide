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

It prompts for a keystore password, a key password, and your name/org. Save the
two passwords **in your password manager** (not in a file), and note the alias
(`hikeguide`).

Keep **two offline backups** of the `.jks` file (e.g. an encrypted USB stick).
If it's lost you can never ship an update that installs over the existing app;
if it leaks together with its passwords, someone could sign a fake "update"
that Android installs over the real one.

## 2. Create android/key.properties

Make a file at `android/key.properties` (next to this one). It says **where**
the key is — and nothing secret:

```properties
keyAlias=hikeguide
storeFile=C:\\Users\\<you>\\hikeguide-release.jks
```

Use double backslashes in `storeFile` on Windows, or forward slashes. A relative
path also works (resolved from the `android/` folder).

**The passwords never go in this file.** Anything that can read files as you
— malware, or any code that runs during an ordinary build (Gradle plugins, the
Flutter tool, packages with build hooks) — could otherwise take the key and its
passwords together. If an older `key.properties` still has `storePassword` /
`keyPassword` lines, they're ignored (the build and `release.ps1` warn about
them): check both passwords are in your password manager, then delete those
lines.

## 3. Build the APK

From the repository root:

```powershell
.\release.ps1
```

It asks for the keystore password and the key password (press Enter if they're
the same), passes them to that one build only, then clears them and stops
Gradle's background process so they don't linger in memory. If PowerShell
refuses to run scripts, use
`powershell -ExecutionPolicy Bypass -File .\release.ps1`.

The signed APK lands at `build/app/outputs/flutter-apk/app-release.apk`.
A plain `flutter build apk --release` stops with an error pointing you to
`release.ps1`, and without `key.properties` at all the release build fails too
(unless `HIKEGUIDE_ALLOW_DEBUG_SIGNING=1` is set — see the top of this file).
Debug builds (`flutter run`) need none of this.

## 4. Publish on GitHub Releases

Attach `app-release.apk` to a new GitHub Release, tagged with the version
(e.g. `v1.0.0`). People download and install it directly — no app store
involved. [Obtainium](https://github.com/ImranR98/Obtainium) can watch your
Releases page and auto-update installs for anyone who wants that.

Bump `version:` in `pubspec.yaml` before each release so updates are recognised
as newer.
