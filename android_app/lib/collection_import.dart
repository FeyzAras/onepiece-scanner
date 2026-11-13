import 'dart:convert';

import 'card_matcher.dart';
import 'card_model.dart';
import 'csv_reader.dart';

/// Woher eine eingelesene Liste stammt.
enum ImportFormat {
  /// Die eigene Sicherungsdatei (JSON). Einzige verlustfreie Quelle.
  sicherung,

  /// Die eigene CSV. Enthaelt Ordner und Preiswahl, aber nicht jeden Einzelscan.
  eigeneCsv,

  /// Bestandsexport aus einem Cardmarket-Konto.
  cardmarketCsv,

  /// Irgendeine andere Tabelle, in der eine Spalte Kartennummern enthaelt.
  allgemeineCsv,

  /// Freier Text: Deckliste (`4xOP01-001`) oder eine Nummer je Zeile.
  textListe,

  /// Nichts Verwertbares gefunden.
  unbekannt,
}

extension ImportFormatLabel on ImportFormat {
  String get label => switch (this) {
        ImportFormat.sicherung => 'Sicherungsdatei',
        ImportFormat.eigeneCsv => 'Eigener CSV-Export',
        ImportFormat.cardmarketCsv => 'Cardmarket-Export',
        ImportFormat.allgemeineCsv => 'Tabelle mit Kartennummern',
        ImportFormat.textListe => 'Kartenliste',
        ImportFormat.unbekannt => 'nicht erkannt',
      };
}

/// Wie die eingelesenen Karten mit dem Bestand verrechnet werden.
enum ImportMode {
  /// Alles obendrauf. Der Normalfall beim Einlesen einer Liste.
  dazu,

  /// Nur so viel ergaenzen, dass die angegebene Anzahl erreicht wird.
  /// Fuer Listen, die man schon halb abgescannt hat.
  auffuellen,

  /// Zielbereich leeren und neu befuellen. Fuer die Wiederherstellung.
  ersetzen,
}

extension ImportModeLabel on ImportMode {
  String get label => switch (this) {
        ImportMode.dazu => 'dazuzählen',
        ImportMode.auffuellen => 'auf Anzahl auffüllen',
        ImportMode.ersetzen => 'ersetzen',
      };
}

/// Eine eingelesene Zeile - zugeordnet oder nicht.
class ImportRow {
  final int zeile;
  final String roh;
  final OpCard? card;
  final int anzahl;

  /// Ordnername aus der Datei, falls vorhanden.
  final String? ordnerName;

  /// Ordner-ID aus der Datei, falls vorhanden.
  final String? ordnerId;

  /// Gewaehlte Preisversion aus der Datei, falls vorhanden.
  final int? preiswahl;

  /// Erklaerung, wenn die Zuordnung nicht geradlinig war.
  final String? hinweis;

  const ImportRow({
    required this.zeile,
    required this.roh,
    this.card,
    this.anzahl = 1,
    this.ordnerName,
    this.ordnerId,
    this.preiswahl,
    this.hinweis,
  });

  bool get zugeordnet => card != null;
}

/// Ergebnis des Einlesens - Grundlage fuer die Vorschau.
class ImportResult {
  final ImportFormat format;

  /// false, wenn das Format nur vermutet wurde. Dann sollte der Nutzer es
  /// ueberstimmen koennen.
  final bool sicher;

  final List<ImportRow> zeilen;

  /// Meldungen, die der Nutzer vor dem Uebernehmen sehen muss.
  final List<String> warnungen;

  /// Nur bei [ImportFormat.sicherung]: der gespeicherte Zustand als JSON-Text,
  /// zum direkten Einspielen ueber `CollectionStore.importRaw`.
  final String? sicherungRoh;

  const ImportResult({
    required this.format,
    required this.sicher,
    required this.zeilen,
    this.warnungen = const [],
    this.sicherungRoh,
  });

  List<ImportRow> get treffer => zeilen.where((z) => z.zugeordnet).toList();
  List<ImportRow> get fehler => zeilen.where((z) => !z.zugeordnet).toList();
  List<ImportRow> get korrigiert =>
      zeilen.where((z) => z.zugeordnet && z.hinweis != null).toList();

  /// Anzahl tatsaechlicher Karten (Dubletten mitgezaehlt).
  int get kartenAnzahl => treffer.fold(0, (s, z) => s + z.anzahl);

  /// Verschiedene Karten.
  int get verschiedene => treffer.map((z) => z.card!.id).toSet().length;

  bool get leer => treffer.isEmpty;
}

/// Liest Kartenlisten aus verschiedenen Quellen ein.
///
/// Bewusst vollstaendig frei von Oberflaeche und Dateisystem: So laesst sich jedes
/// Format ohne Geraet testen, und genau das ist noetig - ein Import, der still das
/// Falsche tut, ist schlimmer als gar keiner.
class CollectionImport {
  /// Hoechstmenge je Zeile. Ein verrutschtes `9999x` wuerde sonst 9.999 Eintraege
  /// anlegen - die Sammlung haelt pro Einzelkarte ein eigenes Objekt.
  static const maxProZeile = 99;

  /// Hoechstmenge je Import, aus demselben Grund.
  static const maxGesamt = 5000;

  /// Spaltennamen, an denen ein Cardmarket-Export zu erkennen ist.
  static const _cardmarketSpalten = [
    'idarticle',
    'idproduct',
    'english name',
    'local name',
    'exp.',
    'exp. name',
    'isfoil',
    'isplayset',
    'issigned',
    'collector number',
  ];

  // ---------------------------------------------------------------- Erkennung

  /// Raet das Format. Zweiter Rueckgabewert sagt, wie sicher das ist.
  static (ImportFormat, bool) detect(String text) {
    final roh = CsvReader.stripBom(text).trim();
    if (roh.isEmpty) return (ImportFormat.unbekannt, true);

    // 1. Eigene Sicherung - eindeutig an der Kennung
    if (roh.startsWith('{')) {
      try {
        final map = jsonDecode(roh);
        if (map is Map && map['kind'] == 'collection-backup') {
          return (ImportFormat.sicherung, true);
        }
        if (map is Map && map['scans'] is List) {
          // Der nackte gespeicherte Zustand, ohne Umschlag
          return (ImportFormat.sicherung, false);
        }
      } catch (_) {
        // kein JSON - weiter unten als Text behandeln
      }
    }

    // 2. Sieht das nach einer Tabelle aus?
    final zeilen = CsvReader.parse(roh);
    if (zeilen.length >= 2 && _spaltenStabil(zeilen)) {
      final index = CsvReader.headerIndex(zeilen.first);

      if (index.containsKey('kartennummer')) return (ImportFormat.eigeneCsv, true);

      final treffer = _cardmarketSpalten.where(index.containsKey).length;
      if (treffer >= 2) return (ImportFormat.cardmarketCsv, true);

      if (_nummernSpalte(zeilen) != null) return (ImportFormat.allgemeineCsv, false);
    }

    // 3. Freier Text
    return _nummerImText.hasMatch(roh)
        ? (ImportFormat.textListe, true)
        : (ImportFormat.unbekannt, true);
  }

  /// Eine Tabelle hat ueber die ersten Zeilen hinweg etwa gleich viele Spalten.
  /// Fliesstext hat das nicht.
  static bool _spaltenStabil(List<List<String>> zeilen) {
    final probe = zeilen.take(10).toList();
    if (probe.first.length < 3) return false;
    final soll = probe.first.length;
    return probe.every((z) => (z.length - soll).abs() <= 1);
  }

  /// Sucht die Spalte, in der ueberwiegend Kartennummern stehen.
  static int? _nummernSpalte(List<List<String>> zeilen) {
    final daten = zeilen.skip(1).take(20).toList();
    if (daten.isEmpty) return null;
    var beste = -1;
    var besteQuote = 0.0;
    for (var spalte = 0; spalte < zeilen.first.length; spalte++) {
      var treffer = 0;
      for (final z in daten) {
        if (spalte < z.length && _nummerImText.hasMatch(z[spalte])) treffer++;
      }
      final quote = treffer / daten.length;
      if (quote > besteQuote) {
        besteQuote = quote;
        beste = spalte;
      }
    }
    return besteQuote > 0.6 ? beste : null;
  }

  // ------------------------------------------------------------------ Einlesen

  /// Liest eine Liste ein. [alsFormat] ueberstimmt die Erkennung.
  static ImportResult read(
    String text, {
    required CardMatcher matcher,
    ImportFormat? alsFormat,
  }) {
    final erkannt = detect(text);
    final format = alsFormat ?? erkannt.$1;
    final sicher = alsFormat != null ? true : erkannt.$2;

    final ergebnis = switch (format) {
      ImportFormat.sicherung => _lesSicherung(text, matcher),
      ImportFormat.eigeneCsv => _lesEigeneCsv(text, matcher),
      ImportFormat.cardmarketCsv => _lesCardmarketCsv(text, matcher),
      ImportFormat.allgemeineCsv => _lesAllgemeineCsv(text, matcher),
      ImportFormat.textListe => _lesText(text, matcher),
      ImportFormat.unbekannt => const ImportResult(
          format: ImportFormat.unbekannt,
          sicher: true,
          zeilen: [],
          warnungen: ['In dieser Datei steht keine einzige Kartennummer.'],
        ),
    };

    return ImportResult(
      format: format,
      sicher: sicher,
      zeilen: ergebnis.zeilen,
      warnungen: [...ergebnis.warnungen, ..._mengenWarnungen(ergebnis.zeilen)],
      sicherungRoh: ergebnis.sicherungRoh,
    );
  }

  static List<String> _mengenWarnungen(List<ImportRow> zeilen) {
    final warnungen = <String>[];
    final gekappt = zeilen.where((z) => z.anzahl >= maxProZeile).length;
    if (gekappt > 0) {
      warnungen.add('$gekappt Zeile(n) mit sehr hoher Stückzahl — '
          'je Zeile werden höchstens $maxProZeile Karten übernommen.');
    }
    final gesamt = zeilen.where((z) => z.zugeordnet).fold<int>(0, (s, z) => s + z.anzahl);
    if (gesamt > maxGesamt) {
      warnungen.add('Die Liste enthält $gesamt Karten. Übernommen werden die ersten $maxGesamt.');
    }
    return warnungen;
  }

  // --- Sicherung -------------------------------------------------------------

  static ImportResult _lesSicherung(String text, CardMatcher matcher) {
    try {
      final map = jsonDecode(CsvReader.stripBom(text).trim());
      if (map is! Map) throw const FormatException('kein Objekt');

      // Entweder mit Umschlag (state) oder der nackte Zustand
      final state = map['state'] is Map ? map['state'] : map;
      if (state is! Map || state['scans'] is! List) {
        throw const FormatException('keine Scans enthalten');
      }

      final scans = (state['scans'] as List).whereType<Map>().toList();
      final zeilen = <ImportRow>[];
      final ordner = <String, String>{
        for (final f in (state['folders'] as List? ?? []).whereType<Map>())
          '${f['id']}': '${f['name']}',
      };

      // Fuer die Vorschau: je Karte eine Zeile mit Anzahl
      final gezaehlt = <String, int>{};
      final erster = <String, Map>{};
      for (final s in scans) {
        final id = '${s['id']}';
        final schluessel = '$id\u0000${s['folder']}';
        gezaehlt[schluessel] = (gezaehlt[schluessel] ?? 0) + 1;
        erster.putIfAbsent(schluessel, () => s);
      }

      var nr = 0;
      gezaehlt.forEach((schluessel, anzahl) {
        nr++;
        final s = erster[schluessel]!;
        final id = '${s['id']}';
        final folderId = s['folder'] as String?;
        zeilen.add(ImportRow(
          zeile: nr,
          roh: id,
          card: matcher.byId(id),
          anzahl: anzahl,
          ordnerId: folderId,
          ordnerName: folderId == null ? null : ordner[folderId],
          hinweis: matcher.byId(id) == null ? 'im Katalog nicht gefunden' : null,
        ));
      });

      final warnungen = <String>[];
      final unbekannte = zeilen.where((z) => !z.zugeordnet).length;
      if (unbekannte > 0) {
        warnungen.add('$unbekannte Karten-Nummern kennt der Katalog nicht. '
            'Beim vollständigen Wiederherstellen bleiben sie trotzdem erhalten.');
      }

      return ImportResult(
        format: ImportFormat.sicherung,
        sicher: true,
        zeilen: zeilen,
        warnungen: warnungen,
        sicherungRoh: jsonEncode(state),
      );
    } catch (e) {
      return const ImportResult(
        format: ImportFormat.sicherung,
        sicher: true,
        zeilen: [],
        warnungen: ['Die Sicherungsdatei ließ sich nicht lesen.'],
      );
    }
  }

  // --- Eigene CSV ------------------------------------------------------------

  static ImportResult _lesEigeneCsv(String text, CardMatcher matcher) {
    final zeilen = CsvReader.parse(text);
    if (zeilen.length < 2) {
      return const ImportResult(
        format: ImportFormat.eigeneCsv,
        sicher: true,
        zeilen: [],
        warnungen: ['Die Datei enthält keine Kartenzeilen.'],
      );
    }

    final index = CsvReader.headerIndex(zeilen.first);
    final spNummer = CsvReader.findColumn(index, ['kartennummer']);
    final spAnzahl = CsvReader.findColumn(index, ['anzahl', 'menge', 'quantity']);
    final spOrdner = CsvReader.findColumn(index, ['ordner']);
    final spOrdnerId = CsvReader.findColumn(index, ['ordner-id', 'ordnerid']);
    final spWahl = CsvReader.findColumn(index, ['preiswahl', 'preisversion']);

    final ergebnis = <ImportRow>[];
    for (var i = 1; i < zeilen.length; i++) {
      final z = zeilen[i];
      final roh = CsvReader.field(z, spNummer);
      if (roh.isEmpty) continue;

      final treffer = resolve(roh, matcher);
      ergebnis.add(ImportRow(
        zeile: i + 1,
        roh: roh,
        card: treffer.card,
        anzahl: _menge(CsvReader.field(z, spAnzahl)),
        ordnerName: _oderNull(CsvReader.field(z, spOrdner)),
        ordnerId: _oderNull(CsvReader.field(z, spOrdnerId)),
        preiswahl: int.tryParse(CsvReader.field(z, spWahl)),
        hinweis: treffer.hinweis,
      ));
    }

    return ImportResult(format: ImportFormat.eigeneCsv, sicher: true, zeilen: ergebnis);
  }

  // --- Cardmarket ------------------------------------------------------------

  static ImportResult _lesCardmarketCsv(String text, CardMatcher matcher) {
    final zeilen = CsvReader.parse(text);
    if (zeilen.length < 2) {
      return const ImportResult(
        format: ImportFormat.cardmarketCsv,
        sicher: true,
        zeilen: [],
        warnungen: ['Die Datei enthält keine Kartenzeilen.'],
      );
    }

    final index = CsvReader.headerIndex(zeilen.first);
    final spProdukt = CsvReader.findColumn(index, ['idproduct', 'id product']);
    final spName = CsvReader.findColumn(index, ['english name', 'local name', 'name', 'card name']);
    final spAnzahl = CsvReader.findColumn(index, ['quantity', 'amount', 'anzahl', 'menge', 'count']);
    final spPlayset = CsvReader.findColumn(index, ['isplayset']);

    final ergebnis = <ImportRow>[];
    var playsets = 0;

    for (var i = 1; i < zeilen.length; i++) {
      final z = zeilen[i];
      final name = CsvReader.field(z, spName);
      final produktText = CsvReader.field(z, spProdukt);
      if (name.isEmpty && produktText.isEmpty) continue;

      var anzahl = _menge(CsvReader.field(z, spAnzahl));
      final playset = CsvReader.field(z, spPlayset).toLowerCase();
      if (playset == 'true' || playset == '1' || playset == 'yes') {
        anzahl *= 4;
        playsets++;
      }

      OpCard? card;
      String? hinweis;

      // 1. Produktnummer trifft exakt die Druckvariante
      final produktId = int.tryParse(produktText);
      if (produktId != null) card = matcher.byProductId(produktId);

      // 2. Cardmarket schreibt die Kartennummer in Klammern hinter den Namen
      if (card == null && name.isNotEmpty) {
        final treffer = resolve(name, matcher);
        card = treffer.card;
        if (card != null) {
          hinweis = card.alt
              ? 'über den Namen zugeordnet'
              : 'über den Namen zugeordnet, Normalversion angenommen';
        }
      }

      ergebnis.add(ImportRow(
        zeile: i + 1,
        roh: name.isNotEmpty ? name : produktText,
        card: card,
        anzahl: anzahl,
        hinweis: hinweis,
      ));
    }

    final warnungen = <String>[
      'Zustand, Sprache, Folierung und deine eigenen Verkaufspreise werden nicht übernommen — '
          'dafür hat die App kein Feld.',
    ];
    if (playsets > 0) {
      warnungen.add('$playsets Zeile(n) waren als Playset markiert und wurden vervierfacht.');
    }

    return ImportResult(
      format: ImportFormat.cardmarketCsv,
      sicher: true,
      zeilen: ergebnis,
      warnungen: warnungen,
    );
  }

  // --- Beliebige Tabelle -----------------------------------------------------

  static ImportResult _lesAllgemeineCsv(String text, CardMatcher matcher) {
    final zeilen = CsvReader.parse(text);
    final spalte = _nummernSpalte(zeilen);
    if (spalte == null) return _lesText(text, matcher);

    final index = CsvReader.headerIndex(zeilen.first);
    final spAnzahl =
        CsvReader.findColumn(index, ['anzahl', 'menge', 'quantity', 'amount', 'count', 'qty']);

    final ergebnis = <ImportRow>[];
    for (var i = 1; i < zeilen.length; i++) {
      final z = zeilen[i];
      final roh = CsvReader.field(z, spalte);
      if (roh.isEmpty) continue;
      final treffer = resolve(roh, matcher);
      ergebnis.add(ImportRow(
        zeile: i + 1,
        roh: roh,
        card: treffer.card,
        anzahl: _menge(CsvReader.field(z, spAnzahl)),
        hinweis: treffer.hinweis,
      ));
    }

    return ImportResult(
      format: ImportFormat.allgemeineCsv,
      sicher: false,
      zeilen: ergebnis,
      warnungen: ['Spalte "${zeilen.first[spalte]}" wurde als Kartennummer gelesen.'],
    );
  }

  // --- Freier Text -----------------------------------------------------------

  /// Erkennt einen Listeneintrag samt Stueckzahl.
  ///
  /// Die Stueckzahl steckt bewusst **im selben** Ausdruck: Stuende sie nicht drin,
  /// wuerde `4xOP01-001` als Kartennummer `xOP01-001` gelesen - das `x` waehre Teil
  /// des Praefixes, und die Karte waere nicht zu finden.
  ///
  /// Abgedeckt: `4xOP01-001`, `4x OP01-001`, `4 x OP01-001`, `OP01-001 x3`,
  /// `OP01-001 ×3` (das Mal-Zeichen kommt beim Kopieren von Webseiten staendig vor),
  /// `OP01-001 *3` sowie `OP01-001` allein. Die blanke Zahl davor (`3 OP01-001`)
  /// wird getrennt behandelt, siehe [_blankeMengeDavor].
  static final RegExp _nummerImText = RegExp(
    r'(?:(\d{1,4})\s*[xX×*]\s*)?'
    r'([A-Za-z]{1,5}[0-9]{0,2}\s*[-–—_.·]\s*[0-9]{1,3}'
    r'(?:[\s_-]*\(?(?:ALT[\s-]?ART|ALT)\)?)?)'
    r'(?:\s*[xX×*]\s*(\d{1,4}))?',
    caseSensitive: false,
  );

  /// Eine blanke Zahl zaehlt nur, wenn sie unmittelbar vor der Nummer steht.
  /// Zahlen sonstwo in der Zeile (Preise, Jahreszahlen) bleiben aussen vor.
  static final RegExp _blankeMengeDavor = RegExp(r'(?:^|[\s,;])(\d{1,4})\s+$');

  static ImportResult _lesText(String text, CardMatcher matcher) {
    final zeilen = const LineSplitter().convert(CsvReader.stripBom(text));
    final ergebnis = <ImportRow>[];
    var mitInlineMenge = 0;
    var nummernGesamt = 0;

    for (var i = 0; i < zeilen.length; i++) {
      final zeile = zeilen[i];
      if (zeile.trim().isEmpty) continue;

      var inDieserZeile = 0;
      for (final m in _nummerImText.allMatches(zeile)) {
        final roh = m.group(2)!;
        final mengeDavor = m.group(1);
        final mengeDanach = m.group(3);

        var anzahl = 1;
        if (mengeDavor != null) {
          anzahl = int.tryParse(mengeDavor) ?? 1;
          mitInlineMenge++;
        } else if (mengeDanach != null) {
          anzahl = int.tryParse(mengeDanach) ?? 1;
          mitInlineMenge++;
        } else {
          final blank = _blankeMengeDavor.firstMatch(zeile.substring(0, m.start));
          if (blank != null) anzahl = int.tryParse(blank.group(1)!) ?? 1;
        }
        if (anzahl <= 0) continue;

        final treffer = resolve(roh, matcher);
        ergebnis.add(ImportRow(
          zeile: i + 1,
          roh: roh.trim(),
          card: treffer.card,
          anzahl: anzahl > maxProZeile ? maxProZeile : anzahl,
          hinweis: treffer.hinweis,
        ));
        inDieserZeile++;
        nummernGesamt++;
      }

      // Zeile mit Text, aber ohne erkennbare Nummer: als Fehler ausweisen,
      // damit nichts unbemerkt verschwindet. Ueberschriften ausgenommen.
      if (inDieserZeile == 0 && !_istUeberschrift(zeile)) {
        ergebnis.add(ImportRow(zeile: i + 1, roh: zeile.trim()));
      }
    }

    // Nur ein Etikett fuer die Anzeige, kein eigener Weg
    final istDeck = mitInlineMenge >= 3 && nummernGesamt > 0;
    return ImportResult(
      format: ImportFormat.textListe,
      sicher: true,
      zeilen: ergebnis,
      warnungen: istDeck
          ? const ['Sieht nach einer Deckliste aus. Decklisten unterscheiden kein Alt-Art — '
              'solche Karten landen auf der Normalversion.']
          : const [],
    );
  }

  static final RegExp _ueberschrift = RegExp(
    r'^\s*(//|#|Leader|Character|Event|Stage|Don!!|Deck|Total|Summe)',
    caseSensitive: false,
  );

  static bool _istUeberschrift(String zeile) => _ueberschrift.hasMatch(zeile);

  // ---------------------------------------------------------------- Zuordnung

  /// Loest einen Text in eine Karte auf.
  ///
  /// Reihenfolge: erst die normalisierte Nummer (`OP1-1` -> `OP01-001`), dann die
  /// tolerante Erkennung aus [CardMatcher.findNumber], die auch OCR-typische
  /// Verwechslungen wie `OPO1-OO1` auffaengt.
  static ({OpCard? card, String? hinweis}) resolve(String roh, CardMatcher matcher) {
    final (ohneAlt, altGewuenscht) = _trenneAlt(roh.trim());
    final norm = _normalisiere(ohneAlt);

    if (norm != null) {
      final kandidaten = altGewuenscht ? ['$norm-ALT', norm] : [norm, '$norm-ALT'];
      for (final k in kandidaten) {
        final c = matcher.byId(k);
        if (c == null) continue;
        return (card: c, hinweis: _hinweis(altGewuenscht, c, norm, ohneAlt));
      }
    }

    // Tolerante Suche. Akzeptiert nur real existierende IDs.
    final gefunden = matcher.findNumber(roh);
    if (gefunden != null) {
      final kandidaten =
          altGewuenscht ? ['$gefunden-ALT', gefunden] : [gefunden, '$gefunden-ALT'];
      for (final k in kandidaten) {
        final c = matcher.byId(k);
        if (c == null) continue;
        return (card: c, hinweis: 'als $gefunden gelesen');
      }
    }

    return (card: null, hinweis: null);
  }

  static String? _hinweis(bool altGewuenscht, OpCard card, String norm, String roh) {
    if (altGewuenscht && !card.alt) return 'keine Alt-Art im Katalog, Normalversion genommen';
    if (!altGewuenscht && card.alt) return 'es gibt nur die Alt-Art';
    if (norm.toUpperCase() != roh.trim().toUpperCase()) return 'als $norm gelesen';
    return null;
  }

  static final RegExp _altRe = RegExp(
    r'^(.*?)[\s_-]*\(?\s*(ALT[\s-]?ART|ALT)\s*\)?$',
    caseSensitive: false,
  );

  static (String, bool) _trenneAlt(String s) {
    final m = _altRe.firstMatch(s);
    if (m != null && m.group(1)!.trim().isNotEmpty) return (m.group(1)!.trim(), true);
    return (s, false);
  }

  static final RegExp _klammern = RegExp(r'^[\(\[\s]+|[\)\]\s]+$');
  static final RegExp _trenner = RegExp(r'[–—‒−_.·]');
  static final RegExp _umsMinus = RegExp(r'\s*-\s*');
  static final RegExp _aufbau = RegExp(r'^([A-Z]+)(\d*)-(\d+)$');

  /// `op1-1` -> `OP01-001`. Null, wenn der Text gar nicht wie eine Nummer aussieht.
  static String? _normalisiere(String s) {
    var t = s.toUpperCase().trim().replaceAll(_klammern, '');
    t = t.replaceAll(_trenner, '-').replaceAll(_umsMinus, '-');
    final m = _aufbau.firstMatch(t);
    if (m == null) return null;
    final prefix = m.group(1)!;
    final setNr = m.group(2)!;
    final kartenNr = m.group(3)!;
    if (kartenNr.length > 3) return null;
    final nummer = kartenNr.padLeft(3, '0');
    return setNr.isEmpty ? '$prefix-$nummer' : '$prefix${setNr.padLeft(2, '0')}-$nummer';
  }

  static int _menge(String roh) {
    if (roh.isEmpty) return 1;
    final n = int.tryParse(roh.replaceAll(RegExp(r'[^\d]'), ''));
    if (n == null || n <= 0) return 1;
    return n > maxProZeile ? maxProZeile : n;
  }

  static String? _oderNull(String s) => s.isEmpty ? null : s;
}
