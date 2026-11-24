import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'card_model.dart';

/// Eine Cardmarket-Version einer Kartennummer: ein Produkt in einer Ausgabe.
///
/// Cardmarket fuehrt pro Nummer oft mehrere Versionen - bei OP17-040 etwa den Booster-
/// Druck, die Parallele und die Asien-Auflage. Ihre Preise liegen weit auseinander, und
/// welche jemand in der Hand haelt, weiss nur er selbst.
class KartenVersion {
  final int idProduct;
  final int idExpansion;

  /// Name der Cardmarket-Ausgabe, z.B. "The World's Strongest Warriors (Asia Region Legal)".
  final String ausgabe;

  /// Cardmarket-Trendpreis in Euro.
  final double preis;

  /// Motive (Platz wie [OpCard.motivIndex]), deren automatische Version das ist. Leer, wenn
  /// die Version keinem Motiv zugeordnet ist - die gibt es dann nur zum Auswaehlen.
  final List<int> motive;

  const KartenVersion({
    required this.idProduct,
    required this.idExpansion,
    required this.ausgabe,
    required this.preis,
    this.motive = const [],
  });

  bool istStandardFuer(OpCard karte) => motive.contains(karte.motivIndex);
}

/// Alle Cardmarket-Versionen, wie `scripts/import-cardmarket-prices.js` sie schreibt.
class VersionsDaten {
  /// Stand der Cardmarket-Daten.
  final String asOf;

  /// Versionen je Kartennummer (gross geschrieben), guenstigste zuerst.
  final Map<String, List<KartenVersion>> jeNummer;

  const VersionsDaten({required this.asOf, required this.jeNummer});

  int get anzahlNummern => jeNummer.length;

  /// Versionen einer Nummer, guenstigste zuerst. Leer, wenn es nichts zu waehlen gibt.
  List<KartenVersion> von(String baseId) => jeNummer[baseId.toUpperCase()] ?? const [];

  KartenVersion? produkt(String baseId, int idProduct) {
    for (final v in von(baseId)) {
      if (v.idProduct == idProduct) return v;
    }
    return null;
  }

  /// Die automatische Version eines Motivs, oder null.
  KartenVersion? standardFuer(OpCard karte) {
    for (final v in von(karte.baseId)) {
      if (v.istStandardFuer(karte)) return v;
    }
    return null;
  }

  /// Liest die Datei. Unbrauchbare Eintraege fallen weg; null nur, wenn gar nichts zu
  /// gebrauchen ist - dann bleibt der bisherige Stand.
  ///
  /// Format: `{asOf, ausgaben: {idExpansion: Name}, versionen: {Nummer: [[idProduct,
  /// idExpansion, Cent, [Motive]?], ...]}}` - knapp, weil die Datei taeglich geladen wird.
  static VersionsDaten? parse(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final ausgaben = <int, String>{};
      final rohAusgaben = map['ausgaben'];
      if (rohAusgaben is Map) {
        rohAusgaben.forEach((k, v) {
          final id = int.tryParse('$k');
          if (id != null && v is String && v.isNotEmpty) ausgaben[id] = v;
        });
      }
      final rohVersionen = map['versionen'];
      if (rohVersionen is! Map) return null;

      final jeNummer = <String, List<KartenVersion>>{};
      rohVersionen.forEach((nummer, liste) {
        if (liste is! List) return;
        final versionen = <KartenVersion>[];
        for (final e in liste) {
          if (e is! List || e.length < 3) continue;
          final p = e[0], x = e[1], cent = e[2];
          if (p is! num || x is! num || cent is! num || cent <= 0) continue;
          final motive = e.length > 3 && e[3] is List
              ? (e[3] as List).whereType<num>().map((n) => n.toInt()).toList()
              : const <int>[];
          versionen.add(KartenVersion(
            idProduct: p.toInt(),
            idExpansion: x.toInt(),
            ausgabe: ausgaben[x.toInt()] ?? 'Cardmarket-Ausgabe ${x.toInt()}',
            preis: cent / 100,
            motive: motive,
          ));
        }
        if (versionen.isEmpty) return;
        versionen.sort((a, b) {
          final c = a.preis.compareTo(b.preis);
          return c != 0 ? c : a.idProduct.compareTo(b.idProduct);
        });
        jeNummer['$nummer'.toUpperCase()] = versionen;
      });
      if (jeNummer.isEmpty) return null;
      return VersionsDaten(asOf: '${map['asOf'] ?? ''}', jeNummer: jeNummer);
    } catch (_) {
      return null;
    }
  }
}

/// Versionen nach Ausgabe gruppiert, fuer die Anzeige.
///
/// Zuerst die Ausgabe mit der automatischen Version von [karte], dann Ausgaben mit
/// Versionen anderer Motive, dann der Rest. Innerhalb einer Gruppe guenstigste zuerst.
List<({String ausgabe, List<KartenVersion> versionen})> nachAusgabe(List<KartenVersion> versionen, OpCard karte) {
  final gruppen = <String, List<KartenVersion>>{};
  for (final v in versionen) {
    gruppen.putIfAbsent(v.ausgabe, () => []).add(v);
  }
  int rang(List<KartenVersion> g) {
    if (g.any((v) => v.istStandardFuer(karte))) return 0;
    if (g.any((v) => v.motive.isNotEmpty)) return 1;
    return 2;
  }

  final liste = gruppen.entries.map((e) => (ausgabe: e.key, versionen: e.value..sort((a, b) => a.preis.compareTo(b.preis)))).toList();
  liste.sort((a, b) {
    final r = rang(a.versionen).compareTo(rang(b.versionen));
    if (r != 0) return r;
    return a.versionen.first.preis.compareTo(b.versionen.first.preis);
  });
  return liste;
}

/// Uebersetzt eine alte Preiswahl (Platz in der aufsteigend sortierten Preisliste, bis
/// v0.12) in die Produktnummer. Null, wenn der Platz nicht mehr existiert.
///
/// Der Platz war nie verlaesslich: Ueberholen sich zwei Versionen im Preis, zeigt er
/// auf die andere. Deshalb wird jetzt die Produktnummer gespeichert - die bleibt.
int? produktZumAltenPlatz(List<KartenVersion> versionen, int platz) {
  if (platz < 0 || platz >= versionen.length) return null;
  return versionen[platz].idProduct;
}

/// Uebersetzt einen sehr alten gespeicherten Betrag in die Version mit dem naechsten Preis.
int? produktZumAltenBetrag(List<KartenVersion> versionen, double betrag) {
  if (versionen.isEmpty) return null;
  var beste = versionen.first;
  for (final v in versionen) {
    if ((v.preis - betrag).abs() < (beste.preis - betrag).abs()) beste = v;
  }
  return beste.idProduct;
}

/// Laedt die Versionen: mitgeliefert, zuletzt geladen, oder frisch aus dem Repository.
///
/// Zwischenspeicher als Datei, nicht in SharedPreferences - die Liste ist rund 250 KB
/// gross, und die Einstellungsdatei liegt bei Android vollstaendig im Arbeitsspeicher.
class VersionStore {
  static const remoteUrl = 'https://raw.githubusercontent.com/FeyzAras/onepiece-scanner/master/docs/data/versions.json';

  final String url;
  final Future<Directory> Function() _ordner;

  VersionStore({this.url = remoteUrl, Future<Directory> Function()? ordner}) : _ordner = ordner ?? _standardOrdner;

  static Future<Directory> _standardOrdner() => getApplicationSupportDirectory();

  Future<File> _datei() async => File('${(await _ordner()).path}${Platform.pathSeparator}versions.json');

  /// Der in die App eingebackene Stand - funktioniert immer, auch ohne Netz.
  static Future<VersionsDaten?> gebuendelt() async {
    try {
      return VersionsDaten.parse(await rootBundle.loadString('assets/versions.json'));
    } catch (_) {
      return null;
    }
  }

  /// Der zuletzt heruntergeladene Stand.
  Future<VersionsDaten?> gespeichert() async {
    try {
      final datei = await _datei();
      if (!await datei.exists()) return null;
      return VersionsDaten.parse(await datei.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Holt den aktuellen Stand und legt ihn ab. Null, wenn das nicht klappt.
  Future<VersionsDaten?> abrufen() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final roh = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
      final daten = VersionsDaten.parse(roh);
      if (daten == null) return null;
      try {
        final datei = await _datei();
        await datei.parent.create(recursive: true);
        // Erst vollstaendig schreiben, dann umbenennen - ein Abbruch hinterlaesst die alte Datei
        final zwischen = File('${datei.path}.tmp');
        await zwischen.writeAsString(roh, flush: true);
        await zwischen.rename(datei.path);
      } catch (_) {
        // Ohne Zwischenspeicher geht es trotzdem weiter
      }
      return daten;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
