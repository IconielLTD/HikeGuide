# Builds a signed release APK (build/app/outputs/flutter-apk/app-release.apk).
#
# Asks for the keystore passwords and hands them to this one build through
# environment variables, so they're never stored in a file. Afterwards they're
# cleared and Gradle's background process (the "daemon", which would otherwise
# keep them in memory for hours) is stopped. See android/SIGNING.md.
#
#   .\release.ps1                 # extra arguments go to `flutter build apk`
#
# If PowerShell refuses to run scripts:
#   powershell -ExecutionPolicy Bypass -File .\release.ps1

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Read-Secret([string]$Prompt) {
    $secure = Read-Host -AsSecureString $Prompt
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$keyProperties = Join-Path $PSScriptRoot 'android\key.properties'
if (-not (Test-Path $keyProperties)) {
    throw 'android/key.properties is missing - see android/SIGNING.md.'
}
if (Select-String -Path $keyProperties -Pattern '^\s*(storePassword|keyPassword)\s*=' -Quiet) {
    Write-Warning ('android/key.properties still contains the passwords. They are no ' +
        'longer used: once they are saved in your password manager, delete those ' +
        'two lines (android/SIGNING.md).')
}

$env:HIKEGUIDE_STORE_PASSWORD = Read-Secret 'Keystore password'
$keyPassword = Read-Secret 'Key password (just press Enter if it is the same)'
if ($keyPassword) { $env:HIKEGUIDE_KEY_PASSWORD = $keyPassword }
Remove-Variable keyPassword

try {
    flutter build apk --release @args
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit code $LASTEXITCODE)" }
}
finally {
    Remove-Item Env:HIKEGUIDE_STORE_PASSWORD, Env:HIKEGUIDE_KEY_PASSWORD `
        -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'android\gradlew.bat') -p (Join-Path $PSScriptRoot 'android') --stop | Out-Null
}
