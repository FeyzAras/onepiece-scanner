import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/price_history.dart';
import 'package:onepiece_scanner/set_progress.dart';

/// Die Uebersicht rechnet mit Geld - und mit Zahlen, die Sammler ernst nehmen
/// ("87 von 175"). Falsch zaehlen faellt dort sofort auf und kostet Vertrauen.
void main() {
  OpCard karte(String id, {bool alt = false, bool jpOnly = false, List<String> colors = const ['Red']}) =>
      OpCard(
        id: id,
        baseId: id.replaceAll('-ALT', ''),
        alt: alt,
        name: id,
        rarity: 'R',
        cardType: 'CHARACTER',
        colors: colors,
        effect: '',
        jpOnly: jpOnly,
      );

  group('Farben', () {
    test('zweifarbige Leader behalten beide Farben', () {
      final law = OpCard.fromJson({
        'id': 'OP01-002',
        'baseId': 'OP01-002',
        'colors': ['Red', 'Green'],
        'color': 'Red',
      });
      expect(law.colors, ['Red', 'Green']);
      expect(law.color, 'Red/Green', reason: 'Anzeige und CSV zeigen jetzt beide');
    });

    test('alte Katalogdateien mit nur einer Farbe funktionieren weiter', () {
      final alt = OpCard.fromJson({'id': 'OP01-004', 'baseId': 'OP01-004', 'color': 'Red'});
      expect(alt.colors, ['Red']);
      expect(OpCard.fromJson({'id': 'x', 'baseId': 'x'}).colors, isEmpty);
    });

    test('Counter wird gelesen', () {
      expect(OpCard.fromJson({'id': 'x', 'baseId': 'x', 'counter': 2000}).counter, 2000);
      expect(OpCard.fromJson({'id': 'x', 'baseId': 'x'}).counter, isNull);
    });

    test('der mitgelieferte Katalog kennt die zweifarbigen Leader', () {
      final datei = File('assets/cards.json');
      if (!datei.existsSync()) return;
      final karten = (jsonDecode(datei.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>()
          .map(OpCard.fromJson)
          .toList();
      final law = karten.firstWhere((k) => k.id == 'OP01-002');
      expect(law.colors, containsAll(['Red', 'Green']));
      expect(karten.where((k) => k.colors.length > 1).length, greaterThan(100));
    });
  });

  group('Set-Namen', () {
    test('Name, "enthalten in" und Rueckfall auf den Code', () {
      final infos = SetInfo.parseAll(jsonEncode([
        {'code': 'OP01', 'name': 'Romance Dawn'},
        {'code': 'EB04', 'name': null, 'enthalten': ['Adventure on Kami\'s Island', 'The Azure Sea\'s Seven']},
        {'code': 'XX01'},
      ]));
      expect(infos['OP01']!.anzeigename, 'Romance Dawn');
      expect(infos['EB04']!.anzeigename, startsWith('enthalten in Adventure'));
      expect(infos['XX01']!.anzeigename, 'XX01');
    });

    test('kaputte Datei ergibt eine leere Zuordnung', () {
      expect(SetInfo.parseAll('{kaputt'), isEmpty);
      expect(SetInfo.parseAll('{}'), isEmpty);
    });

    test('der mitgelieferte Katalog hat zu jedem Set einen Eintrag', () {
      final datei = File('assets/sets.json');
      if (!datei.existsSync()) return;
      final infos = SetInfo.parseAll(datei.readAsStringSync());
      expect(infos['OP01']?.name, 'Romance Dawn');
      expect(infos.length, greaterThanOrEqualTo(50));
    });
  });

  group('Set-Fortschritt', () {
    final katalog = [
      karte('OP01-001'),
      karte('OP01-002'),
      karte('OP01-003'),
      karte('OP01-001-ALT', alt: true),
      karte('OP01-099', jpOnly: true),
      karte('ST01-001'),
      karte('ST01-002'),
    ];
    final preise = {'OP01-001': 2.0, 'OP01-002': 5.0, 'OP01-003': 0.5, 'ST01-001': 1.0};
    double preis(OpCard k) => preise[k.id] ?? 0;

    test('Grundkarten und Alt-Arts werden getrennt gezaehlt', () {
      final f = SetProgress.berechnen(
        katalog: katalog,
        besessen: {'OP01-001', 'OP01-001-ALT'},
        preisVon: preis,
      ).firstWhere((s) => s.code == 'OP01');
      expect(f.grundGesamt, 3);
      expect(f.grundBesessen, 1);
      expect(f.altGesamt, 1);
      expect(f.altBesessen, 1);
    });

    test('nur auf Japanisch erschienene Karten zaehlen nicht zur Gesamtzahl', () {
      final f = SetProgress.berechnen(katalog: katalog, besessen: {}, preisVon: preis)
          .firstWhere((s) => s.code == 'OP01');
      expect(f.grundGesamt, 3, reason: 'OP01-099 ist jpOnly');
    });

    test('fehlende Karten, guenstigste zuerst, mit Kosten zum Komplettieren', () {
      final f = SetProgress.berechnen(katalog: katalog, besessen: {'OP01-001'}, preisVon: preis)
          .firstWhere((s) => s.code == 'OP01');
      expect(f.fehlend.map((k) => k.id), ['OP01-003', 'OP01-002']);
      expect(f.kostenKomplett, closeTo(5.5, 0.001));
      expect(f.ohnePreis, 0);
    });

    test('fehlende Karten ohne Preis werden gezaehlt statt verschwiegen', () {
      final f = SetProgress.berechnen(katalog: katalog, besessen: {}, preisVon: preis)
          .firstWhere((s) => s.code == 'ST01');
      expect(f.kostenKomplett, closeTo(1.0, 0.001));
      expect(f.ohnePreis, 1, reason: 'ST01-002 hat keinen Preis - die Kosten sind eine Untergrenze');
    });

    test('ein komplettes Set wird erkannt', () {
      final f = SetProgress.berechnen(
        katalog: katalog,
        besessen: {'ST01-001', 'ST01-002'},
        preisVon: preis,
      ).firstWhere((s) => s.code == 'ST01');
      expect(f.komplett, isTrue);
      expect(f.anteil, 1.0);
      expect(f.kostenKomplett, 0);
    });

    test('angefangene Sets zuerst, nach Fortschritt sortiert', () {
      final liste = SetProgress.berechnen(
        katalog: [...katalog, karte('OP02-001')],
        besessen: {'ST01-001', 'OP01-001'},
        preisVon: preis,
      );
      expect(liste.map((s) => s.code), ['ST01', 'OP01', 'OP02']);
    });

    test('Set-Namen werden zugeordnet', () {
      final f = SetProgress.berechnen(
        katalog: katalog,
        besessen: {},
        preisVon: preis,
        infos: {'OP01': const SetInfo(code: 'OP01', name: 'Romance Dawn')},
      ).firstWhere((s) => s.code == 'OP01');
      expect(f.anzeigename, 'Romance Dawn');
    });
  });

  group('Verlaufsdatei lesen', () {
    test('Cent werden zu Euro, Luecken bleiben Luecken', () {
      final h = SetHistory.parse(jsonEncode({
        'dates': ['2026-10-01', '2026-10-02', '2026-10-03'],
        'prices': {
          'OP01-001': [187, null, 200],
        },
      }))!;
      final v = h.verlaufVon('OP01-001');
      expect(v.map((p) => p.datum), ['2026-10-01', '2026-10-03']);
      expect(v.first.wert, closeTo(1.87, 0.0001));
      expect(h.verlaufVon('gibtsnicht'), isEmpty);
    });

    test('Reihen, die nicht zur Datumsachse passen, werden verworfen', () {
      final h = SetHistory.parse(jsonEncode({
        'dates': ['2026-10-01', '2026-10-02'],
        'prices': {
          'OP01-001': [100, 110],
          'OP01-002': [100],
        },
      }))!;
      expect(h.prices.keys, ['OP01-001'], reason: 'sonst wuerden Werte auf falsche Tage rutschen');
    });

    test('kaputte Dateien ergeben null', () {
      expect(SetHistory.parse('{kaputt'), isNull);
      expect(SetHistory.parse('[]'), isNull);
      expect(SetHistory.parse(jsonEncode({'dates': 'x', 'prices': {}})), isNull);
    });
  });

  group('Wertverlauf der Sammlung', () {
    final op01 = SetHistory(dates: const ['2026-10-01', '2026-10-02', '2026-10-03'], prices: {
      'OP01-001': const [100, null, 200],
      'OP01-002': const [null, 300, 300],
    });
    final st01 = SetHistory(dates: const ['2026-10-02', '2026-10-03'], prices: {
      'ST01-001': const [50, 60],
    });

    test('Dubletten zaehlen mehrfach, Luecken werden vorwaerts gefuellt', () {
      final v = WertVerlauf.berechnen(
        kartenIds: ['OP01-001', 'OP01-001'],
        historien: {'OP01': op01},
      );
      expect(v.map((p) => p.wert), [2.0, 2.0, 4.0], reason: 'Tag 2 ohne Preis -> Wert von Tag 1');
    });

    test('vor dem ersten bekannten Preis zaehlt eine Karte nicht mit', () {
      final v = WertVerlauf.berechnen(kartenIds: ['OP01-002'], historien: {'OP01': op01});
      expect(v.map((p) => p.wert), [0.0, 3.0, 3.0]);
    });

    test('mehrere Sets mit unterschiedlichen Tagen auf einer Achse', () {
      final v = WertVerlauf.berechnen(
        kartenIds: ['OP01-001', 'ST01-001'],
        historien: {'OP01': op01, 'ST01': st01},
      );
      expect(v.map((p) => p.datum), ['2026-10-01', '2026-10-02', '2026-10-03']);
      expect(v.map((p) => p.wert).toList(), [1.0, 1.5, 2.6]);
    });

    test('Karten ohne Verlauf und leere Sammlungen', () {
      expect(WertVerlauf.berechnen(kartenIds: [], historien: {'OP01': op01}), isEmpty);
      expect(WertVerlauf.berechnen(kartenIds: ['OP01-001'], historien: {}), isEmpty);
      final v = WertVerlauf.berechnen(kartenIds: ['XX01-001', 'OP01-001'], historien: {'OP01': op01});
      expect(v.last.wert, 2.0, reason: 'unbekannte Karte zaehlt nicht, stoert aber auch nicht');
    });

    test('Veraenderung gegenueber vor einer Woche', () {
      final verlauf = [
        const PreisPunkt('2026-10-01', 100),
        const PreisPunkt('2026-10-05', 110),
        const PreisPunkt('2026-10-08', 120),
      ];
      final w = WertVerlauf.veraenderung(verlauf, 7)!;
      expect(w.absolut, closeTo(20, 0.001), reason: 'Vergleich mit 01.10., dem Stand vor 7 Tagen');
      expect(w.prozent, closeTo(20, 0.001));
      expect(WertVerlauf.veraenderung([const PreisPunkt('2026-10-01', 5)], 7), isNull);
    });
  });

  group('Laden mit Zwischenspeicher', () {
    late HttpServer server;
    late Directory ordner;
    var abrufe = 0;
    var antworten = true;
    final inhalt = jsonEncode({
      'dates': ['2026-10-01'],
      'prices': {
        'OP01-001': [187]
      },
    });

    setUp(() async {
      abrufe = 0;
      antworten = true;
      ordner = await Directory.systemTemp.createTemp('verlauf_test_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        abrufe++;
        if (antworten && r.uri.path.endsWith('/OP01.json')) {
          r.response.write(inhalt);
        } else {
          r.response.statusCode = HttpStatus.notFound;
        }
        r.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      if (ordner.existsSync()) await ordner.delete(recursive: true);
    });

    HistoryStore store() => HistoryStore(
          basis: 'http://127.0.0.1:${server.port}/history/',
          ordner: () async => ordner,
        );

    test('erster Abruf holt und speichert, der zweite kommt aus der Datei', () async {
      final h = await store().laden('OP01');
      expect(h?.prices['OP01-001'], [187]);
      expect(abrufe, 1);

      final wieder = await store().laden('OP01');
      expect(wieder, isNotNull);
      expect(abrufe, 1, reason: 'frische Datei - kein zweiter Abruf');
    });

    test('ohne Netz gilt der alte Stand weiter', () async {
      await store().laden('OP01');
      antworten = false;
      final spaeter = await store().laden('OP01', jetzt: DateTime.now().add(const Duration(days: 2)));
      expect(spaeter?.prices['OP01-001'], [187], reason: 'ein alter Verlauf ist besser als keiner');
      expect(abrufe, 2, reason: 'es wurde versucht, neu zu laden');
    });

    test('nie geladen und kein Netz ergibt null', () async {
      antworten = false;
      expect(await store().laden('OP01'), isNull);
    });

    test('mehrere Sets auf einmal, Fehlschlaege fallen weg', () async {
      final alle = await store().ladenMehrere(['OP01', 'OP02', 'OP01']);
      expect(alle.keys, ['OP01']);
    });
  });
}
