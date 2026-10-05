import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_matcher.dart';
import 'package:onepiece_scanner/card_model.dart';

/// Pruefen die Erkennungslogik gegen den echten Kartenkatalog - ohne Geraet,
/// laeuft direkt auf dem Rechner (`flutter test`).
void main() {
  late CardMatcher matcher;

  setUpAll(() {
    final raw = File('assets/cards.json').readAsStringSync();
    final cards = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(OpCard.fromJson).toList();
    matcher = CardMatcher(cards);
  });

  test('Katalog ist geladen', () {
    expect(matcher.cards.length, greaterThan(3000));
  });

  test('sauber gelesene Kartennummer trifft exakt', () {
    final r = matcher.match('Roronoa Zoro OP01-001 LEADER');
    expect(r, isNotNull);
    expect(r!.card.id, 'OP01-001');
    expect(r.how, 'number');
  });

  test('Punkt statt Bindestrich wird toleriert', () {
    final r = matcher.match('blah OP01.001 blah');
    expect(r?.card.id, 'OP01-001');
  });

  test('typischer OCR-Fehler (P als O gelesen) wird korrigiert', () {
    final r = matcher.match('Supernovas/Straw Hat Crew oo01.001 um');
    expect(r?.card.id, 'OP01-001');
    expect(r?.how, 'number');
  });

  test('echter OCR-Rohtext aus einem Testlauf wird erkannt', () {
    const realOcr = '''
mm 5000 %
ar " ofiyour; Characters gain caf
- LEADER [A :
Roronoa Zoro rll
Supernovas/Straw Hat Crew oo01.001 um''';
    final r = matcher.match(realOcr);
    expect(r?.card.id, 'OP01-001');
  });

  test('Starter-Deck-Nummer wird erkannt', () {
    expect(matcher.match('ST01-013 Roronoa Zoro')?.card.id, 'ST01-013');
  });

  test('Namensabgleich greift, wenn keine Nummer lesbar ist', () {
    final r = matcher.match('LEADER Roronoa Zoro Supernovas Straw Hat Crew');
    expect(r, isNotNull);
    expect(r!.card.name, 'Roronoa Zoro');
    expect(r.how, 'name');
  });

  test('wirrer Text liefert keinen Treffer', () {
    expect(matcher.match('zzz qqq wirrer text ohne alles'), isNull);
  });

  test('echte Cardmarket-Preise sind eingespielt', () {
    final card = matcher.cards.firstWhere((c) => c.id == 'OP01-001');
    expect(card.price, isNotNull);
    expect(card.price!.amount, greaterThan(0));
    expect(card.price!.currency, 'EUR');
    expect(card.price!.source, 'cardmarket');
    expect(card.price!.isReal, isTrue);
    expect(card.price!.asOf, isNotEmpty);
  });

  test('fast alle Karten haben einen Preis', () {
    final withPrice = matcher.cards.where((c) => c.price != null).length;
    expect(withPrice / matcher.cards.length, greaterThan(0.95));
  });
}

