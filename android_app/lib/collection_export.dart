import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'collection_view.dart';

/// Exportiert die Sammlung als CSV - zum Sichern, Weitergeben oder Auswerten
/// in einer Tabellenkalkulation.
///
/// Bewusst mit Semikolon getrennt und Komma als Dezimalzeichen: So oeffnet Excel
/// in deutscher Einstellung die Datei direkt richtig, ohne Importdialog.
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
  ];

  /// Baut den CSV-Inhalt. Oeffentlich, damit er sich ohne Dateisystem testen laesst.
  static String buildCsv({
    required List<StackedCard> stacks,
    required String Function(String folderId) folderName,
    String? priceAsOf,
  }) {
    final buffer = StringBuffer();

    // Hinweiszeile, damit spaeter nachvollziehbar ist, worauf sich die Preise beziehen
    if (priceAsOf != null && priceAsOf.isNotEmpty) {
      buffer.writeln('# One Piece Scanner – Sammlung, Preise nach Cardmarket, Stand $priceAsOf');
    }
    buffer.writeln(_columns.join(_separator));

    for (final stack in stacks) {
      final card = stack.card;
      final letzter = stack.entries
          .map((e) => e.at)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      buffer.writeln([
        _escape(card.id),
        _escape(card.name),
        _escape(card.setCode),
        _escape(card.rarity),
        _escape(card.cardType),
        _escape(card.color),
        stack.count.toString(),
        _money(stack.unitPrice),
        _money(stack.totalValue),
        _escape(folderName(stack.entries.first.folderId)),
        _escape(stack.how == 'number+name' ? 'Nummer + Name' : 'Nummer'),
        _escape(_date(letzter)),
      ].join(_separator));
    }

    return buffer.toString();
  }

  /// Schreibt die Datei und oeffnet den Teilen-Dialog des Geraets.
  static Future<void> share({
    required List<StackedCard> stacks,
    required String Function(String folderId) folderName,
    String? priceAsOf,
  }) async {
    final csv = buildCsv(stacks: stacks, folderName: folderName, priceAsOf: priceAsOf);
    final dir = await getTemporaryDirectory();
    final stamp = _date(DateTime.now()).replaceAll('.', '-');
    final file = File('${dir.path}/sammlung-$stamp.csv');
    // BOM, damit Excel die Umlaute richtig anzeigt
    await file.writeAsString('﻿$csv');

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'One Piece Sammlung',
        text: 'Sammlung als CSV (${stacks.length} verschiedene Karten)',
      ),
    );
  }

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
