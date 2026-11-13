import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/collection_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Sammlung des Nutzers liegt nur an einer einzigen Stelle auf dem Geraet.
/// Geht sie dort verloren, ist sie weg - es gibt keine zweite Quelle.
///
/// Diese Tests sichern genau das ab: dass nichts stillschweigend verschwindet,
/// auch nicht bei beschaedigten Daten, unbekannten Karten-IDs oder einem
/// fehlgeschlagenen Import.
void main() {
  StoredScan scan(String id, {String folder = 'default', String how = 'number', int at = 1000}) =>
      StoredScan(
        cardId: id,
        folderId: folder,
        how: how,
        at: DateTime.fromMillisecondsSinceEpoch(at),
      );

  group('Einlesen', () {
    test('vollstaendiger Zustand wird uebernommen', () {
      final state = CollectionStore.parse(jsonEncode({
        'folders': [
          {'id': 'default', 'name': 'Meine Sammlung'},
          {'id': 'f2', 'name': 'Doppelte'},
        ],
        'active': 'f2',
        'scans': [
          {'id': 'OP01-001', 'folder': 'default', 'how': 'number', 'at': 1700},
          {'id': 'OP01-001-ALT', 'folder': 'f2', 'how': 'number+name', 'at': 1800},
        ],
        'priceChoice': {'OP01-001': 3},
      }));

      expect(state, isNotNull);
      expect(state!.folders.length, 2);
      expect(state.activeFolderId, 'f2');
      expect(state.scans.length, 2);
      expect(state.scans[1].cardId, 'OP01-001-ALT');
      expect(state.priceChoice['OP01-001'], 3);
      expect(state.loadFailed, isFalse);
    });

    test('kaputtes JSON ergibt null statt eines leeren Zustands', () {
      expect(CollectionStore.parse('{kein json'), isNull);
      expect(CollectionStore.parse(''), isNull);
      expect(CollectionStore.parse('[]'), isNull);
    });

    test('unlesbare Eintraege gehen nicht verloren, sondern werden aufbewahrt', () {
      final state = CollectionStore.parse(jsonEncode({
        'scans': [
          {'id': 'OP01-001'},
          {'folder': 'default'}, // ohne id - nicht lesbar
        ],
      }));

      expect(state!.scans.length, 1);
      expect(state.unreadableScans.length, 1);
      expect(state.unreadableScans.first['folder'], 'default');
    });

    test('aufbewahrte Eintraege ueberstehen einen Speicherdurchlauf', () {
      final erst = CollectionStore.parse(jsonEncode({
        'scans': [
          {'id': 'OP01-001'},
          {'kaputt': true},
        ],
      }))!;

      final wieder = CollectionStore.parse(CollectionStore.encode(erst))!;
      expect(wieder.scans.length, 1);
      expect(wieder.unreadableScans.length, 1);
      expect(wieder.unreadableScans.first['kaputt'], true);
    });

    test('Preisauswahl aus einer frueheren Fassung wird als Betrag erkannt', () {
      final state = CollectionStore.parse(jsonEncode({
        'scans': [
          {'id': 'OP01-001'}
        ],
        'prices': {'OP01-001': 12.5},
      }))!;

      expect(state.legacyPriceAmounts['OP01-001'], 12.5);
      expect(state.priceChoice, isEmpty);
    });
  });

  group('Laden vom Geraet', () {
    test('beschaedigte Daten werden gesichert statt verworfen', () async {
      SharedPreferences.setMockInitialValues({'collection_v2': '{halb kaputt'});

      final state = await CollectionStore.load();
      expect(state.loadFailed, isTrue, reason: 'Der Fehler muss sichtbar gemacht werden');
      expect(state.scans, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      final gesichert = prefs.getKeys().where((k) => k.startsWith('collection_v2_broken_'));
      expect(gesichert, hasLength(1), reason: 'Der Rohtext muss erhalten bleiben');
      expect(prefs.getString(gesichert.first), '{halb kaputt');
    });

    test('die Uebernahme aus der Vorversion funktioniert weiterhin', () async {
      SharedPreferences.setMockInitialValues({
        'scanned_cards_v1': jsonEncode([
          {'id': 'OP01-001', 'how': 'number', 'at': 1700},
          {'id': 'OP02-002', 'how': 'number+name', 'at': 1800},
        ]),
      });

      final state = await CollectionStore.load();
      expect(state.scans.length, 2);
      expect(state.scans.first.cardId, 'OP01-001');
      expect(state.activeFolderId, CollectionStore.defaultFolderId);
      expect(state.loadFailed, isFalse);
    });

    test('ohne gespeicherte Daten entsteht ein leerer Standardzustand', () async {
      SharedPreferences.setMockInitialValues({});

      final state = await CollectionStore.load();
      expect(state.scans, isEmpty);
      expect(state.folders.single.id, CollectionStore.defaultFolderId);
      expect(state.loadFailed, isFalse);
    });

    test('Speichern und wieder laden ergibt denselben Stand', () async {
      SharedPreferences.setMockInitialValues({});

      await CollectionStore.save(CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: [scan('OP01-001'), scan('OP01-001'), scan('OP05-003', folder: 'f2')],
        priceChoice: const {'OP01-001': 2},
      ));

      final state = await CollectionStore.load();
      expect(state.scans.length, 3);
      expect(state.priceChoice['OP01-001'], 2);
    });
  });

  group('Sicherung und Wiederherstellung', () {
    test('Import ersetzt den Stand und legt den bisherigen zur Seite', () async {
      SharedPreferences.setMockInitialValues({});
      await CollectionStore.save(CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: [scan('OP01-001')],
      ));

      final neu = jsonEncode({
        'scans': [
          {'id': 'OP09-001'},
          {'id': 'OP09-002'},
        ],
      });
      expect(await CollectionStore.importRaw(neu), isTrue);

      final danach = await CollectionStore.load();
      expect(danach.scans.length, 2);
      expect(await CollectionStore.backupTime(), isNotNull);

      expect(await CollectionStore.restoreBackup(), isTrue);
      final zurueck = await CollectionStore.load();
      expect(zurueck.scans.single.cardId, 'OP01-001');
      expect(await CollectionStore.backupTime(), isNull);
    });

    test('eine leere Sicherung wird abgelehnt, statt die Sammlung zu loeschen', () async {
      SharedPreferences.setMockInitialValues({});
      await CollectionStore.save(CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: [scan('OP01-001')],
      ));

      expect(await CollectionStore.importRaw('{}'), isFalse);
      expect(await CollectionStore.importRaw(jsonEncode({'scans': []})), isFalse);
      expect(await CollectionStore.importRaw('kein json'), isFalse);

      final unveraendert = await CollectionStore.load();
      expect(unveraendert.scans.single.cardId, 'OP01-001',
          reason: 'Eine abgelehnte Datei darf nichts anfassen');
    });

    test('der Rohtext der Sicherung entspricht dem Gespeicherten', () async {
      SharedPreferences.setMockInitialValues({});
      final state = CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: [scan('OP01-001')],
      );
      await CollectionStore.save(state);

      expect(await CollectionStore.exportRaw(), CollectionStore.encode(state));
    });

    test('ohne Sicherung gibt es nichts rueckgaengig zu machen', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await CollectionStore.restoreBackup(), isFalse);
      expect(await CollectionStore.backupTime(), isNull);
    });
  });
}
