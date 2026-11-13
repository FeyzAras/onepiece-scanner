import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eine Versionsnummer der Form `major.minor.patch`.
///
/// Verglichen wird bewusst ueber die **Versionsbezeichnung** (0.9.0), nicht ueber den
/// versionCode: Beim Bauen mit `--split-per-abi` rechnet Flutter `1000 x ABI` auf den
/// versionCode drauf. Wer einmal ohne diesen Schalter baut, bekaeme einen ganz anderen
/// Wert - und jeder Vergleich kippte.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  const AppVersion(this.major, this.minor, this.patch);

  /// Liest `0.9.0`, `v0.9.0`, `0.9` und `0.9.0+900` (die Build-Nummer wird ignoriert).
  /// Gibt null zurueck statt abzustuerzen, wenn der Text keine Version ist.
  static AppVersion? parse(String? raw) {
    if (raw == null) return null;
    var t = raw.trim();
    if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
    final plus = t.indexOf('+');
    if (plus >= 0) t = t.substring(0, plus);
    final teile = t.split('.');
    if (teile.isEmpty || teile.length > 3) return null;
    final zahlen = <int>[];
    for (final teil in teile) {
      final n = int.tryParse(teil);
      if (n == null || n < 0) return null;
      zahlen.add(n);
    }
    while (zahlen.length < 3) {
      zahlen.add(0);
    }
    return AppVersion(zahlen[0], zahlen[1], zahlen[2]);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Inhalt von `docs/data/version.json` - was die neueste Fassung ist und wo sie liegt.
class UpdateInfo {
  final AppVersion version;
  final String released;
  final int minSdk;
  final String apkUrl;
  final int? bytes;
  final String? sha256;
  final List<String> notes;

  /// Notausgang: Eine Pflicht-Aktualisierung laesst sich nicht ueberspringen.
  /// Gedacht fuer den Fall, dass eine veroeffentlichte Fassung Daten gefaehrdet.
  final bool mandatory;

  const UpdateInfo({
    required this.version,
    required this.released,
    required this.minSdk,
    required this.apkUrl,
    this.bytes,
    this.sha256,
    this.notes = const [],
    this.mandatory = false,
  });

  /// Liest die Datei. Gibt null zurueck, wenn sie unbrauchbar ist - dann wird einfach
  /// kein Update angeboten, statt mit halben Angaben etwas herunterzuladen.
  static UpdateInfo? parse(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;

      final version = AppVersion.parse(map['version']?.toString());
      if (version == null) return null;

      final apk = map['apk'];
      if (apk is! Map) return null;
      final url = apk['url'];
      if (url is! String || !url.startsWith('https://')) return null;

      final bytes = apk['bytes'];
      final sha = apk['sha256'];
      final notes = map['notes'];

      return UpdateInfo(
        version: version,
        released: (map['released'] ?? '').toString(),
        minSdk: int.tryParse('${map['minSdk'] ?? 0}') ?? 0,
        apkUrl: url,
        bytes: bytes is num && bytes > 0 ? bytes.toInt() : null,
        sha256: sha is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha) ? sha.toLowerCase() : null,
        notes: notes is List ? notes.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList() : const [],
        mandatory: map['mandatory'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Groesse fuer die Anzeige, z.B. "37,3 MB".
  String get groesseText {
    final b = bytes;
    if (b == null) return '';
    return '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
}

/// Ergebnis einer Pruefung.
class UpdateCheck {
  /// Das angebotene Update, oder null wenn es keins gibt.
  final UpdateInfo? angebot;

  /// Die neueste veroeffentlichte Fassung, auch wenn sie nicht neuer ist.
  final UpdateInfo? neueste;

  /// Fehlerbeschreibung, wenn die Pruefung selbst scheiterte.
  final String? fehler;

  /// true, wenn gar nicht geprueft wurde (letzte Pruefung juenger als ein Tag).
  final bool gedrosselt;

  const UpdateCheck({this.angebot, this.neueste, this.fehler, this.gedrosselt = false});
}

class UpdateException implements Exception {
  final String meldung;
  const UpdateException(this.meldung);
  @override
  String toString() => meldung;
}

/// Der Nutzer hat den Download abgebrochen.
class UpdateAbgebrochen implements Exception {
  const UpdateAbgebrochen();
}

/// Zum Abbrechen eines laufenden Downloads.
class DownloadAbbruch {
  bool _abgebrochen = false;
  bool get abgebrochen => _abgebrochen;
  void abbrechen() => _abgebrochen = true;
}

class UpdateService {
  static const remoteUrl =
      'https://raw.githubusercontent.com/FeyzAras/onepiece-scanner/master/docs/data/version.json';

  static const _letztePruefungKey = 'update_last_check';
  static const _uebersprungenKey = 'update_skipped_version';

  /// Hoechstens einmal am Tag von selbst nachsehen.
  static const pruefAbstand = Duration(hours: 24);

  /// Ob ein Update angeboten werden soll. Reine Entscheidung, ohne Netz - testbar.
  ///
  /// Die Prozessorfrage (arm64) wird bewusst nicht geprueft: Laeuft diese App, kann das
  /// Geraet auch die naechste Fassung ausfuehren - es gibt nur die eine Variante.
  static UpdateInfo? anbieten({
    required UpdateInfo info,
    required AppVersion installiert,
    int? androidVersion,
    String? uebersprungen,
    bool manuell = false,
  }) {
    if (!(info.version > installiert)) return null;
    if (androidVersion != null && androidVersion < info.minSdk) return null;
    if (!manuell && !info.mandatory && uebersprungen == info.version.toString()) return null;
    return info;
  }

  /// Fragt die neueste Version ab.
  ///
  /// Ohne [manuell] hoechstens einmal am Tag, und Fehler bleiben still - kein Netz ist
  /// unterwegs der Normalfall und kein Grund fuer eine Meldung.
  static Future<UpdateCheck> pruefen({
    required String installierteVersion,
    int? androidVersion,
    bool manuell = false,
    DateTime? jetzt,
    String url = remoteUrl,
  }) async {
    final installiert = AppVersion.parse(installierteVersion);
    if (installiert == null) {
      return UpdateCheck(fehler: 'Eigene Version unbekannt ($installierteVersion)');
    }

    final prefs = await SharedPreferences.getInstance();
    final zeit = jetzt ?? DateTime.now();

    if (!manuell) {
      final letzte = prefs.getInt(_letztePruefungKey);
      if (letzte != null &&
          zeit.difference(DateTime.fromMillisecondsSinceEpoch(letzte)) < pruefAbstand) {
        return const UpdateCheck(gedrosselt: true);
      }
    }

    final roh = await _holeText(url);
    if (roh == null) {
      return const UpdateCheck(fehler: 'Keine Verbindung zum Update-Server.');
    }
    final info = UpdateInfo.parse(roh);
    if (info == null) {
      return const UpdateCheck(fehler: 'Die Versionsangaben ließen sich nicht lesen.');
    }

    await prefs.setInt(_letztePruefungKey, zeit.millisecondsSinceEpoch);

    return UpdateCheck(
      neueste: info,
      angebot: anbieten(
        info: info,
        installiert: installiert,
        androidVersion: androidVersion,
        uebersprungen: prefs.getString(_uebersprungenKey),
        manuell: manuell,
      ),
    );
  }

  /// Diese Version nicht mehr von selbst anbieten.
  static Future<void> ueberspringen(AppVersion version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uebersprungenKey, version.toString());
  }

  static Future<String?> _holeText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Laedt die APK herunter und prueft sie.
  ///
  /// Geschrieben wird zuerst in eine `.part`-Datei; erst wenn Laenge und Pruefsumme
  /// stimmen, bekommt sie ihren endgueltigen Namen. So kann ein abgebrochener Download
  /// nie als vermeintlich fertige APK an den Installer gehen.
  ///
  /// Anders als die Preis- und Deck-Abrufe wirft diese Funktion bei Fehlern - ein
  /// gescheiterter 37-MB-Download muss sichtbar werden, nicht still verschwinden.
  static Future<File> herunterladen(
    UpdateInfo info, {
    required Directory ziel,
    void Function(int empfangen, int? gesamt)? fortschritt,
    DownloadAbbruch? abbruch,
  }) async {
    await ziel.create(recursive: true);
    final name = 'onepiece-scanner-${info.version}.apk';
    final teil = File('${ziel.path}${Platform.pathSeparator}$name.part');
    final fertig = File('${ziel.path}${Platform.pathSeparator}$name');
    if (await teil.exists()) await teil.delete();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(info.apkUrl));
      // GitHub leitet Release-Dateien auf einen anderen Host um. HttpClient folgt
      // Umleitungen bei GET von selbst - hier nur ausdruecklich festgehalten.
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw UpdateException('Download fehlgeschlagen (HTTP ${response.statusCode}).');
      }

      final gesamt = response.contentLength > 0 ? response.contentLength : info.bytes;
      sink = teil.openWrite();
      var empfangen = 0;

      await for (final stueck in response.timeout(const Duration(seconds: 45))) {
        if (abbruch?.abgebrochen ?? false) throw const UpdateAbgebrochen();
        sink.add(stueck);
        empfangen += stueck.length;
        fortschritt?.call(empfangen, gesamt);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (abbruch?.abgebrochen ?? false) throw const UpdateAbgebrochen();

      final erwartet = info.bytes ?? (response.contentLength > 0 ? response.contentLength : null);
      if (erwartet != null && empfangen != erwartet) {
        throw UpdateException('Download unvollständig ($empfangen von $erwartet Bytes).');
      }

      final soll = info.sha256;
      if (soll != null) {
        final ist = (await sha256.bind(teil.openRead()).first).toString();
        if (ist != soll) {
          throw const UpdateException('Die heruntergeladene Datei ist beschädigt (Prüfsumme stimmt nicht).');
        }
      }

      if (await fertig.exists()) await fertig.delete();
      return await teil.rename(fertig.path);
    } on UpdateAbgebrochen {
      await _aufraeumen(sink, teil);
      rethrow;
    } on UpdateException {
      await _aufraeumen(sink, teil);
      rethrow;
    } catch (e) {
      await _aufraeumen(sink, teil);
      throw UpdateException('Download fehlgeschlagen: $e');
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _aufraeumen(IOSink? sink, File teil) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await teil.exists()) await teil.delete();
    } catch (_) {}
  }

  /// Entfernt alte Downloads. Beim Start aufgerufen: Nach einer erfolgreichen
  /// Installation laeuft die App neu an und kann erst dann aufraeumen.
  static Future<void> aufraeumen(Directory ordner) async {
    try {
      if (!await ordner.exists()) return;
      await for (final f in ordner.list()) {
        if (f is File) await f.delete();
      }
    } catch (_) {
      // Aufraeumen darf nie den Start stoeren
    }
  }
}
