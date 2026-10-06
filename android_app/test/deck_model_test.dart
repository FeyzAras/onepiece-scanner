import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/deck_model.dart';

/// Die Deckdatei nutzt ein kompaktes Format (kurze Schluessel, Kartenliste als Zeichenkette),
/// weil sie sonst mehrere Megabyte gross waere. Diese Tests sichern das Einlesen ab -
/// inklusive der Faelle, in denen die Datei unvollstaendig oder fehlerhaft ist.
void main() {
  group('Kartenliste einlesen', () {
    test('normale Liste', () {
      final cards = Deck.parseCardList('1xOP09-062 4xOP17-113 2xST34-003');
      expect(cards.length, 3);
      expect(cards[0].id, 'OP09-062');
      expect(cards[0].qty, 1);
      expect(cards[1].qty, 4);
      expect(cards[2].id, 'ST34-003');
    });

    test('leere Zeichenkette ergibt keine Karten', () {
      expect(Deck.parseCardList(''), isEmpty);
    });

    test('kaputte Eintraege werden uebersprungen, gueltige bleiben', () {
      final cards = Deck.parseCardList('4xOP01-001 kaputt 0xOP01-002 xOP01-003 2xOP01-004');
      expect(cards.map((c) => c.id), ['OP01-001', 'OP01-004']);
    });
  });

  group('Deck einlesen', () {
    test('kompaktes Format wird verstanden', () {
      final deck = Deck.fromJson({
        'n': 'Robin',
        'l': 'OP09-062',
        'd': '10/4/2026',
        'p': 'Spielername',
        'pl': 'T8',
        's': 'OP17',
        'f': 'jp',
        'c': '1xOP09-062 4xOP17-113',
      });
      expect(deck, isNotNull);
      expect(deck!.name, 'Robin');
      expect(deck.set, 'OP17');
      expect(deck.istJapanisch, isTrue);
      expect(deck.formatLabel, 'JP');
      expect(deck.cardCount, 5);
    });

    test('fehlendes Format gilt als englisch', () {
      final deck = Deck.fromJson({'n': 'X', 's': 'OP01', 'c': '1xOP01-001'});
      expect(deck!.format, 'en');
      expect(deck.istJapanisch, isFalse);
    });

    test('Deck ohne Karten wird verworfen', () {
      expect(Deck.fromJson({'n': 'Leer', 'c': ''}), isNull);
      expect(Deck.fromJson({'n': 'Leer'}), isNull);
    });
  });

  group('Gesamte Deckdatei', () {
    test('die mitgelieferte Datei laesst sich lesen und ist vollstaendig', () {
      final raw = File('assets/decks.json').readAsStringSync();
      final data = DeckData.parse(raw);
      expect(data, isNotNull);
      expect(data!.decks.length, greaterThan(1000));
      expect(data.sourceName, isNotEmpty);

      // Beide Formate und mehrere Sets muessen vertreten sein
      expect(data.decks.any((d) => d.istJapanisch), isTrue);
      expect(data.decks.any((d) => !d.istJapanisch), isTrue);
      expect(data.decks.map((d) => d.set).toSet().length, greaterThan(10));

      // Jedes Deck braucht Karten und einen Leader
      expect(data.decks.every((d) => d.cards.isNotEmpty), isTrue);
      expect(data.decks.where((d) => d.leaderId != null).length / data.decks.length,
          greaterThan(0.95));
    });

    test('je Archetyp bleiben hoechstens fuenf Listen', () {
      final data = DeckData.parse(File('assets/decks.json').readAsStringSync())!;
      final proArchetyp = <String, int>{};
      for (final d in data.decks) {
        final key = '${d.set}|${d.format}|${d.name}';
        proArchetyp[key] = (proArchetyp[key] ?? 0) + 1;
      }
      expect(proArchetyp.values.every((n) => n <= 5), isTrue);
    });

    test('kaputte Datei stuerzt nicht ab', () {
      expect(DeckData.parse('{kein json'), isNull);
      expect(DeckData.parse(jsonEncode({'decks': []})), isNull);
      expect(DeckData.parse('[]'), isNull);
    });
  });
}
