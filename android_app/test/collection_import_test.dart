import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_matcher.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/collection_export.dart';
import 'package:onepiece_scanner/collection_import.dart';
import 'package:onepiece_scanner/collection_view.dart';
import 'package:onepiece_scanner/deck_model.dart';

/// Ein Import, der still das Falsche tut, ist schlimmer als gar keiner: Die
/// Sammlung sieht danach plausibel aus, stimmt aber nicht mehr.
///
/// Diese Tests halten fest, was aus fremden Listen herausgelesen werden muss -
/// und vor allem, dass nicht zugeordnete Zeilen sichtbar bleiben, statt
/// stillschweigend zu verschwinden.
void main() {
  OpCard karte(
    String id, {
    String name = 'Testkarte',
    bool alt = false,
    int? idProduct,
  }) =>
      OpCard(
        id: id,
        baseId: alt ? id.replaceAll('-ALT', '') : id,
        alt: alt,
        name: name,
        rarity: 'R',
        cardType: 'Character',
        color: 'Red',
        effect: '',
        price: idProduct == null
            ? null
            : CardPrice(
                amount: 1.5,
                currency: 'EUR',
                basis: 'trend',
                source: 'cardmarket',
                asOf: '2026-11-12',
                idProduct: idProduct,
              ),
      );

  final matcher = CardMatcher([
    karte('OP01-001', name: 'Roronoa Zoro', idProduct: 690368),
    karte('OP01-001-ALT', name: 'Roronoa Zoro', alt: true, idProduct: 690369),
    karte('OP05-003', name: 'Nur Alt', alt: false),
    karte('ST01-002', name: 'Starter Karte', idProduct: 700001),
    karte('EB01-001', name: 'Extra Booster'),
    karte('PRB01-001', name: 'Premium Booster'),
    karte('P-001', name: 'Promo Karte'),
  ]);

  ImportResult lies(String text, {ImportFormat? alsFormat}) =>
      CollectionImport.read(text, matcher: matcher, alsFormat: alsFormat);

  group('Format erkennen', () {
    test('eigene Sicherungsdatei', () {
      final text = CollectionExport.buildBackupJson(jsonEncode({
        'scans': [
          {'id': 'OP01-001', 'folder': 'default'}
        ]
      }));
      expect(CollectionImport.detect(text).$1, ImportFormat.sicherung);
    });

    test('eigene CSV', () {
      const text = 'Kartennummer;Name;Set;Anzahl\nOP01-001;Zoro;OP01;2\n';
      expect(CollectionImport.detect(text).$1, ImportFormat.eigeneCsv);
    });

    test('eigene CSV auch mit vorangestellter Hinweiszeile', () {
      const text = '# One Piece Scanner – Stand 2026-11-12\n'
          'Kartennummer;Name;Set;Anzahl\nOP01-001;Zoro;OP01;2\n';
      expect(CollectionImport.detect(text).$1, ImportFormat.eigeneCsv);
    });

    test('Cardmarket-Export', () {
      const text = 'idArticle;idProduct;English Name;Exp.;Condition;Language;isFoil;Quantity\n'
          '1;690368;Roronoa Zoro (OP01-001);OP01;NM;1;false;2\n';
      expect(CollectionImport.detect(text).$1, ImportFormat.cardmarketCsv);
    });

    test('Deckliste als Text', () {
      expect(CollectionImport.detect('4xOP01-001 2xST01-002').$1, ImportFormat.textListe);
    });

    test('Nummernliste als Text', () {
      expect(CollectionImport.detect('OP01-001\nST01-002\n').$1, ImportFormat.textListe);
    });

    test('Fliesstext ohne Nummern gilt als unbekannt', () {
      final erkannt = CollectionImport.detect('Hallo, das ist nur ein Brief.');
      expect(erkannt.$1, ImportFormat.unbekannt);
    });

    test('leere Datei gilt als unbekannt', () {
      expect(CollectionImport.detect('   ').$1, ImportFormat.unbekannt);
    });

    test('das Format laesst sich ueberstimmen', () {
      final r = lies('OP01-001;irgendwas', alsFormat: ImportFormat.textListe);
      expect(r.format, ImportFormat.textListe);
      expect(r.sicher, isTrue);
    });
  });

  group('Kartennummern zuordnen', () {
    OpCard? aufgeloest(String roh) => CollectionImport.resolve(roh, matcher).card;

    test('normale Schreibweise', () => expect(aufgeloest('OP01-001')?.id, 'OP01-001'));
    test('kleingeschrieben', () => expect(aufgeloest('op01-001')?.id, 'OP01-001'));
    test('ohne fuehrende Nullen', () => expect(aufgeloest('OP1-1')?.id, 'OP01-001'));
    test('in Klammern', () => expect(aufgeloest('(OP01-001)')?.id, 'OP01-001'));
    test('mit Leerzeichen um den Strich', () => expect(aufgeloest('OP01 - 001')?.id, 'OP01-001'));
    test('mit Punkt statt Strich', () => expect(aufgeloest('OP01.001')?.id, 'OP01-001'));
    test('Gedankenstrich statt Bindestrich', () => expect(aufgeloest('OP01–001')?.id, 'OP01-001'));

    test('Alt-Art in verschiedenen Schreibweisen', () {
      expect(aufgeloest('OP01-001-ALT')?.id, 'OP01-001-ALT');
      expect(aufgeloest('OP01-001 ALT')?.id, 'OP01-001-ALT');
      expect(aufgeloest('OP01-001 (Alt Art)')?.id, 'OP01-001-ALT');
    });

    test('ohne Alt-Kennzeichnung kommt die Normalversion', () {
      expect(aufgeloest('OP01-001')?.alt, isFalse);
    });

    test('OCR-Verwechslung von O und Null im Praefix', () {
      final treffer = CollectionImport.resolve('OPO1-001', matcher);
      expect(treffer.card?.id, 'OP01-001');
      expect(treffer.hinweis, contains('OP01-001'));
    });

    test('alle Praefixe des Katalogs', () {
      expect(aufgeloest('ST01-002')?.id, 'ST01-002');
      expect(aufgeloest('EB01-001')?.id, 'EB01-001');
      expect(aufgeloest('PRB01-001')?.id, 'PRB01-001');
      expect(aufgeloest('P-001')?.id, 'P-001');
    });

    test('es gibt einen Hinweis, wenn korrigiert werden musste', () {
      expect(CollectionImport.resolve('OP1-1', matcher).hinweis, isNotNull);
      expect(CollectionImport.resolve('OP01-001', matcher).hinweis, isNull);
    });

    test('Unsinn wird nicht zugeordnet', () {
      expect(aufgeloest('Shanks Promo 2023'), isNull);
      expect(aufgeloest('ZZ99-999'), isNull);
      expect(aufgeloest(''), isNull);
    });
  });

  group('Textlisten', () {
    int mengeVon(String text, String id) => lies(text)
        .treffer
        .where((z) => z.card!.id == id)
        .fold(0, (s, z) => s + z.anzahl);

    test('Deckliste im ueblichen Format', () {
      final r = lies('4xOP01-001 2xST01-002 1xEB01-001');
      expect(r.treffer.length, 3);
      expect(mengeVon('4xOP01-001 2xST01-002 1xEB01-001', 'OP01-001'), 4);
      expect(mengeVon('4xOP01-001 2xST01-002 1xEB01-001', 'ST01-002'), 2);
    });

    test('Menge mit Leerzeichen', () {
      expect(mengeVon('4x OP01-001', 'OP01-001'), 4);
      expect(mengeVon('4 x OP01-001', 'OP01-001'), 4);
    });

    test('Menge hinter der Nummer', () {
      expect(mengeVon('OP01-001 x3', 'OP01-001'), 3);
      expect(mengeVon('OP01-001 *3', 'OP01-001'), 3);
    });

    test('Mal-Zeichen aus kopiertem Webtext', () {
      expect(mengeVon('OP01-001 ×3', 'OP01-001'), 3);
      expect(mengeVon('3×OP01-001', 'OP01-001'), 3);
    });

    test('blanke Zahl direkt davor', () {
      expect(mengeVon('3 OP01-001', 'OP01-001'), 3);
    });

    test('ohne Angabe gilt eine Karte', () {
      expect(mengeVon('OP01-001', 'OP01-001'), 1);
    });

    test('eine Zahl irgendwo in der Zeile zaehlt nicht als Menge', () {
      expect(mengeVon('Gekauft 2023 fuer 12 Euro: OP01-001', 'OP01-001'), 1);
    });

    test('dieselbe Nummer mehrfach ergibt die Summe', () {
      expect(mengeVon('2xOP01-001\n2xOP01-001', 'OP01-001'), 4);
    });

    test('eine Nummer je Zeile', () {
      final r = lies('OP01-001\nST01-002\nEB01-001');
      expect(r.treffer.length, 3);
      expect(r.kartenAnzahl, 3);
    });

    test('Ueberschriften stoeren nicht', () {
      final r = lies('Leader:\n1xOP01-001\n\nCharacter:\n4xST01-002');
      expect(r.fehler, isEmpty);
      expect(r.kartenAnzahl, 5);
    });

    test('Zeilen ohne Nummer werden als Fehler ausgewiesen, nicht verschluckt', () {
      final r = lies('4xOP01-001\nShanks Promo von 2023');
      expect(r.treffer.length, 1);
      expect(r.fehler.length, 1);
      expect(r.fehler.single.roh, 'Shanks Promo von 2023');
      expect(r.fehler.single.zeile, 2);
    });

    test('Stueckzahl wird gekappt und das wird gesagt', () {
      final r = lies('9999xOP01-001');
      expect(r.treffer.single.anzahl, CollectionImport.maxProZeile);
      expect(r.warnungen.any((w) => w.contains('Stückzahl')), isTrue);
    });

    test('eine Deckliste wird als solche benannt', () {
      final r = lies('4xOP01-001 3xST01-002 2xEB01-001');
      expect(r.warnungen.any((w) => w.contains('Deckliste')), isTrue);
    });

    test('auf der strengen Form stimmt der Import mit Deck.parseCardList ueberein', () {
      // Der Deck-Parser bleibt absichtlich unangetastet - er bedient die
      // Deck-Pipeline und ist auf ein maschinell erzeugtes Format zugeschnitten.
      // Dieser Test haelt fest, dass beide auf dieser Form dasselbe liefern.
      const text = '4xOP01-001 1xST01-002 2xEB01-001';

      final ausDeck = {for (final c in Deck.parseCardList(text)) c.id: c.qty};
      final ausImport = <String, int>{};
      for (final z in lies(text).treffer) {
        ausImport[z.card!.id] = (ausImport[z.card!.id] ?? 0) + z.anzahl;
      }

      expect(ausImport, ausDeck);
    });

    test('woran Deck.parseCardList scheitert, kommt der Import durch', () {
      // Genau diese Schreibweisen sind der Grund, warum es einen zweiten,
      // toleranteren Parser gibt statt einer Aenderung am bestehenden.
      for (final form in ['4x OP01-001', 'OP01-001 x4', 'OP01-001 ×4', '4 OP01-001']) {
        expect(Deck.parseCardList(form).fold<int>(0, (s, c) => s + c.qty), isNot(4),
            reason: '$form sollte den Deck-Parser ueberfordern');
        expect(mengeVon(form, 'OP01-001'), 4, reason: '$form muss der Import koennen');
      }
    });
  });

  group('Eigene CSV', () {
    test('Spalten werden ueber den Namen gelesen, nicht ueber die Position', () {
      const text = 'Name;Anzahl;Kartennummer;Ordner\n'
          'Zoro;3;OP01-001;Doppelte\n';
      final r = lies(text);
      expect(r.treffer.single.card!.id, 'OP01-001');
      expect(r.treffer.single.anzahl, 3);
      expect(r.treffer.single.ordnerName, 'Doppelte');
    });

    test('Ordner-ID und Preiswahl werden uebernommen', () {
      const text = 'Kartennummer;Anzahl;Ordner;Ordner-ID;Preiswahl\n'
          'OP01-001;1;Doppelte;f2;4\n';
      final zeile = lies(text).treffer.single;
      expect(zeile.ordnerId, 'f2');
      expect(zeile.preiswahl, 4);
    });

    test('fehlende Anzahl bedeutet eine Karte', () {
      const text = 'Kartennummer;Name\nOP01-001;Zoro\n';
      expect(lies(text).treffer.single.anzahl, 1);
    });

    test('auch die alte CSV aus v0.7.0 wird gelesen', () {
      // Wichtig fuer den Umstieg: Wer vor dem Update noch mit der alten Fassung
      // exportiert hat, muss diese Datei notfalls wieder einlesen koennen. Ihr
      // fehlen die technischen Spalten Ordner-ID und Preiswahl.
      const alt = '# One Piece Scanner – Sammlung, Preise nach Cardmarket, Stand 2026-11-12\n'
          'Kartennummer;Name;Set;Seltenheit;Kartentyp;Farbe;Anzahl;Einzelpreis;'
          'Gesamtpreis;Ordner;Erkannt über;Zuletzt gescannt\n'
          'OP01-001;Roronoa Zoro;OP01;L;Leader;Red;3;1,87;5,61;Meine Sammlung;Nummer;12.11.2026\n'
          'ST01-002;Starter Karte;ST01;C;Character;Red;1;0,15;0,15;Doppelte;Nummer + Name;12.11.2026\n';

      final r = lies(alt);
      expect(r.format, ImportFormat.eigeneCsv);
      expect(r.kartenAnzahl, 4);
      expect(r.fehler, isEmpty);

      final zoro = r.treffer.firstWhere((z) => z.card!.id == 'OP01-001');
      expect(zoro.anzahl, 3);
      expect(zoro.ordnerName, 'Meine Sammlung');
      expect(zoro.ordnerId, isNull, reason: 'die alte Datei hat keine Ordner-ID');
      expect(zoro.preiswahl, isNull);
    });
  });

  group('Cardmarket-Export', () {
    const kopf = 'idArticle;idProduct;English Name;Exp.;Condition;Language;isFoil;isPlayset;Quantity\n';

    test('die Produktnummer trifft die Druckvariante genau', () {
      final r = lies('$kopf' '1;690369;Roronoa Zoro;OP01;NM;1;false;false;2\n');
      expect(r.treffer.single.card!.id, 'OP01-001-ALT',
          reason: '690369 ist die Alt-Art, 690368 die Normalversion');
      expect(r.treffer.single.anzahl, 2);
    });

    test('ohne Produktnummer hilft die Nummer im Produktnamen', () {
      final r = lies('$kopf' '1;;Roronoa Zoro (OP01-001);OP01;NM;1;false;false;1\n');
      expect(r.treffer.single.card!.id, 'OP01-001');
      expect(r.treffer.single.hinweis, contains('Namen'));
    });

    test('ein Name ohne Nummer wird nicht geraten', () {
      final r = lies('$kopf' '1;;Irgendeine Karte;OP01;NM;1;false;false;1\n');
      expect(r.treffer, isEmpty);
      expect(r.fehler.single.roh, 'Irgendeine Karte');
    });

    test('Playset vervierfacht und wird gemeldet', () {
      final r = lies('$kopf' '1;690368;Roronoa Zoro;OP01;NM;1;false;true;2\n');
      expect(r.treffer.single.anzahl, 8);
      expect(r.warnungen.any((w) => w.contains('Playset')), isTrue);
    });

    test('es wird gesagt, was nicht uebernommen werden kann', () {
      final r = lies('$kopf' '1;690368;Roronoa Zoro;OP01;NM;1;false;false;1\n');
      expect(r.warnungen.any((w) => w.contains('Zustand')), isTrue);
    });
  });

  group('Sicherungsdatei', () {
    test('wird vollstaendig gelesen und haelt den Rohzustand bereit', () {
      final zustand = jsonEncode({
        'v': 2,
        'folders': [
          {'id': 'default', 'name': 'Meine Sammlung'},
          {'id': 'f2', 'name': 'Doppelte'},
        ],
        'active': 'default',
        'scans': [
          {'id': 'OP01-001', 'folder': 'default', 'how': 'number', 'at': 1700},
          {'id': 'OP01-001', 'folder': 'default', 'how': 'number', 'at': 1701},
          {'id': 'ST01-002', 'folder': 'f2', 'how': 'number', 'at': 1702},
        ],
        'priceChoice': {'OP01-001': 2},
      });

      final r = lies(CollectionExport.buildBackupJson(zustand));
      expect(r.format, ImportFormat.sicherung);
      expect(r.kartenAnzahl, 3);
      expect(r.sicherungRoh, isNotNull);
      expect(jsonDecode(r.sicherungRoh!)['priceChoice']['OP01-001'], 2);

      final zoro = r.treffer.firstWhere((z) => z.card!.id == 'OP01-001');
      expect(zoro.anzahl, 2);
      expect(zoro.ordnerName, 'Meine Sammlung');
    });

    test('unbekannte Karten werden benannt, bleiben aber in der Sicherung', () {
      final zustand = jsonEncode({
        'scans': [
          {'id': 'OP01-001', 'folder': 'default'},
          {'id': 'XY99-999', 'folder': 'default'},
        ],
      });
      final r = lies(CollectionExport.buildBackupJson(zustand));
      expect(r.fehler.single.roh, 'XY99-999');
      expect(r.warnungen.any((w) => w.contains('Katalog')), isTrue);
      expect(r.sicherungRoh, contains('XY99-999'));
    });

    test('eine kaputte Sicherungsdatei fuehrt zu einer Meldung, nicht zum Absturz', () {
      final r = lies('{"kind":"collection-backup","state":{}}',
          alsFormat: ImportFormat.sicherung);
      expect(r.treffer, isEmpty);
      expect(r.warnungen, isNotEmpty);
    });
  });

  group('Rundlauf Export zu Import', () {
    test('eine exportierte CSV wird vollstaendig wieder eingelesen', () {
      final zoro = karte('OP01-001', name: 'Roronoa Zoro');
      final starter = karte('ST01-002', name: 'Starter Karte');

      CollectionEntry e(OpCard c, String folder) => CollectionEntry(
            card: c,
            folderId: folder,
            how: 'number',
            at: DateTime.fromMillisecondsSinceEpoch(1700),
          );

      final entries = [
        e(zoro, 'default'),
        e(zoro, 'default'),
        e(zoro, 'f2'), // dieselbe Karte in einem zweiten Ordner
        e(starter, 'f2'),
      ];

      final csv = CollectionExport.buildCsv(
        entries: entries,
        priceOf: (_) => 1.5,
        folderName: (id) => id == 'default' ? 'Meine Sammlung' : 'Doppelte',
        choiceOf: (_) => null,
      );

      final r = lies(csv);
      expect(r.format, ImportFormat.eigeneCsv);
      expect(r.kartenAnzahl, 4, reason: 'keine Karte darf unterwegs verlorengehen');

      final nachOrdner = <String, int>{};
      for (final z in r.treffer) {
        nachOrdner[z.ordnerId!] = (nachOrdner[z.ordnerId] ?? 0) + z.anzahl;
      }
      expect(nachOrdner['default'], 2);
      expect(nachOrdner['f2'], 2);
    });

    test('die Preiswahl ueberlebt den Rundlauf', () {
      final csv = CollectionExport.buildCsv(
        entries: [
          CollectionEntry(
            card: karte('OP01-001'),
            folderId: 'default',
            how: 'number',
            at: DateTime.fromMillisecondsSinceEpoch(1700),
          )
        ],
        priceOf: (_) => 1.5,
        folderName: (_) => 'Meine Sammlung',
        choiceOf: (_) => 5,
      );
      expect(lies(csv).treffer.single.preiswahl, 5);
    });
  });
}
