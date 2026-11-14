# Veroeffentlicht eine neue App-Version.
#
# Warum ein Skript und nicht Handarbeit: Beim Veroeffentlichen gibt es drei Fehler, die
# sich erst auf dem Handy des Nutzers zeigen und dann nicht mehr zu reparieren sind.
#
#   1. Falscher Signaturschluessel -> "App nicht installiert". Der einzige Ausweg waere
#      Deinstallieren, und damit waere die Sammlung weg.
#   2. Version ohne --split-per-abi gebaut -> versionCode 800 statt 2800, also kleiner als
#      die veroeffentlichte 2001. Android lehnt das als Downgrade ab.
#   3. version.json vor dem Release geschrieben -> alle Geraete melden ein Update, dessen
#      Datei es noch nicht gibt.
#
# Das Skript prueft alle drei, bevor irgendetwas veroeffentlicht wird.
#
# Aufruf:
#   . C:\Users\<Benutzer>\Dev\.toolchain\env.ps1
#   .\scripts\release.ps1 -Version 0.8.0 -NotesFile .\release-notes.md

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$NotesFile,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

$Fingerabdruck = 'CC:BD:78:F9:5F:9D:ED:20:8A:B9:6D:CC:DF:ED:50:A3:BE:70:95:E1:D6:CD:30:55:23:43:9C:F6:83:CB:04:BB'
$Repo = 'FeyzAras/onepiece-scanner'
$AssetName = 'onepiece-scanner-arm64.apk'

$Wurzel = Split-Path -Parent $PSScriptRoot
$AppDir = Join-Path $Wurzel 'android_app'
$Pubspec = Join-Path $AppDir 'pubspec.yaml'
$KeyProps = Join-Path $AppDir 'android\key.properties'
$Apk = Join-Path $AppDir 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
$VersionJson = Join-Path $Wurzel 'docs\data\version.json'

function Schritt($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Abbruch($text) { Write-Host "ABBRUCH: $text" -ForegroundColor Red; exit 1 }

# Externe Programme (flutter, gh, git, apksigner) schreiben Warnungen auf stderr.
# Windows PowerShell 5.1 macht daraus Fehlerdatensaetze, sobald stderr umgeleitet wird -
# und mit ErrorActionPreference 'Stop' bricht das Skript dann mitten im Build ab, obwohl
# nur eine harmlose Warnung kam. Genau so ist das Release v0.9.0 zuerst gescheitert.
# Deshalb laufen externe Programme hier mit 'Continue', und ob sie geklappt haben,
# entscheidet allein ihr Exitcode.
function Nativ([scriptblock]$befehl) {
    $vorher = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $befehl } finally { $ErrorActionPreference = $vorher }
}

# --- 1. Version gegen pubspec pruefen -------------------------------------------------
Schritt '1/7  Version pruefen'

if ($Version -notmatch '^\d+\.\d+\.\d+$') { Abbruch "Version muss die Form X.Y.Z haben, bekam '$Version'." }

$teile = $Version.Split('.')
$erwarteteBuildNummer = [int]$teile[0] * 10000 + [int]$teile[1] * 100 + [int]$teile[2]
$erwartet = "version: $Version+$erwarteteBuildNummer"

$pubspecZeile = (Get-Content $Pubspec | Where-Object { $_ -match '^version:' })
if ($pubspecZeile -ne $erwartet) {
    Abbruch "pubspec.yaml sagt '$pubspecZeile', erwartet wird '$erwartet'.`n         Erst die Version in pubspec.yaml setzen."
}
Write-Host "  pubspec.yaml: $pubspecZeile"
Write-Host "  versionCode nach --split-per-abi (arm64): $(2000 + $erwarteteBuildNummer)"

# Das Arbeitsverzeichnis muss sauber sein. Am Ende committet das Skript version.json und
# holt per 'pull --rebase' die Commits der taeglichen Actions - mit offenen Aenderungen
# verweigert Git das. Dann waere das Release schon oeffentlich, version.json aber nicht
# hochgeladen. Genau das ist bei v0.9.0 passiert; deshalb wird es jetzt VORHER geprueft.
Push-Location $Wurzel
try { $offen = Nativ { git status --porcelain } } finally { Pop-Location }
if ($offen) {
    Abbruch "Es gibt uncommittete Aenderungen:`n$($offen -join "`n")`n         Erst committen, dann veroeffentlichen."
}
Write-Host "  Arbeitsverzeichnis sauber."

# --- 2. Schluessel pruefen ------------------------------------------------------------
Schritt '2/7  Signaturschluessel pruefen'

if (-not (Test-Path $KeyProps)) { Abbruch "android/key.properties fehlt." }
$store = (Get-Content $KeyProps | Where-Object { $_ -match '^storeFile=' }) -replace '^storeFile=', ''
if (-not (Test-Path $store)) {
    Abbruch "Keystore nicht gefunden: $store`n         NICHT neu erzeugen - aus der Sicherung wiederherstellen.`n         Ohne genau diesen Schluessel laesst sich die installierte App nie wieder aktualisieren."
}
Write-Host "  Keystore: $store"

if ($WhatIfOnly) { Write-Host "`nNur Pruefung - hier ist Schluss." -ForegroundColor Yellow; exit 0 }

# --- 3. Bauen -------------------------------------------------------------------------
Schritt '3/7  App bauen'

Push-Location $AppDir
try {
    # --split-per-abi ist Pflicht, siehe Kopfkommentar
    Nativ { flutter build apk --release --split-per-abi }
    if ($LASTEXITCODE -ne 0) { Abbruch "Build fehlgeschlagen." }
} finally { Pop-Location }

if (-not (Test-Path $Apk)) { Abbruch "APK nicht gefunden: $Apk" }
$groesse = (Get-Item $Apk).Length
Write-Host "  APK: $([math]::Round($groesse/1MB,1)) MB"

# --- 4. Signatur pruefen --------------------------------------------------------------
Schritt '4/7  Signatur pruefen'

$apksigner = Get-ChildItem (Join-Path $env:ANDROID_SDK_ROOT 'build-tools') -Recurse -Filter 'apksigner.bat' |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $apksigner) { Abbruch "apksigner nicht gefunden. Ist die Werkzeugkette geladen?" }

$zeile = Nativ { & $apksigner verify --print-certs $Apk } | Select-String -Pattern 'SHA-256 digest'
if (-not $zeile) { Abbruch "Signatur konnte nicht gelesen werden." }
$ist = (($zeile -split ':')[-1]).Trim().ToUpper()
$soll = $Fingerabdruck.Replace(':', '')

if ($ist -ne $soll) {
    Abbruch "FALSCHER SCHLUESSEL.`n         erwartet: $soll`n         gefunden: $ist`n         Dieses Release wuerde sich NICHT ueber die installierte App legen lassen."
}
Write-Host "  Fingerabdruck stimmt." -ForegroundColor Green

# --- 5. Release anlegen ---------------------------------------------------------------
Schritt '5/7  Release anlegen'

# Die Datei muss VOR dem Hochladen den richtigen Namen tragen.
#
# Nicht ueber die #-Angabe von gh loesbar: Die setzt nur das Anzeige-Etikett, der
# Dateiname im Release bleibt der urspruengliche. Genau daran ist das Release v0.8.0
# zuerst gescheitert - die Datei hing als app-arm64-v8a-release.apk dran, und damit
# ging der Dauerlink /releases/latest/download/onepiece-scanner-arm64.apk ins Leere.
$Hochzuladen = Join-Path ([System.IO.Path]::GetTempPath()) $AssetName
Copy-Item $Apk $Hochzuladen -Force
Write-Host "  benannt als: $AssetName"

$titel = "v$Version"
$argumente = @("release", "create", "v$Version", $Hochzuladen, "--repo", $Repo, "--title", $titel)
if ($NotesFile) { $argumente += @("--notes-file", $NotesFile) } else { $argumente += @("--generate-notes") }

Nativ { & gh @argumente }
if ($LASTEXITCODE -ne 0) { Abbruch "gh release create fehlgeschlagen." }

# --- 6. Pruefen, dass die Datei wirklich erreichbar ist --------------------------------
Schritt '6/7  Erreichbarkeit der APK pruefen'

$url = "https://github.com/$Repo/releases/download/v$Version/$AssetName"
try {
    $antwort = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 60
    Write-Host "  HTTP $($antwort.StatusCode) - $url"
} catch {
    Abbruch "Die APK ist unter $url nicht erreichbar.`n         version.json wird deshalb NICHT geschrieben."
}

# --- 7. version.json schreiben --------------------------------------------------------
Schritt '7/7  version.json schreiben'

$sha = (Get-FileHash $Apk -Algorithm SHA256).Hash.ToLower()
$notizen = @()
if ($NotesFile -and (Test-Path $NotesFile)) {
    $notizen = Get-Content $NotesFile | Where-Object { $_ -match '^\s*[-*]\s+' } | ForEach-Object { $_ -replace '^\s*[-*]\s+', '' }
}

$inhalt = [ordered]@{
    version     = $Version
    versionCode = 2000 + $erwarteteBuildNummer
    released    = (Get-Date -Format 'yyyy-MM-dd')
    minSdk      = 24
    abi         = 'arm64-v8a'
    apk         = [ordered]@{ url = $url; bytes = $groesse; sha256 = $sha }
    notes       = $notizen
    mandatory   = $false
}

New-Item -ItemType Directory -Force -Path (Split-Path $VersionJson) | Out-Null
$json = $inhalt | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($VersionJson, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  geschrieben: $VersionJson"

Push-Location $Wurzel
try {
    Nativ { git add docs/data/version.json }
    Nativ { git commit -m "Version $Version veroeffentlicht" }
    if ($LASTEXITCODE -ne 0) { Abbruch "version.json liess sich nicht committen." }
    # Die taeglichen Actions committen ins selbe Repository - ohne rebase lehnt GitHub ab
    Nativ { git pull --rebase origin master }
    if ($LASTEXITCODE -ne 0) { Abbruch "git pull --rebase fehlgeschlagen - version.json ist lokal committet, aber nicht hochgeladen." }
    Nativ { git push origin master }
    if ($LASTEXITCODE -ne 0) { Abbruch "git push fehlgeschlagen - version.json ist lokal committet, aber nicht hochgeladen." }
} finally { Pop-Location }

Write-Host "`nFertig: v$Version ist veroeffentlicht." -ForegroundColor Green
Write-Host "Die App meldet das Update beim naechsten Start (hoechstens einmal taeglich)."
