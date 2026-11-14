// Der Test gibt bewusst einen kurzen Bericht aus (wie viele Decks gueltig sind).
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_matcher.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/deck_model.dart';
import 'package:onepiece_scanner/my_decks.dart';

/// Die Regelpruefung gegen die Wirklichkeit: Tausende Decks, die auf Turnieren
/// gespielt wurden. Wer dort platziert war, hatte ein regelkonformes Deck - meldet die
/// App bei ihnen einen Fehler, ist die Regel falsch umgesetzt, nicht das Deck.
void main() {
  final kartenDatei = File('assets/cards.json');
  final deckDatei = File('assets/decks.json');
  if (!kartenDatei.existsSync() || !deckDatei.existsSync()) return;

  final karten = (jsonDecode(kartenDatei.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>()
      .map(OpCard.fromJson)
      .toList();
  final matcher = CardMatcher(karten);
  OpCard? zurNummer(String nr) => matcher.byId(nr) ?? matcher.byId('$nr-ALT');

  final turnierdecks = DeckData.parse(deckDatei.readAsStringSync())?.decks ?? const <Deck>[];

  test('echte Turnierdecks verletzen keine Farb- und Kopienregel', () {
    expect(turnierdecks.length, greaterThan(1000));

    var gueltig = 0, mitUnbekannten = 0;
    final farbFehler = <String>[];
    final kopienFehler = <String>[];
    final kopienOhneErklaerung = <String>[];
    final anzahlFehler = <String>[];
    final ohneLeader = <String>[];
    final typFehler = <String>[];
    final sonderFehler = <String>[];

    for (final t in turnierdecks) {
      final v = DeckText.ausTurnierdeck(t, zurNummer);
      final d = MeinDeck(id: 'x', name: t.name, leaderId: v.leaderId, karten: v.karten, geaendert: DateTime(2026));
      final p = DeckRegeln.pruefen(d, matcher.byId);

      // Fehlt eine Karte im Katalog, ist die Zaehlung nicht aussagekraeftig
      final vollstaendig = t.cards.every((c) => zurNummer(c.id) != null);
      if (!vollstaendig) {
        mitUnbekannten++;
        continue;
      }
      if (p.gueltig) gueltig++;
      if (p.falscheFarbe.isNotEmpty) farbFehler.add('${t.name}: ${p.falscheFarbe.map((k) => k.id).join(',')}');
      if (p.zuViele.isNotEmpty) {
        kopienFehler.add('${t.name}: ${p.zuViele}');
        // Erklaert nur ein doppelter Eintrag in der abgeschriebenen Liste den Fehler?
        // ("4xEB04-011 4xEB04-011") Dann liegt es an der Quelle, nicht an der Regel.
        for (final nummer in p.zuViele.keys) {
          final eintraege = t.cards.where((c) => c.id == nummer).length;
          if (eintraege < 2) kopienOhneErklaerung.add('${t.name}: $nummer');
        }
      }
      if (p.anzahl != 50) anzahlFehler.add('${t.name}: ${p.anzahl}');
      if (p.leader == null) ohneLeader.add('${t.name}: ${v.leaderId}');
      if (p.falscherTyp.isNotEmpty) typFehler.add('${t.name}: ${p.falscherTyp.map((k) => k.id).join(',')}');
      if (p.sonderregelVerstoss.isNotEmpty) {
        sonderFehler.add('${t.name} (${v.leaderId}): ${p.sonderregelVerstoss.map((k) => k.id).join(',')}');
      }
    }

    final geprueft = turnierdecks.length - mitUnbekannten;
    // Bericht fuer die Testausgabe
    print('Turnierdecks: ${turnierdecks.length}, vollstaendig im Katalog: $geprueft, '
        'davon gueltig: $gueltig (${(gueltig / geprueft * 100).toStringAsFixed(1)} %), '
        'Farbfehler: ${farbFehler.length}, Kopienfehler: ${kopienFehler.length}, '
        'Anzahl != 50: ${anzahlFehler.length}, ohne Leader: ${ohneLeader.length}, '
        'falscher Typ: ${typFehler.length}, Leader-Sonderregel: ${sonderFehler.length}');
    for (final f in [
      ...farbFehler.take(5),
      ...kopienFehler.take(5),
      ...anzahlFehler.take(5),
      ...ohneLeader.take(5),
      ...typFehler.take(5),
      ...sonderFehler.take(10),
    ]) {
      print('  $f');
    }

    // Kopiengrenze: Mit der Ausnahme "any number of this card" (5-1-2-4) fiel die Zahl von
    // 37 auf 6. Die restlichen 6 haben alle denselben Grund - dieselbe Nummer steht in der
    // Quelle zweimal in der Liste. Jeder Kopienfehler OHNE diese Erklaerung waere ein
    // Fehler in der Regel.
    expect(kopienOhneErklaerung, isEmpty, reason: 'Kopienregel 5-1-2-3/5-1-2-4 falsch umgesetzt?');

    // Farbfehler: Die verbleibenden Faelle sind Tippfehler in den abgeschriebenen
    // Turnierlisten, keine Regelfehler - etwa ein "Yellow-Purple Pudding"-Deck mit dem
    // rein gelben Leader Kalgara OP08-098 statt Pudding OP08-058 (Zahlendreher), oder ein
    // gelber Momonosuke in einem rot-gruenen Law-Deck. Auf einem Turnier waere das
    // verboten. Deshalb eine Obergrenze statt Null: steigt die Zahl, stimmt etwas an der
    // Regel nicht.
    expect(farbFehler.length, lessThan(geprueft * 0.01),
        reason: 'mehr als 1 % Farbfehler - Farbregel 5-1-2-2 falsch umgesetzt?');
    expect(gueltig / geprueft, greaterThan(0.95));

    // Leader-Sonderregeln (Rayleigh, Imu, Nami P-117): Kein einziges Turnierdeck mit einem
    // dieser Leader darf auffallen - sonst ist die Regel zu streng gelesen.
    expect(sonderFehler, isEmpty, reason: 'Leader-Sonderregel (5-1-2-4) zu streng umgesetzt?');
  });

  test('jede Deckbau-Regel eines Leaders im Katalog wird geprueft', () {
    final mitRegel = <String>{};
    final ungeprueft = <String>[];
    for (final k in karten.where((k) => k.cardType == 'LEADER')) {
      final r = LeaderSonderregel.aus(k);
      if (r == null) continue;
      mitRegel.add(k.baseId);
      if (r.ungeprueft.isNotEmpty) ungeprueft.add('${k.id}: ${r.ungeprueft.join(' / ')}');
    }
    print('Leader mit Deckbau-Regel: ${mitRegel.join(', ')}');
    expect(mitRegel, containsAll(['OP12-001', 'OP13-079', 'P-117']));
    // Bringt ein neues Set eine Regel in anderem Wortlaut, zeigt die App "spielbereit*" mit
    // Vorbehalt. Das ist richtig - aber der Anlass, die Regel einzubauen.
    expect(ungeprueft, isEmpty, reason: 'neue Leader-Regel, die die App noch nicht prueft');
  });
}
