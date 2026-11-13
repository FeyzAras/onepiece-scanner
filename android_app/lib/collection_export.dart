import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'card_model.dart';
import 'collection_store.dart';
import 'collection_view.dart';

/// Exportiert die Sammlung - zum Sichern, Weitergeben oder Auswerten.
///
/// Es entstehen zwei Dateien, die zusammen geteilt werden:
///
/// * `sammlung-TT-MM-JJJJ.csv` - zum Ansehen in Excel. Bewusst mit Semikolon getrennt
///   und Komma als Dezimalzeichen, damit Excel in deutscher Einstellung die Datei
///   direkt richtig oeffnet.
/// * `sammlung-TT-MM-JJJJ.json` - die eigentliche Sicherung. Sie enthaelt den
///   gespeicherten Zustand woertlich, also auch Ordner, Preisauswahl und Eintraege,
///   zu denen der Katalog keine Karte kennt. Nur diese Datei kann verlustfrei
///   wieder eingelesen werden.
class CollectionExport {
  static const _separator = ';';

  static const _columns = [
    'Kartennummer',
    'Name',
    'Set',
    'Seltenheit',
    'Kartentyp',
    'Farbe',
    'Anzahl',
    'Einzelpreis',
    'Gesamtpreis',
    'Ordner',
    'Erkannt über',
    'Zuletzt gescannt',
    // Technische Spalten ganz rechts, damit links alles lesbar bleibt
    'Alt-Art',
    'Ordner-ID',
    'Preiswahl',
  ];

  /// Baut den CSV-Inhalt. Oeffentlich, damit er sich ohne Dateisystem testen laesst.
  ///
  /// [entries] muss die **vollstaendige** Sammlung sein, nicht die gerade angezeigte
  /// Auswahl. Frueher wurde die gefilterte Anzeigeliste uebergeben - wer etwas gesucht
  /// hatte, sicherte unbemerkt nur einen Teil.
  static String buildCsv({
    required List<CollectionEntry> entries,
    required double Function(OpCard card) priceOf,
    required String Function(String folderId) folderName,
    int? Function(OpCard card)? choiceOf,
    String? priceAsOf,
  }) {
    final buffer = StringBuffer();

    // Hinweiszeile, damit spaeter nachvollziehbar ist, worauf sich die Preise beziehen
    if (priceAsOf != null && priceAsOf.isNotEmpty) {
      buffer.writeln('# One Piece Scanner – Sammlung, Preise nach Cardmarket, Stand $priceAsOf');
    }
    buffer.writeln(_columns.join(_separator));

    for (final gruppe in _group(entries)) {
      final card = gruppe.first.card;
      final anzahl = gruppe.length;
      final einzel = priceOf(card);
      final letzter = gruppe.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
      final wahl = choiceOf?.call(card);
      buffer.writeln([
        _escape(card.id),
        _escape(card.name),
        _escape(card.setCode),
        _escape(card.rarity),
        _escape(card.cardType),
        _escape(card.color),
        anzahl.toString(),
        _money(einzel),
        _money(einzel * anzahl),
        _escape(folderName(gruppe.first.folderId)),
        _escape(_howLabel(gruppe.first.how)),
        _escape(_date(letzter)),
        card.alt ? 'ja' : 'nein',
        _escape(gruppe.first.folderId),
        wahl?.toString() ?? '',
      ].join(_separator));
    }

    return buffer.toString();
  }

  /// Fasst zu einer Zeile zusammen, was wirklich gleich ist: gleiche Karte,
  /// gleicher Ordner, gleiche Erkennungsart.
  ///
  /// Nur nach der Karten-ID zu gruppieren waere falsch - dieselbe Karte kann in
  /// mehreren Ordnern liegen, und beim Zusammenfassen wuerde ein Ordner verschwinden.
  static List<List<CollectionEntry>> _group(List<CollectionEntry> entries) {
    final map = <String, List<CollectionEntry>>{};
    for (final e in entries) {
      map.putIfAbsent('${e.card.id}\u0000${e.folderId}\u0000${e.how}', () => []).add(e);
    }
    final gruppen = map.values.toList();
    gruppen.sort((a, b) {
      final bySet = a.first.card.setCode.compareTo(b.first.card.setCode);
      if (bySet != 0) return bySet;
      final byId = a.first.card.id.compareTo(b.first.card.id);
      if (byId != 0) return byId;
      return a.first.folderId.compareTo(b.first.folderId);
    });
    return gruppen;
  }

  /// Die Sicherungsdatei. [rawState] ist der gespeicherte Zustand als JSON-Text -
  /// woertlich das, was auf dem Geraet liegt, damit die Sicherung gar nicht davon
  /// abweichen kann.
  static String buildBackupJson(String rawState, {DateTime? at}) {
    Object? state;
    try {
      state = jsonDecode(rawState);
    } catch (_) {
      // Lieber den Rohtext mitnehmen als die Sicherung scheitern lassen
      state = rawState;
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'onepiece-scanner',
      'kind': 'collection-backup',
      'schema': 1,
      'exportedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'state': state,
    });
  }

  /// Schreibt beide Dateien und oeffnet den Teilen-Dialog des Geraets.
  static Future<void> share({
    required List<CollectionEntry> entries,
    required double Function(OpCard card) priceOf,
    required String Function(String folderId) folderName,
    int? Function(OpCard card)? choiceOf,
    String? priceAsOf,
  }) async {
    final csv = buildCsv(
      entries: entries,
      priceOf: priceOf,
      folderName: folderName,
      choiceOf: choiceOf,
      priceAsOf: priceAsOf,
    );

    final dir = await getTemporaryDirectory();
    final stamp = _date(DateTime.now()).replaceAll('.', '-');

    final csvDatei = File('${dir.path}/sammlung-$stamp.csv');
    // BOM, damit Excel die Umlaute richtig anzeigt
    await csvDatei.writeAsString('﻿$csv');

    final dateien = <XFile>[XFile(csvDatei.path, mimeType: 'text/csv')];

    final roh = await CollectionStore.exportRaw();
    if (roh != null && roh.isNotEmpty) {
      final jsonDatei = File('${dir.path}/sammlung-$stamp.json');
      await jsonDatei.writeAsString(buildBackupJson(roh));
      dateien.add(XFile(jsonDatei.path, mimeType: 'application/json'));
    }

    final verschiedene = _group(entries).length;
    await SharePlus.instance.share(
      ShareParams(
        files: dateien,
        subject: 'One Piece Sammlung',
        text: 'Sammlung: ${entries.length} Karten, $verschiedene verschiedene. '
            'Die JSON-Datei ist die Sicherung zum Wiedereinlesen.',
      ),
    );
  }

  static String _howLabel(String how) => switch (how) {
        'number+name' => 'Nummer + Name',
        'import' => 'Importiert',
        _ => 'Nummer',
      };

  static String _money(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Felder mit Trennzeichen, Anfuehrungszeichen oder Zeilenumbruch muessen gequotet werden.
  static String _escape(String value) {
    if (!value.contains(_separator) && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}
