import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/price_store.dart';

/// Die App laedt die Preise taeglich aus dem Repository nach. Diese Tests pruefen das
/// Einlesen - inklusive der Faelle, in denen die Datei fehlerhaft oder unvollstaendig ist.
/// Dort darf die App nicht abstuerzen, sondern muss beim vorherigen Stand bleiben.
void main() {
  String build(Map<String, dynamic> map) => jsonEncode(map);

  group('Preisdatei einlesen', () {
    test('vollstaendige Datei wird uebernommen', () {
      final parsed = LivePrices.parse(build({
        'asOf': '2026-10-06',
        'prices': {'OP01-001': 1.87, 'OP01-001-ALT': 610.16},
        'options': {
          'OP01-001': [1.87, 7.05, 610.16],
        },
      }));
      expect(parsed, isNotNull);
      expect(parsed!.asOf, '2026-10-06');
      expect(parsed.byCardId['OP01-001'], 1.87);
      expect(parsed.byCardId['OP01-001-ALT'], 610.16);
      expect(parsed.optionsByBaseId['OP01-001'], [1.87, 7.05, 610.16]);
      expect(parsed.isEmpty, isFalse);
    });

    test('ganze Zahlen werden als Betrag gelesen', () {
      final parsed = LivePrices.parse(build({
        'asOf': '2026-10-06',
        'prices': {'OP01-002': 3},
      }));
      expect(parsed!.byCardId['OP01-002'], 3.0);
    });

    test('Datei ohne Preise gilt als unbrauchbar', () {
      expect(LivePrices.parse(build({'asOf': '2026-10-06', 'prices': {}})), isNull);
    });

    test('kaputtes JSON stuerzt nicht ab', () {
      expect(LivePrices.parse('{das ist kein json'), isNull);
    });

    test('unerwarteter Aufbau stuerzt nicht ab', () {
      expect(LivePrices.parse('[1,2,3]'), isNull);
      expect(LivePrices.parse(build({'prices': 'text statt objekt'})), isNull);
    });

    test('ungueltige Einzelwerte werden uebersprungen, der Rest bleibt', () {
      final parsed = LivePrices.parse(build({
        'asOf': '2026-10-06',
        'prices': {'OP01-001': 1.87, 'kaputt': null, 'negativ': -5, 'null': 0},
      }));
      expect(parsed!.byCardId.keys, ['OP01-001']);
    });

    test('Versionslisten mit nur einem Eintrag werden verworfen', () {
      // Eine Liste mit einem Wert waere redundant zum Preis selbst - und zum Umschalten nutzlos.
      final parsed = LivePrices.parse(build({
        'prices': {'OP01-001': 1.87},
        'options': {
          'OP01-001': [1.87],
          'OP01-002': [0.5, 9.9],
        },
      }));
      expect(parsed!.optionsByBaseId.containsKey('OP01-001'), isFalse);
      expect(parsed.optionsByBaseId['OP01-002'], [0.5, 9.9]);
    });

    test('fehlendes Datum ist kein Fehler', () {
      final parsed = LivePrices.parse(build({
        'prices': {'OP01-001': 1.87},
      }));
      expect(parsed!.asOf, '');
    });
  });
}
