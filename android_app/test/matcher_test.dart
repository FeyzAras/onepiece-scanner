import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_matcher.dart';
import 'package:onepiece_scanner/card_model.dart';

/// Prueft die Erkennungslogik gegen den echten Kartenkatalog - ohne Geraet,
/// laeuft direkt auf dem Rechner (`flutter test`).
void main() {
  late CardMatcher matcher;

  setUpAll(() {
    final raw = File('assets/cards.json').readAsStringSync();
    final cards = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(OpCard.fromJson).toList();
    matcher = CardMatcher(cards);
  });

  group('Kartennummer erkennen', () {
    test('Katalog ist geladen', () {
      expect(matcher.cards.length, greaterThan(3000));
    });

    test('sauber gelesene Nummer trifft exakt', () {
      final r = matcher.match('Roronoa Zoro OP01-001 LEADER');
      expect(r.hasMatch, isTrue);
      expect(r.match!.card.id, 'OP01-001');
      expect(r.match!.nameConfirmed, isTrue, reason: 'Name steht auch im Text');
      expect(r.match!.how, 'number+name');
    });

    test('Punkt statt Bindestrich wird toleriert', () {
      expect(matcher.match('blah OP01.001 blah').match?.card.id, 'OP01-001');
    });

    test('typischer OCR-Fehler (P als O gelesen) wird korrigiert', () {
      final r = matcher.match('Supernovas/Straw Hat Crew oo01.001 um');
      expect(r.match?.card.id, 'OP01-001');
    });

    test('Starter-Deck-Nummer wird erkannt', () {
      expect(matcher.match('ST01-013 Roronoa Zoro').match?.card.id, 'ST01-013');
    });

    test('Nummer ohne Namen im Text gilt trotzdem, aber ohne Namensbestaetigung', () {
      final r = matcher.match('irgendein text OP01-001 noch mehr text');
      expect(r.match?.card.id, 'OP01-001');
      expect(r.match?.nameConfirmed, isFalse);
      expect(r.match?.how, 'number');
    });
  });

  group('Ohne Kartennummer wird nichts uebernommen', () {
    // Das war der Fehler in der ersten Fassung: Beim Scannen von "Snake Dance"
    // wurden reihum Gina, Portgas.D.Ace usw. erkannt, weil deren Namen im
    // Effekttext der Karte vorkommen.
    test('Kartenname allein ergibt keinen Treffer', () {
      final r = matcher.match('LEADER Roronoa Zoro Supernovas Straw Hat Crew');
      expect(r.hasMatch, isFalse, reason: 'ohne Nummer darf nichts uebernommen werden');
      expect(r.nameOnlyHint, 'Roronoa Zoro', reason: 'als Hinweis fuer den Nutzer aber gemeldet');
    });

    test('fremder Name im Effekttext loest keinen Treffer aus', () {
      final r = matcher.match('Snake Dance Gib deinem Leader Portgas.D.Ace und Gina Kraft');
      expect(r.hasMatch, isFalse);
    });

    test('wirrer Text liefert weder Treffer noch Hinweis', () {
      final r = matcher.match('zzz qqq wirrer text ohne alles');
      expect(r.hasMatch, isFalse);
      expect(r.nameOnlyHint, isNull);
    });

    test('echter OCR-Rohtext mit lesbarer Nummer wird erkannt', () {
      const realOcr = '''
mm 5000 %
ar " ofiyour; Characters gain caf
- LEADER [A :
Roronoa Zoro rll
Supernovas/Straw Hat Crew oo01.001 um''';
      expect(matcher.match(realOcr).match?.card.id, 'OP01-001');
    });
  });

  group('Cardmarket-Preise', () {
    test('Beispielkarte hat echten Preis', () {
      final card = matcher.byId('OP01-001')!;
      expect(card.price, isNotNull);
      expect(card.price!.amount, greaterThan(0));
      expect(card.price!.currency, 'EUR');
      expect(card.price!.source, 'cardmarket');
      expect(card.price!.asOf, isNotEmpty);
    });

    test('fast alle Karten haben einen Preis', () {
      final withPrice = matcher.cards.where((c) => c.price != null).length;
      expect(withPrice / matcher.cards.length, greaterThan(0.95));
    });
  });
}
