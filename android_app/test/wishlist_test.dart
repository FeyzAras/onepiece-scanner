import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_matcher.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/collection_import.dart';
import 'package:onepiece_scanner/collection_store.dart';
import 'package:onepiece_scanner/wishlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Wunschliste ist eine Einkaufsliste mit Geld dahinter. Zaehlt sie doppelt, kauft
/// man doppelt; vergisst sie beim Update, was drinstand, faengt man von vorn an.
void main() {
  OpCard karte(String id, {bool alt = false}) => OpCard(
        id: id,
        baseId: id.replaceAll('-ALT', ''),
        alt: alt,
        name: id,
        rarity: 'R',
        cardType: 'CHARACTER',
        effect: '',
      );

  group('Eintragen', () {
    test('Stern setzen und wieder entfernen', () {
      final w = Wunschliste();
      w.setzen('OP01-001', 1);
      expect(w.anzahl('OP01-001'), 1);
      w.setzen('OP01-001', 0);
      expect(w.enthaelt('OP01-001'), isFalse);
      expect(w.leer, isTrue);
    });

    test('mehrfach hinzufuegen nimmt die groessere Anzahl, nicht die Summe', () {
      final w = Wunschliste();
      w.hinzufuegen({'OP01-002': 1}); // fuer das Set
      w.hinzufuegen({'OP01-002': 3}); // fuer ein Deck
      expect(w.anzahl('OP01-002'), 3, reason: 'drei Exemplare decken beide Zwecke');
      w.hinzufuegen({'OP01-002': 2});
      expect(w.anzahl('OP01-002'), 3, reason: 'eine kleinere Anzahl ueberschreibt nichts');
    });

    test('hinzufuegen meldet, wie viele Eintraege sich geaendert haben', () {
      final w = Wunschliste();
      expect(w.hinzufuegen({'A-001': 1, 'A-002': 2}), 2);
      expect(w.hinzufuegen({'A-001': 1, 'A-002': 2}), 0, reason: 'nichts Neues');
      expect(w.hinzufuegen({'A-001': 4, 'A-003': 0}), 1, reason: 'Anzahl 0 wird ignoriert');
    });

    test('Zaehler fuer Anzeige', () {
      final w = Wunschliste()..laden({'A-001': 4, 'A-002': 1});
      expect(w.verschiedene, 2);
      expect(w.exemplare, 5);
    });

    test('Anzahl ist nach oben begrenzt', () {
      final w = Wunschliste()..setzen('A-001', 500);
      expect(w.anzahl('A-001'), 99);
    });
  });

  group('Abhaken beim Scannen', () {
    test('die gescannte Karte wird heruntergezaehlt und verschwindet bei 0', () {
      final w = Wunschliste()..laden({'OP01-001': 2});
      expect(w.abhaken(karte('OP01-001')), 'OP01-001');
      expect(w.anzahl('OP01-001'), 1);
      w.abhaken(karte('OP01-001'));
      expect(w.enthaelt('OP01-001'), isFalse);
    });

    test('eine Alt-Art erfuellt den Wunsch nach der Normalversion', () {
      final w = Wunschliste()..laden({'OP01-001': 1});
      expect(w.abhaken(karte('OP01-001-ALT', alt: true)), 'OP01-001');
      expect(w.leer, isTrue);
    });

    test('die Normalversion erfuellt den Wunsch nach der Alt-Art nicht', () {
      final w = Wunschliste()..laden({'OP01-001-ALT': 1});
      expect(w.abhaken(karte('OP01-001')), isNull);
      expect(w.anzahl('OP01-001-ALT'), 1, reason: 'wer die Alt-Art sucht, will die Alt-Art');
    });

    test('ist die gescannte Alt-Art selbst gesucht, wird sie zuerst gestrichen', () {
      final w = Wunschliste()..laden({'OP01-001': 1, 'OP01-001-ALT': 1});
      expect(w.abhaken(karte('OP01-001-ALT', alt: true)), 'OP01-001-ALT');
      expect(w.anzahl('OP01-001'), 1);
    });

    test('nicht gesuchte Karten aendern nichts', () {
      final w = Wunschliste()..laden({'OP01-001': 1});
      expect(w.abhaken(karte('ST01-001')), isNull);
      expect(w.exemplare, 1);
    });
  });

  group('Speichern nur bei echten Aenderungen', () {
    test('Laden loest keinen Speichervorgang aus', () {
      var gespeichert = 0;
      final w = Wunschliste(onAenderung: () => gespeichert++);
      w.laden({'A-001': 1});
      expect(gespeichert, 0, reason: 'beim Start darf nichts ueberschrieben werden');
    });

    test('jede echte Aenderung wird gespeichert, wirkungslose nicht', () {
      var gespeichert = 0;
      final w = Wunschliste(onAenderung: () => gespeichert++);
      w.setzen('A-001', 1);
      w.setzen('A-001', 1); // keine Aenderung
      w.hinzufuegen({'A-002': 2});
      w.abhaken(karte('A-002'));
      w.leeren();
      w.leeren(); // schon leer
      expect(gespeichert, 4);
    });
  });

  group('Teilen als Deckliste', () {
    test('Format, sortiert nach Nummer', () {
      expect(Wunschliste.alsDeckliste({'ST01-002': 2, 'OP01-001': 4}), '4xOP01-001\n2xST01-002');
    });

    test('der eigene Import liest die geteilte Liste wieder ein', () {
      final matcher = CardMatcher([karte('OP01-001'), karte('ST01-002')]);
      final text = Wunschliste.alsDeckliste({'OP01-001': 4, 'ST01-002': 2});
      final r = CollectionImport.read(text, matcher: matcher);
      expect(r.format, ImportFormat.textListe);
      expect(r.kartenAnzahl, 6);
      expect(r.fehler, isEmpty);
    });

    test('Kosten mit und ohne Preis', () {
      final k = Wunschliste.kosten(
        {'A-001': 2, 'A-002': 1},
        (id) => karte(id),
        (c) => c.id == 'A-001' ? 1.5 : 0,
      );
      expect(k.summe, closeTo(3.0, 0.001));
      expect(k.ohnePreis, 1);
    });
  });

  group('Gespeichert mit der Sammlung', () {
    test('Wunschliste ueberlebt Speichern und Laden', () async {
      SharedPreferences.setMockInitialValues({});
      await CollectionStore.save(CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: const [],
        wishlist: const {'OP01-001': 3},
      ));
      final s = await CollectionStore.load();
      expect(s.wishlist, {'OP01-001': 3});
    });

    test('aeltere Staende ohne Wunschliste laden weiter', () {
      final s = CollectionStore.parse(jsonEncode({'scans': [{'id': 'OP01-001'}]}))!;
      expect(s.wishlist, isEmpty);
    });

    test('unsinnige Mengen werden verworfen', () {
      final s = CollectionStore.parse(jsonEncode({
        'scans': [],
        'wishlist': {'A-001': 2, 'A-002': 0, 'A-003': -1, 'A-004': 'x'},
      }))!;
      expect(s.wishlist, {'A-001': 2});
    });

    test('die Sicherung enthaelt die Wunschliste', () async {
      SharedPreferences.setMockInitialValues({});
      await CollectionStore.save(CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: const [],
        wishlist: const {'ST01-002': 1},
      ));
      final roh = await CollectionStore.exportRaw();
      expect(jsonDecode(roh!)['wishlist'], {'ST01-002': 1});
    });

    test('eine leere Wunschliste wird gar nicht erst geschrieben', () {
      final roh = CollectionStore.encode(const CollectionState(
        folders: [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: [],
      ));
      expect(jsonDecode(roh).containsKey('wishlist'), isFalse);
    });
  });
}
