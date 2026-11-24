import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/card_versions.dart';
import 'package:onepiece_scanner/widgets.dart';

OpCard karte(String id, {String? baseId, bool? alt}) {
  final basis = baseId ?? id.replaceAll(RegExp(r'-ALT\d*$'), '');
  return OpCard(id: id, baseId: basis, alt: alt ?? id != basis, name: 'Edward.Newgate', rarity: 'R', cardType: 'CHARACTER', effect: '');
}

/// So schreibt import-cardmarket-prices.js die Datei - Werte wie bei OP17-040 am 24.11.2026.
const beispiel = '''
{"asOf":"2026-11-24",
 "ausgaben":{"6492":"The World's Strongest Warriors","6723":"The World's Strongest Warriors (Asia Region Legal)","6772":"The Dominance of God"},
 "versionen":{
   "OP17-040":[[904855,6723,6],[904022,6492,16,[0]],[904023,6492,2550,[1]],[923820,6772,7446]],
   "OP01-006":[[690371,5229,17,[0,4]],[690798,5229,17]]
 }}
''';

void main() {
  group('Datei lesen', () {
    test('Versionen mit Ausgabe, Preis und Motiv - guenstigste zuerst', () {
      final d = VersionsDaten.parse(beispiel)!;
      expect(d.asOf, '2026-11-24');
      final v = d.von('OP17-040');
      expect(v.map((x) => x.idProduct), [904855, 904022, 904023, 923820]);
      expect(v.first.ausgabe, "The World's Strongest Warriors (Asia Region Legal)");
      expect(v.first.preis, 0.06);
      expect(v.first.motive, isEmpty, reason: 'Asien-Auflage gehoert keinem Motiv automatisch');
      expect(v[2].motive, [1]);
      expect(d.von('op17-040'), hasLength(4), reason: 'Gross-/Kleinschreibung egal');
      expect(d.von('OP99-999'), isEmpty);
    });

    test('kaputte Eintraege fallen weg, unbrauchbare Dateien ergeben null', () {
      final d = VersionsDaten.parse(
          '{"ausgaben":{},"versionen":{"A-001":[[1,2,300],[null,2,5],[3,4],"x",[5,6,-1]],"B-001":"x"}}')!;
      expect(d.von('A-001').map((v) => v.idProduct), [1]);
      expect(d.von('A-001').single.ausgabe, 'Cardmarket-Ausgabe 2', reason: 'Name fehlt -> Nummer');
      expect(d.von('B-001'), isEmpty);
      expect(VersionsDaten.parse('{"versionen":{}}'), isNull);
      expect(VersionsDaten.parse('{"ausgaben":{}}'), isNull);
      expect(VersionsDaten.parse('kein json'), isNull);
      expect(VersionsDaten.parse('[1,2,3]'), isNull);
    });
  });

  group('Automatische Version und Gruppierung', () {
    final d = VersionsDaten.parse(beispiel)!;

    test('jedes Motiv findet seine automatische Version', () {
      expect(d.standardFuer(karte('OP17-040'))!.idProduct, 904022);
      expect(d.standardFuer(karte('OP17-040-ALT'))!.idProduct, 904023);
      expect(d.standardFuer(karte('OP17-040-ALT2')), isNull, reason: 'Motiv ohne Cardmarket-Gegenstueck');
      // Ein Nachdruck teilt sich die Version mit der Normalversion
      expect(d.standardFuer(karte('OP01-006-ALT4'))!.idProduct, 690371);
    });

    test('Ausgabe der eigenen Version zuerst, Versionen ohne Motiv zuletzt', () {
      final gruppen = nachAusgabe(d.von('OP17-040'), karte('OP17-040'));
      expect(gruppen.map((g) => g.ausgabe), [
        "The World's Strongest Warriors",
        "The World's Strongest Warriors (Asia Region Legal)",
        'The Dominance of God',
      ]);
      expect(gruppen.first.versionen.map((v) => v.idProduct), [904022, 904023]);
    });
  });

  group('Alte Preiswahl uebersetzen', () {
    final v = VersionsDaten.parse(beispiel)!.von('OP17-040');

    test('Listenplatz -> Produktnummer', () {
      expect(produktZumAltenPlatz(v, 0), 904855);
      expect(produktZumAltenPlatz(v, 2), 904023);
      expect(produktZumAltenPlatz(v, 4), isNull);
      expect(produktZumAltenPlatz(v, -1), isNull);
    });

    test('alter Betrag -> naechstliegende Version', () {
      expect(produktZumAltenBetrag(v, 30.87), 904023);
      expect(produktZumAltenBetrag(v, 0.1), 904855);
      expect(produktZumAltenBetrag(const [], 1), isNull);
    });
  });

  group('Motiv-Platz', () {
    test('Hin und zurueck', () {
      for (final (id, platz) in [('OP17-040', 0), ('OP17-040-ALT', 1), ('OP17-040-ALT7', 7)]) {
        expect(motivIndexVon(id, 'OP17-040'), platz);
        expect(motivIdVon('OP17-040', platz), id);
      }
      expect(motivIndexVon('OP17-0401', 'OP17-040'), -1);
      expect(motivIndexVon('OP17-040-X', 'OP17-040'), -1);
      expect(karte('OP17-040-ALT3').motivIndex, 3);
    });

    test('Bezeichnung: Normal, Parallele, Nachdruck', () {
      expect(karte('OP01-006').motivName, 'Normal');
      expect(karte('OP01-006-ALT').motivName, 'Parallele');
      const nachdruck = OpCard(
        id: 'OP01-006-ALT4', baseId: 'OP01-006', alt: true, name: 'Otama', rarity: 'UC', cardType: 'CHARACTER',
        effect: '', img: 'https://x/OP01-006_r1.png',
      );
      expect(nachdruck.istNachdruck, isTrue);
      expect(nachdruck.motivName, 'Nachdruck');
    });
  });

  group('Euro im deutschen Format', () {
    test('Komma, Tausenderpunkt, Rundung', () {
      expect(formatEuro(0.17), '0,17 €');
      expect(formatEuro(30.87), '30,87 €');
      expect(formatEuro(1234.5), '1.234,50 €');
      expect(formatEuro(12030.94), '12.030,94 €');
      expect(formatEuro(1234567.891), '1.234.567,89 €');
      expect(formatEuro(0), '0,00 €');
      expect(formatEuro(0.005), '0,01 €');
      expect(formatEuro(-2.5), '−2,50 €');
    });
  });

  group('Speicher', () {
    late Directory ordner;
    late HttpServer server;
    var antwort = beispiel;
    var status = 200;

    setUp(() async {
      ordner = await Directory.systemTemp.createTemp('versionen_test');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        r.response.statusCode = status;
        r.response.write(antwort);
        r.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await ordner.delete(recursive: true);
    });

    VersionStore store() =>
        VersionStore(url: 'http://127.0.0.1:${server.port}/versions.json', ordner: () async => ordner);

    test('abrufen legt den Stand ab, gespeichert liest ihn ohne Netz', () async {
      expect(await store().gespeichert(), isNull);
      final frisch = await store().abrufen();
      expect(frisch!.von('OP17-040'), hasLength(4));
      final spaeter = await store().gespeichert();
      expect(spaeter!.von('OP17-040'), hasLength(4));
      expect(File('${ordner.path}${Platform.pathSeparator}versions.json.tmp').existsSync(), isFalse);
    });

    test('kaputte Antwort oder Fehler ueberschreibt den alten Stand nicht', () async {
      await store().abrufen();
      antwort = '{"versionen":';
      expect(await store().abrufen(), isNull);
      status = 500;
      expect(await store().abrufen(), isNull);
      expect((await store().gespeichert())!.von('OP17-040'), hasLength(4));
      antwort = beispiel;
      status = 200;
    });
  });

  // ── Die echte mitgelieferte Datei gegen den echten Katalog ──────────────────
  final versionenDatei = File('assets/versions.json');
  final katalogDatei = File('assets/cards.json');
  final echt = versionenDatei.existsSync() && katalogDatei.existsSync();

  group('Echte Daten', () {
    late VersionsDaten daten;
    late Map<String, OpCard> katalog;

    setUpAll(() {
      daten = VersionsDaten.parse(versionenDatei.readAsStringSync())!;
      katalog = {
        for (final j in (jsonDecode(katalogDatei.readAsStringSync()) as List).cast<Map<String, dynamic>>())
          (j['id'] as String).toUpperCase(): OpCard.fromJson(j),
      };
    });

    test('OP17-040 hat seine vier Versionen, mit Namen', () {
      final v = daten.von('OP17-040');
      expect(v.length, greaterThanOrEqualTo(3));
      expect(v.map((x) => x.ausgabe), contains("The World's Strongest Warriors (Asia Region Legal)"));
      expect(daten.standardFuer(katalog['OP17-040']!)!.ausgabe, "The World's Strongest Warriors");
      expect(daten.standardFuer(katalog['OP17-040-ALT']!)!.preis,
          greaterThan(daten.standardFuer(katalog['OP17-040']!)!.preis * 10));
    });

    test('jede automatische Version zeigt auf ein Motiv, das es im Katalog gibt', () {
      var geprueft = 0;
      for (final MapEntry(key: nummer, value: versionen) in daten.jeNummer.entries) {
        for (final v in versionen) {
          for (final platz in v.motive) {
            expect(katalog.containsKey(motivIdVon(nummer, platz).toUpperCase()), isTrue,
                reason: '$nummer Motiv $platz (${v.idProduct})');
            geprueft++;
          }
        }
      }
      expect(geprueft, greaterThan(2000));
    });

    test('Katalogpreis und automatische Version stimmen ueberein', () {
      var geprueft = 0;
      for (final k in katalog.values) {
        final p = k.price;
        if (p == null || k.jpOnly) continue;
        final standard = daten.standardFuer(k);
        if (standard == null) continue;
        expect(standard.idProduct, p.idProduct, reason: k.id);
        expect((standard.preis - p.amount).abs(), lessThan(0.006), reason: k.id);
        geprueft++;
      }
      expect(geprueft, greaterThan(2000));
    });

    test('keine Originalausgabe in anderer Sprache - der Fehler bis v0.12', () {
      // OP05 bis OP16 bekamen frueher die Preise der zuerst angelegten Ausgabe, und das war
      // die japanische bzw. asiatische
      for (final id in ['OP05-001', 'OP09-004', 'OP13-001', 'OP16-001', 'EB01-001']) {
        final k = katalog[id];
        if (k == null) continue;
        final standard = daten.standardFuer(k);
        expect(standard, isNotNull, reason: id);
        expect(standard!.ausgabe, isNot(contains('Non-English')), reason: id);
        expect(standard.ausgabe, isNot(contains('Asia')), reason: id);
      }
    });
  }, skip: echt ? false : 'assets fehlen');
}
