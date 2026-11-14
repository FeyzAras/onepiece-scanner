import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_matcher.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/collection_store.dart';
import 'package:onepiece_scanner/deck_model.dart';
import 'package:onepiece_scanner/my_decks.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ein Deck, das die App als "spielbereit" meldet, muss auf einem Turnier auch erlaubt
/// sein. Gemessen wird an den offiziellen Comprehensive Rules, Version 1.2.1 (5-1-2 ff.).
void main() {
  OpCard karte(
    String id, {
    String typ = 'CHARACTER',
    List<String> farben = const ['Red'],
    int? kosten,
    int? counter,
    String effekt = '',
    List<String> typen = const [],
  }) =>
      OpCard(
        id: id,
        baseId: id.replaceAll('-ALT', ''),
        alt: id.endsWith('-ALT'),
        name: id,
        rarity: 'R',
        cardType: typ,
        colors: farben,
        costLife: kosten,
        counter: counter,
        types: typen,
        effect: effekt,
      );

  final katalog = [
    karte('OP01-001', typ: 'LEADER', kosten: 5),
    karte('OP01-002', typ: 'LEADER', farben: ['Red', 'Green'], kosten: 4),
    karte('OP01-060', typ: 'LEADER', farben: ['Blue'], kosten: 5),
    karte('OP01-013', kosten: 2, counter: 1000),
    karte('OP01-013-ALT', kosten: 2, counter: 1000),
    karte('OP01-014', kosten: 3, counter: 2000),
    karte('OP01-025', farben: ['Green'], kosten: 4, counter: 2000),
    karte('OP01-077', farben: ['Blue'], kosten: 5),
    karte('OP01-090', farben: ['Red', 'Green'], kosten: 6),
    karte('OP01-029', typ: 'EVENT', kosten: 1),
    karte('OP01-039', typ: 'STAGE', farben: ['Green'], kosten: 12),
  ];
  final matcher = CardMatcher(katalog);
  OpCard? von(String id) => matcher.byId(id);

  MeinDeck deck(String? leader, Map<String, int> karten) =>
      MeinDeck(id: 'd', name: 'Test', leaderId: leader, karten: karten, geaendert: DateTime(2026));

  /// 50 rote Karten, regelkonform: 12 Nummern x 4 + 2
  Map<String, int> fuenfzigRote() {
    final m = <String, int>{};
    for (var i = 0; i < 12; i++) {
      m['R-${i.toString().padLeft(3, '0')}'] = 4;
    }
    m['R-012'] = 2;
    return m;
  }

  group('Regeln nach Comprehensive Rules 5-1-2', () {
    final roteKarten = {
      for (var i = 0; i <= 12; i++) 'R-${i.toString().padLeft(3, '0')}': karte('R-${i.toString().padLeft(3, '0')}'),
    };
    OpCard? mitRoten(String id) => roteKarten[id] ?? von(id);

    test('ein Leader und genau 50 passende Karten sind spielbereit', () {
      final p = DeckRegeln.pruefen(deck('OP01-001', fuenfzigRote()), mitRoten);
      expect(p.gueltig, isTrue, reason: p.meldungen.join(' / '));
      expect(p.meldungen, isEmpty);
    });

    test('49 oder 51 Karten sind nicht erlaubt (5-1-2)', () {
      final weniger = fuenfzigRote()..['R-012'] = 1;
      final mehr = fuenfzigRote()..['R-012'] = 3;
      expect(DeckRegeln.pruefen(deck('OP01-001', weniger), mitRoten).gueltig, isFalse);
      expect(DeckRegeln.pruefen(deck('OP01-001', mehr), mitRoten).gueltig, isFalse);
      expect(DeckRegeln.pruefen(deck('OP01-001', weniger), mitRoten).meldungen.first, contains('bis 50'));
    });

    test('ohne Leader nicht spielbereit', () {
      final p = DeckRegeln.pruefen(deck(null, fuenfzigRote()), mitRoten);
      expect(p.gueltig, isFalse);
      expect(p.meldungen.first, contains('Leader'));
    });

    test('eine Nicht-Leader-Karte als Leader zaehlt nicht', () {
      expect(DeckRegeln.pruefen(deck('OP01-013', fuenfzigRote()), mitRoten).leader, isNull);
    });

    test('hoechstens 4 je Kartennummer - Alt-Arts zaehlen mit (5-1-2-3)', () {
      final p = DeckRegeln.pruefen(deck('OP01-001', {'OP01-013': 3, 'OP01-013-ALT': 2}), von);
      expect(p.zuViele, {'OP01-013': 5});
      final ok = DeckRegeln.pruefen(deck('OP01-001', {'OP01-013': 2, 'OP01-013-ALT': 2}), von);
      expect(ok.zuViele, isEmpty);
    });

    test('Karten einer Farbe, die der Leader nicht hat, sind verboten (5-1-2-2)', () {
      final p = DeckRegeln.pruefen(deck('OP01-001', {'OP01-013': 1, 'OP01-025': 1}), von);
      expect(p.falscheFarbe.map((k) => k.id), ['OP01-025']);
    });

    test('zweifarbiger Leader erlaubt beide Farben', () {
      final p = DeckRegeln.pruefen(deck('OP01-002', {'OP01-013': 1, 'OP01-025': 1, 'OP01-039': 1}), von);
      expect(p.falscheFarbe, isEmpty);
      final blau = DeckRegeln.pruefen(deck('OP01-002', {'OP01-077': 1}), von);
      expect(blau.falscheFarbe.map((k) => k.id), ['OP01-077']);
    });

    test('eine mehrfarbige Karte braucht ALLE ihre Farben im Leader', () {
      // Rot/Gruen ist auch "eine Karte einer nicht enthaltenen Farbe", wenn der Leader nur rot ist
      expect(DeckRegeln.pruefen(deck('OP01-001', {'OP01-090': 1}), von).falscheFarbe, hasLength(1));
      expect(DeckRegeln.pruefen(deck('OP01-002', {'OP01-090': 1}), von).falscheFarbe, isEmpty);
    });

    test('ein Leader im 50er-Deck ist verboten (5-1-2-1)', () {
      final p = DeckRegeln.pruefen(deck('OP01-001', {'OP01-060': 1}), von);
      expect(p.falscherTyp.map((k) => k.id), ['OP01-060']);
    });

    test('Events und Stages sind erlaubt', () {
      final p = DeckRegeln.pruefen(deck('OP01-002', {'OP01-029': 1, 'OP01-039': 1}), von);
      expect(p.falscherTyp, isEmpty);
    });

    test('unbekannte Karten werden benannt', () {
      final p = DeckRegeln.pruefen(deck('OP01-001', {'XX99-001': 1}), von);
      expect(p.unbekannt, ['XX99-001']);
      expect(p.gueltig, isFalse);
    });

    test('Karten ohne Farbangabe gelten als erlaubt - keine falschen Fehler', () {
      final ohne = karte('Z-001', farben: const []);
      expect(DeckRegeln.farbeErlaubt(ohne, von('OP01-001')!), isTrue);
    });

    test('der Sucher zeigt nur passende Karten', () {
      final rot = von('OP01-001')!;
      expect(DeckRegeln.passt(von('OP01-013')!, rot), isTrue);
      expect(DeckRegeln.passt(von('OP01-025')!, rot), isFalse);
      expect(DeckRegeln.passt(von('OP01-060')!, rot), isFalse, reason: 'Leader gehoeren nicht ins Deck');
      expect(DeckRegeln.passt(von('OP01-077')!, null), isTrue, reason: 'ohne Leader alles zeigen');
    });

    test('Kopien je Nummer ueber alle Artworks', () {
      final d = deck('OP01-001', {'OP01-013': 2, 'OP01-013-ALT': 1, 'OP01-014': 4});
      expect(DeckRegeln.kopienDerNummer(d, 'OP01-013', von), 3);
    });
  });

  group('Sonderregeln einzelner Karten (5-1-2-4)', () {
    // Wortlaute wie auf den echten Karten (Prisoner of Impel Down, Rayleigh, Imu, P-117 Nami)
    final prisoner = karte('OP16-042',
        farben: ['Blue'], effekt: 'Under the rules of this game, you may have any number of this card in your deck.');
    final rayleigh = karte('OP12-001',
        typ: 'LEADER',
        farben: ['Blue'],
        effekt: 'Under the rules of this game, you cannot include cards with a cost of 5 or more in your deck. [DON!! x1] …');
    final imu = karte('OP13-079',
        typ: 'LEADER',
        farben: ['Blue'],
        effekt: 'Under the rules of this game, you cannot include Events with a cost of 2 or more in your deck '
            'and at the start of the game, play up to 1 Stage.');
    final nami = karte('P-117',
        typ: 'LEADER',
        farben: ['Blue'],
        effekt: 'Under the rules of this game, you can only include {East Blue} type cards in your deck and when your deck is reduced to 0 …');
    final teuer = karte('B-005', farben: ['Blue'], kosten: 5, typen: ['Navy']);
    final billig = karte('B-004', farben: ['Blue'], kosten: 4, typen: ['East Blue']);
    final event2 = karte('B-E02', typ: 'EVENT', farben: ['Blue'], kosten: 2);
    final figur2 = karte('B-C02', farben: ['Blue'], kosten: 2, typen: ['Navy']);
    final ohneTyp = karte('B-X01', farben: ['Blue'], kosten: 1);
    final alle = {for (final k in [prisoner, rayleigh, imu, nami, teuer, billig, event2, figur2, ohneTyp]) k.id: k};
    OpCard? hier(String id) => alle[id];

    test('"any number of this card" hebt die Kopiengrenze auf', () {
      final p = DeckRegeln.pruefen(deck('OP12-001', {'OP16-042': 8}), hier);
      expect(p.zuViele, isEmpty);
      expect(DeckRegeln.grenze(prisoner), greaterThan(4));
      expect(DeckRegeln.grenze(teuer), 4);
    });

    test('Rayleigh: keine Karten ab Kosten 5', () {
      final p = DeckRegeln.pruefen(deck('OP12-001', {'B-005': 1, 'B-004': 1}), hier);
      expect(p.sonderregelVerstoss.map((k) => k.id), ['B-005']);
      expect(p.meldungen.join(), contains('ab Kosten 5'));
      expect(DeckRegeln.passt(teuer, rayleigh), isFalse, reason: 'der Sucher zeigt sie gar nicht erst');
      expect(DeckRegeln.passt(billig, rayleigh), isTrue);
    });

    test('Imu: keine Events ab Kosten 2 - Charaktere mit Kosten 2 schon', () {
      final p = DeckRegeln.pruefen(deck('OP13-079', {'B-E02': 1, 'B-C02': 1}), hier);
      expect(p.sonderregelVerstoss.map((k) => k.id), ['B-E02']);
    });

    test('Nami P-117: nur {East Blue}-Karten', () {
      final p = DeckRegeln.pruefen(deck('P-117', {'B-004': 1, 'B-C02': 1}), hier);
      expect(p.sonderregelVerstoss.map((k) => k.id), ['B-C02']);
    });

    test('Karten ohne Typangabe werden nicht faelschlich verworfen', () {
      expect(LeaderSonderregel.aus(nami)!.erlaubt(ohneTyp), isTrue);
    });

    test('eine unbekannte Sonderregel fuehrt zu einem Vorbehalt statt zu stillem "spielbereit"', () {
      final fremd = karte('Z-001',
          typ: 'LEADER', farben: ['Blue'], effekt: 'Under the rules of this game, your deck must contain exactly 3 Stages.');
      final regel = LeaderSonderregel.aus(fremd)!;
      expect(regel.ungeprueft.single, contains('exactly 3 Stages'));
      final p = DeckRegeln.pruefen(deck('Z-001', const {}), (id) => id == 'Z-001' ? fremd : null);
      expect(p.vorbehalt, isTrue);
    });

    test('Leader ohne Sonderregel', () {
      expect(LeaderSonderregel.aus(von('OP01-001')), isNull);
    });

    test('Spielregeln ohne Deckbezug ergeben keinen Vorbehalt (Brook, Enel OP15-058)', () {
      // Wortlaute wie auf den echten Karten
      final brook = karte('OP15-022',
          typ: 'LEADER',
          farben: ['Purple'],
          effekt: 'Under the rules of this game, you do not lose when your deck has 0 cards. '
              'You lose at the end of the turn in which your deck becomes 0 cards.');
      final enel = karte('OP15-058',
          typ: 'LEADER', farben: ['Purple'], effekt: 'Under the rules of this game, your DON!! deck consists of 6 cards.');
      expect(LeaderSonderregel.aus(brook), isNull);
      expect(LeaderSonderregel.aus(enel), isNull);
      final p = DeckRegeln.pruefen(deck('OP15-022', const {}), (id) => id == 'OP15-022' ? brook : null);
      expect(p.vorbehalt, isFalse);
    });
  });

  group('Statistik', () {
    test('Kostenkurve, Typen und Counter', () {
      final s = DeckStatistik.berechnen(
        deck('OP01-002', {'OP01-013': 4, 'OP01-014': 2, 'OP01-029': 3, 'OP01-039': 1}),
        von,
      );
      expect(s.kostenKurve[2], 4);
      expect(s.kostenKurve[1], 3);
      expect(s.kostenKurve[10], 1, reason: 'Kosten 12 zaehlen bei 10+');
      expect(s.nachTyp, {'CHARACTER': 6, 'EVENT': 3, 'STAGE': 1});
      expect(s.counter1000, 4);
      expect(s.counter2000, 2);
    });
  });

  group('Als Text und zurueck', () {
    test('Leader zuerst, dann die Karten sortiert', () {
      final text = DeckText.alsText(deck('OP01-001', {'OP01-014': 2, 'OP01-013': 4}));
      expect(text, '1xOP01-001\n4xOP01-013\n2xOP01-014');
    });

    test('Rundlauf: Text einfuegen ergibt dasselbe Deck', () {
      final d = deck('OP01-002', {'OP01-013': 4, 'OP01-025': 3, 'OP01-029': 2});
      final r = DeckText.ausText(DeckText.alsText(d), matcher);
      expect(r.leaderId, 'OP01-002');
      expect(r.karten, d.karten);
      expect(r.nichtErkannt, isEmpty);
    });

    test('mehrere Leader in der Liste - keiner wird geraten', () {
      final r = DeckText.ausText('1xOP01-001\n1xOP01-060\n4xOP01-013', matcher);
      expect(r.leaderId, isNull);
      expect(r.karten, {'OP01-013': 4});
    });

    test('unbekannte Zeilen werden gemeldet', () {
      final r = DeckText.ausText('1xOP01-001\n4xOP01-013\nKeine Karte hier', matcher);
      expect(r.nichtErkannt, ['Keine Karte hier']);
    });

    test('Turnierdeck als Vorlage: Leader herausgeloest, Normalversionen', () {
      final turnier = Deck.fromJson({
        'n': 'Zoro Aggro',
        'l': 'OP01-001',
        'c': '1xOP01-001 4xOP01-013 2xOP01-014',
      })!;
      final r = DeckText.ausTurnierdeck(turnier, (nr) => matcher.byId(nr) ?? matcher.byId('$nr-ALT'));
      expect(r.leaderId, 'OP01-001');
      expect(r.karten, {'OP01-013': 4, 'OP01-014': 2});
    });
  });

  group('Abgleich mit der Sammlung', () {
    test('Besitz zaehlt je Nummer, egal welches Artwork, hoechstens bis zum Bedarf', () {
      final d = deck('OP01-001', {'OP01-013': 4, 'OP01-014': 2});
      final besitz = {'OP01-013': 6, 'OP01-014': 1};
      final a = DeckAbdeckung.berechnen(d, von, (nr) => besitz[nr] ?? 0);
      expect(a.benoetigt, 6);
      expect(a.vorhanden, 5, reason: '4 von 4 plus 1 von 2 - die zwei ueberzaehligen zaehlen nicht');
      expect(a.fehlend, {'OP01-014': 1});
    });

    test('fuer die Wunschliste zaehlt die Variante, die im Deck steht', () {
      final d = deck('OP01-001', {'OP01-013-ALT': 3});
      final a = DeckAbdeckung.berechnen(d, von, (_) => 0);
      expect(a.fehlend, {'OP01-013-ALT': 3});
    });
  });

  group('Decks verwalten', () {
    test('anlegen, Karten setzen, loeschen - jede Aenderung wird gespeichert', () {
      var gespeichert = 0;
      final m = MeineDecks(onAenderung: () => gespeichert++);
      final id = m.anlegen(name: 'Zoro', leaderId: 'OP01-001');
      m.setzeKarte(id, 'OP01-013', 4);
      m.setzeKarte(id, 'OP01-013', 0);
      expect(m.deck(id)!.karten, isEmpty);
      m.loeschen(id);
      expect(m.decks, isEmpty);
      expect(gespeichert, 4);
    });

    test('Laden loest keinen Speichervorgang aus', () {
      var gespeichert = 0;
      final m = MeineDecks(onAenderung: () => gespeichert++);
      m.laden([deck('OP01-001', const {})]);
      expect(gespeichert, 0);
      expect(m.decks, hasLength(1));
    });

    test('neue Decks stehen oben, IDs sind eindeutig', () {
      final m = MeineDecks();
      final a = m.anlegen(name: 'A');
      final b = m.anlegen(name: 'B');
      expect(a, isNot(b));
      expect(m.decks.first.name, 'B');
    });
  });

  group('Gespeichert mit der Sammlung', () {
    test('eigene Decks ueberleben Speichern und Laden', () async {
      SharedPreferences.setMockInitialValues({});
      await CollectionStore.save(CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: const [],
        myDecks: [deck('OP01-002', {'OP01-013': 4})],
      ));
      final s = await CollectionStore.load();
      expect(s.myDecks.single.leaderId, 'OP01-002');
      expect(s.myDecks.single.karten, {'OP01-013': 4});
    });

    test('aeltere Staende ohne eigene Decks laden weiter', () {
      expect(CollectionStore.parse(jsonEncode({'scans': []}))!.myDecks, isEmpty);
    });

    test('kaputte Deck-Eintraege werden uebersprungen, der Rest bleibt', () {
      final s = CollectionStore.parse(jsonEncode({
        'scans': [],
        'myDecks': [
          {'name': 'ohne ID'},
          'kein Objekt',
          {'id': 'ok', 'name': 'Gut', 'cards': {'OP01-013': 4, 'OP01-014': 0}},
        ],
      }))!;
      expect(s.myDecks.single.id, 'ok');
      expect(s.myDecks.single.karten, {'OP01-013': 4}, reason: 'Anzahl 0 faellt weg');
    });

    test('die Sicherung enthaelt die eigenen Decks', () async {
      SharedPreferences.setMockInitialValues({});
      await CollectionStore.save(CollectionState(
        folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
        activeFolderId: 'default',
        scans: const [],
        myDecks: [deck('OP01-001', {'OP01-013': 1})],
      ));
      final roh = jsonDecode((await CollectionStore.exportRaw())!);
      expect((roh['myDecks'] as List).single['leader'], 'OP01-001');
    });
  });
}
