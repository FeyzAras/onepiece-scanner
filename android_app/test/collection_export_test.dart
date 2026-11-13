import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/collection_export.dart';
import 'package:onepiece_scanner/collection_view.dart';

/// Der Export ist das Sicherungsnetz der Sammlung. Wenn er unvollstaendig ist,
/// faellt das erst auf, wenn man ihn braucht - also im schlimmsten Moment.
///
/// Der wichtigste Test hier ist der letzte: dieselbe Karte in zwei Ordnern muss
/// zwei Zeilen ergeben. Frueher wurde nur nach Karten-ID gruppiert, wodurch der
/// zweite Ordner samt seiner Karten aus der Sicherung verschwand.
void main() {
  OpCard karte(String id, {String name = 'Testkarte', bool alt = false}) => OpCard(
        id: id,
        baseId: alt ? id.replaceAll('-ALT', '') : id,
        alt: alt,
        name: name,
        rarity: 'R',
        cardType: 'Character',
        color: 'Red',
        effect: '',
      );

  CollectionEntry eintrag(OpCard c, {String folder = 'default', String how = 'number', int at = 1000}) =>
      CollectionEntry(
        card: c,
        folderId: folder,
        how: how,
        at: DateTime.fromMillisecondsSinceEpoch(at),
      );

  String csv(List<CollectionEntry> entries, {int? Function(OpCard)? choiceOf}) =>
      CollectionExport.buildCsv(
        entries: entries,
        priceOf: (_) => 1.5,
        folderName: (id) => id == 'default' ? 'Meine Sammlung' : 'Doppelte',
        choiceOf: choiceOf,
      );

  List<String> zeilen(String inhalt) =>
      inhalt.trim().split('\n').map((z) => z.trimRight()).toList();

  group('CSV-Aufbau', () {
    test('Kopfzeile steht und enthaelt die technischen Spalten', () {
      final z = zeilen(csv([eintrag(karte('OP01-001'))]));
      expect(z.first.startsWith('Kartennummer;Name;Set;'), isTrue);
      expect(z.first.endsWith(';Alt-Art;Ordner-ID;Preiswahl'), isTrue);
    });

    test('Dubletten werden zu einer Zeile mit Anzahl zusammengefasst', () {
      final c = karte('OP01-001');
      final z = zeilen(csv([eintrag(c), eintrag(c), eintrag(c)]));
      expect(z.length, 2, reason: 'Kopfzeile plus eine Kartenzeile');
      final felder = z[1].split(';');
      expect(felder[6], '3');
      expect(felder[7], '1,50');
      expect(felder[8], '4,50');
    });

    test('dieselbe Karte in zwei Ordnern ergibt ZWEI Zeilen', () {
      final c = karte('OP01-001');
      final z = zeilen(csv([
        eintrag(c),
        eintrag(c),
        eintrag(c, folder: 'f2'),
      ]));

      expect(z.length, 3, reason: 'Kopfzeile plus je eine Zeile pro Ordner');
      final ordner = z.skip(1).map((zeile) => zeile.split(';')[9]).toList();
      expect(ordner, containsAll(['Meine Sammlung', 'Doppelte']));

      final anzahlen = z.skip(1).map((zeile) => zeile.split(';')[6]).toList()..sort();
      expect(anzahlen, ['1', '2']);
    });

    test('Ordner-ID wird mitgeschrieben, nicht nur der Name', () {
      final z = zeilen(csv([eintrag(karte('OP01-001'), folder: 'f2')]));
      expect(z[1].split(';')[13], 'f2');
    });

    test('Alt-Art wird ausgewiesen', () {
      final z = zeilen(csv([
        eintrag(karte('OP01-001')),
        eintrag(karte('OP01-001-ALT', alt: true)),
      ]));
      final werte = {for (final zeile in z.skip(1)) zeile.split(';')[0]: zeile.split(';')[12]};
      expect(werte['OP01-001'], 'nein');
      expect(werte['OP01-001-ALT'], 'ja');
    });

    test('die gewaehlte Preisversion wird mitgeschrieben', () {
      final z = zeilen(csv([eintrag(karte('OP01-001'))], choiceOf: (_) => 4));
      expect(z[1].split(';')[14], '4');
    });

    test('ohne gewaehlte Version bleibt die Spalte leer', () {
      final z = zeilen(csv([eintrag(karte('OP01-001'))]));
      expect(z[1].split(';')[14], '');
    });

    test('Semikolon und Anfuehrungszeichen im Namen werden gequotet', () {
      final z = zeilen(csv([eintrag(karte('OP01-001', name: 'Zoro; der "Beste"'))]));
      expect(z[1].contains('"Zoro; der ""Beste"""'), isTrue);
    });

    test('Erkennungsart wird in Klartext uebersetzt', () {
      final z = zeilen(csv([
        eintrag(karte('OP01-001'), how: 'number+name'),
        eintrag(karte('OP02-002'), how: 'import'),
        eintrag(karte('OP03-003'), how: 'number'),
      ]));
      final werte = {for (final zeile in z.skip(1)) zeile.split(';')[0]: zeile.split(';')[10]};
      expect(werte['OP01-001'], 'Nummer + Name');
      expect(werte['OP02-002'], 'Importiert');
      expect(werte['OP03-003'], 'Nummer');
    });

    test('leere Sammlung ergibt nur die Kopfzeile', () {
      expect(zeilen(csv([])).length, 1);
    });

    test('der Preisstand steht als Hinweiszeile obenan', () {
      final inhalt = CollectionExport.buildCsv(
        entries: [eintrag(karte('OP01-001'))],
        priceOf: (_) => 1,
        folderName: (_) => 'Meine Sammlung',
        priceAsOf: '2026-11-12',
      );
      expect(zeilen(inhalt).first, startsWith('# One Piece Scanner'));
      expect(zeilen(inhalt).first, contains('2026-11-12'));
    });
  });

  group('Sicherungsdatei', () {
    test('der gespeicherte Zustand wird unveraendert eingebettet', () {
      final roh = jsonEncode({
        'v': 2,
        'scans': [
          {'id': 'OP01-001', 'folder': 'default', 'how': 'number', 'at': 1700}
        ],
        'priceChoice': {'OP01-001': 2},
      });

      final sicherung = jsonDecode(
        CollectionExport.buildBackupJson(roh, at: DateTime.utc(2026, 11, 13)),
      ) as Map<String, dynamic>;

      expect(sicherung['kind'], 'collection-backup');
      expect(sicherung['app'], 'onepiece-scanner');
      expect(sicherung['exportedAt'], '2026-11-13T00:00:00.000Z');
      expect(jsonEncode(sicherung['state']), jsonEncode(jsonDecode(roh)));
    });

    test('auch ein unlesbarer Stand wird mitgenommen statt verworfen', () {
      final sicherung = jsonDecode(CollectionExport.buildBackupJson('{kaputt'))
          as Map<String, dynamic>;
      expect(sicherung['state'], '{kaputt');
    });
  });
}
