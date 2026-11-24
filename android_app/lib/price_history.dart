import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Preisverlauf eines Sets, wie ihn `scripts/build-price-history.js` schreibt:
/// `{dates: [...], prices: {"OP01-001": [187, 185, null, ...]}}` - Cent, an [dates]
/// ausgerichtet, null = an diesem Tag kein Preis.
class SetHistory {
  final List<String> dates;
  final Map<String, List<int?>> prices;

  const SetHistory({required this.dates, required this.prices});

  /// Gibt null zurueck statt abzustuerzen, wenn die Datei unbrauchbar ist.
  static SetHistory? parse(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final dates = map['dates'];
      final prices = map['prices'];
      if (dates is! List || prices is! Map) return null;

      final tage = dates.map((e) => '$e').toList();
      final reihen = <String, List<int?>>{};
      prices.forEach((key, value) {
        if (value is! List) return;
        // Nur Reihen, die zur Datumsachse passen - sonst wuerden Werte verrutschen
        if (value.length != tage.length) return;
        reihen['$key'] = value.map((v) => v is num ? v.round() : null).toList();
      });
      return SetHistory(dates: tage, prices: reihen);
    } catch (_) {
      return null;
    }
  }

  /// Verlauf einer Karte in Euro. Leer, wenn die Karte nicht vorkommt.
  List<PreisPunkt> verlaufVon(String cardId) {
    final reihe = prices[cardId];
    if (reihe == null) return const [];
    final punkte = <PreisPunkt>[];
    for (var i = 0; i < dates.length; i++) {
      final cent = reihe[i];
      if (cent != null) punkte.add(PreisPunkt(dates[i], cent / 100));
    }
    return punkte;
  }
}

class PreisPunkt {
  final String datum; // ISO, "2026-11-13"
  final double wert;
  const PreisPunkt(this.datum, this.wert);
}

/// Wert der heutigen Sammlung an jedem bekannten Tag.
class WertVerlauf {
  /// [kartenIds] enthaelt eine ID je Einzelkarte - Dubletten mehrfach.
  ///
  /// Luecken werden vorwaerts gefuellt: Fehlt fuer eine Karte an einem Tag der Preis,
  /// gilt der letzte bekannte. Sonst entstuenden Einbrueche, die es am Markt nie gab.
  /// Vor dem ersten bekannten Preis zaehlt eine Karte nicht mit - es gab schlicht keinen.
  ///
  /// Grenze: Gerechnet wird mit der automatisch zugeordneten Druckvariante. Hat der
  /// Nutzer fuer eine Karte eine andere Version gewaehlt, ist deren Verlauf nicht enthalten.
  static List<PreisPunkt> berechnen({
    required List<String> kartenIds,
    required Map<String, SetHistory> historien,
  }) {
    if (kartenIds.isEmpty || historien.isEmpty) return const [];

    final anzahl = <String, int>{};
    for (final id in kartenIds) {
      anzahl[id] = (anzahl[id] ?? 0) + 1;
    }

    // Gemeinsame Datumsachse ueber alle beteiligten Sets
    final alleTage = <String>{};
    for (final h in historien.values) {
      alleTage.addAll(h.dates);
    }
    final tage = alleTage.toList()..sort();
    if (tage.isEmpty) return const [];
    final summe = List<double>.filled(tage.length, 0);

    for (final eintrag in anzahl.entries) {
      final code = eintrag.key.split('-').first;
      final h = historien[code];
      final reihe = h?.prices[eintrag.key];
      if (h == null || reihe == null) continue;

      final proTag = <String, int>{};
      for (var i = 0; i < h.dates.length; i++) {
        final cent = reihe[i];
        if (cent != null) proTag[h.dates[i]] = cent;
      }

      int? zuletzt;
      for (var i = 0; i < tage.length; i++) {
        zuletzt = proTag[tage[i]] ?? zuletzt;
        if (zuletzt != null) summe[i] += zuletzt * eintrag.value / 100;
      }
    }

    return [for (var i = 0; i < tage.length; i++) PreisPunkt(tage[i], summe[i])];
  }

  /// Veraenderung gegenueber dem Stand vor [tage] Tagen (oder dem aeltesten bekannten).
  static ({double absolut, double prozent})? veraenderung(List<PreisPunkt> verlauf, int tage) {
    if (verlauf.length < 2) return null;
    final letzter = verlauf.last;
    final ziel = DateTime.parse(letzter.datum).subtract(Duration(days: tage));
    var vorher = verlauf.first;
    for (final p in verlauf) {
      if (DateTime.parse(p.datum).isAfter(ziel)) break;
      vorher = p;
    }
    if (vorher.wert <= 0 || identical(vorher, letzter)) return null;
    final diff = letzter.wert - vorher.wert;
    return (absolut: diff, prozent: diff / vorher.wert * 100);
  }
}

/// Laedt Set-Verlaeufe aus dem Repository, mit Zwischenspeicher als Datei.
///
/// Bewusst Dateien und nicht SharedPreferences: Die Einstellungsdatei liegt bei Android
/// vollstaendig im Arbeitsspeicher, und 60 Verlaeufe zu je bis zu 300 KB haetten dort
/// nichts verloren.
class HistoryStore {
  static const basisUrl =
      'https://raw.githubusercontent.com/FeyzAras/onepiece-scanner/master/docs/data/history/';

  /// So lange gilt eine gespeicherte Datei als frisch. Die Preise aendern sich einmal
  /// am Tag; oefter nachzusehen braucht nur Datenvolumen.
  static const frischDauer = Duration(hours: 6);

  final String basis;
  final Future<Directory> Function() _ordner;

  HistoryStore({this.basis = basisUrl, Future<Directory> Function()? ordner})
      : _ordner = ordner ?? _standardOrdner;

  static Future<Directory> _standardOrdner() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}history');
  }

  final Map<String, SetHistory> _imSpeicher = {};

  /// Verlauf eines Sets. Ohne Netz gilt der zuletzt gespeicherte Stand, auch wenn er
  /// alt ist - ein alter Verlauf ist besser als keiner. Null nur, wenn es nie einen gab.
  ///
  /// [erzwingen]: nicht auf eine frische Datei vertrauen, sondern neu holen - fuer
  /// "nach unten ziehen zum Aktualisieren". Vorher holte das innerhalb von 6 Stunden nichts.
  Future<SetHistory?> laden(String setCode, {DateTime? jetzt, bool erzwingen = false}) async {
    final schonDa = _imSpeicher[setCode];
    if (schonDa != null && !erzwingen) return schonDa;

    final ordner = await _ordner();
    final datei = File('${ordner.path}${Platform.pathSeparator}$setCode.json');
    final zeit = jetzt ?? DateTime.now();

    if (!erzwingen && await datei.exists() && zeit.difference(await datei.lastModified()) < frischDauer) {
      final h = SetHistory.parse(await datei.readAsString());
      if (h != null) return _imSpeicher[setCode] = h;
    }

    final roh = await _holen('$basis$setCode.json');
    if (roh != null) {
      final h = SetHistory.parse(roh);
      if (h != null) {
        try {
          await ordner.create(recursive: true);
          await datei.writeAsString(roh);
        } catch (_) {
          // Ohne Zwischenspeicher geht es trotzdem weiter
        }
        return _imSpeicher[setCode] = h;
      }
    }

    if (await datei.exists()) {
      final h = SetHistory.parse(await datei.readAsString());
      if (h != null) return _imSpeicher[setCode] = h;
    }
    return null;
  }

  /// Mehrere Sets, hoechstens vier gleichzeitig.
  Future<Map<String, SetHistory>> ladenMehrere(Iterable<String> codes, {bool erzwingen = false}) async {
    final ergebnis = <String, SetHistory>{};
    final liste = codes.toSet().toList();
    for (var i = 0; i < liste.length; i += 4) {
      final runde = liste.skip(i).take(4);
      await Future.wait(runde.map((code) async {
        final h = await laden(code, erzwingen: erzwingen);
        if (h != null) ergebnis[code] = h;
      }));
    }
    return ergebnis;
  }

  static Future<String?> _holen(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
