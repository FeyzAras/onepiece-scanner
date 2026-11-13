import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Aktualisierung aus der App heraus ist die Funktion, die am ehesten Schaden
/// anrichten kann: Eine halb heruntergeladene APK, eine falsch verglichene Version
/// oder ein Update, das sich nicht installieren laesst, verleiten zum Deinstallieren -
/// und das loescht die Sammlung.
///
/// Die Downloads laufen hier gegen einen echten lokalen Server, nicht gegen eine
/// Attrappe: Umleitung, fehlende Laengenangabe, Verbindungsabriss und Abbruch
/// verhalten sich nur so wie im Ernstfall.
void main() {
  group('Versionsnummern', () {
    AppVersion v(String s) => AppVersion.parse(s)!;

    test('uebliche Schreibweisen', () {
      expect(v('0.9.0').toString(), '0.9.0');
      expect(v('v0.9.0').toString(), '0.9.0');
      expect(v('0.9').toString(), '0.9.0');
      expect(v('0.9.0+900').toString(), '0.9.0', reason: 'Build-Nummer wird ignoriert');
      expect(v(' 1.2.3 ').toString(), '1.2.3');
    });

    test('zweistellige Teile werden als Zahl verglichen, nicht als Text', () {
      expect(v('0.10.0') > v('0.9.0'), isTrue);
      expect(v('1.10.2') > v('1.9.9'), isTrue);
    });

    test('Reihenfolge', () {
      expect(v('0.9.1') > v('0.9.0'), isTrue);
      expect(v('1.0.0') > v('0.99.99'), isTrue);
      expect(v('0.9.0') > v('0.9.0'), isFalse);
      expect(v('0.9.0'), v('0.9'));
    });

    test('Unsinn ergibt null statt eines Absturzes', () {
      expect(AppVersion.parse(null), isNull);
      expect(AppVersion.parse(''), isNull);
      expect(AppVersion.parse('abc'), isNull);
      expect(AppVersion.parse('1.2.3.4'), isNull);
      expect(AppVersion.parse('1.-2.3'), isNull);
    });
  });

  group('version.json einlesen', () {
    const beispielSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    String datei({
      Object? version = '0.10.0',
      Object? url = 'https://github.com/x/releases/download/v0.10.0/a.apk',
      Object? bytes = 1234,
      Object? sha = beispielSha,
      Object? notes = const ['eins', 'zwei'],
      Object? minSdk = 24,
      Object? mandatory = false,
    }) =>
        jsonEncode({
          'version': version,
          'released': '2026-11-20',
          'minSdk': minSdk,
          'apk': {'url': url, 'bytes': bytes, 'sha256': sha},
          'notes': notes,
          'mandatory': mandatory,
        });

    test('vollstaendige Datei', () {
      final info = UpdateInfo.parse(datei())!;
      expect(info.version.toString(), '0.10.0');
      expect(info.apkUrl, endsWith('a.apk'));
      expect(info.bytes, 1234);
      expect(info.sha256, 'a' * 64);
      expect(info.notes, ['eins', 'zwei']);
      expect(info.minSdk, 24);
      expect(info.mandatory, isFalse);
    });

    test('ohne brauchbare Version oder Adresse gibt es kein Update', () {
      expect(UpdateInfo.parse(datei(version: 'kaputt')), isNull);
      expect(UpdateInfo.parse(datei(url: null)), isNull);
      expect(UpdateInfo.parse(datei(url: 'http://unsicher/a.apk')), isNull,
          reason: 'nur https - die APK wird schliesslich installiert');
    });

    test('kaputtes JSON stuerzt nicht ab', () {
      expect(UpdateInfo.parse('{kaputt'), isNull);
      expect(UpdateInfo.parse('[]'), isNull);
      expect(UpdateInfo.parse(''), isNull);
    });

    test('fehlerhafte Nebenangaben werden toleriert', () {
      final info = UpdateInfo.parse(datei(notes: 'kein Array', minSdk: '24', sha: 'zu kurz', bytes: -5))!;
      expect(info.notes, isEmpty);
      expect(info.minSdk, 24);
      expect(info.sha256, isNull, reason: 'eine ungueltige Pruefsumme wird nicht verwendet');
      expect(info.bytes, isNull);
    });

    test('die tatsaechlich veroeffentlichte Datei ist lesbar', () {
      final echt = File('../docs/data/version.json');
      if (!echt.existsSync()) return; // nur im Repository vorhanden
      final info = UpdateInfo.parse(echt.readAsStringSync());
      expect(info, isNotNull, reason: 'docs/data/version.json muss zum Leser passen');
      expect(info!.apkUrl, endsWith('onepiece-scanner-arm64.apk'));
    });
  });

  group('Wann ein Update angeboten wird', () {
    UpdateInfo info(String v, {int minSdk = 24, bool pflicht = false}) => UpdateInfo(
          version: AppVersion.parse(v)!,
          released: '',
          minSdk: minSdk,
          apkUrl: 'https://x/a.apk',
          mandatory: pflicht,
        );
    final installiert = AppVersion.parse('0.9.0')!;

    test('neuere Version wird angeboten', () {
      expect(UpdateService.anbieten(info: info('0.10.0'), installiert: installiert), isNotNull);
    });

    test('gleiche oder aeltere Version nicht', () {
      expect(UpdateService.anbieten(info: info('0.9.0'), installiert: installiert), isNull);
      expect(UpdateService.anbieten(info: info('0.8.0'), installiert: installiert), isNull);
    });

    test('zu altes Android bekommt nichts angeboten', () {
      expect(
        UpdateService.anbieten(info: info('0.10.0', minSdk: 30), installiert: installiert, androidVersion: 28),
        isNull,
      );
    });

    test('eine uebersprungene Version kommt nicht von selbst wieder', () {
      expect(
        UpdateService.anbieten(info: info('0.10.0'), installiert: installiert, uebersprungen: '0.10.0'),
        isNull,
      );
    });

    test('beim gezielten Nachsehen erscheint sie trotzdem', () {
      expect(
        UpdateService.anbieten(
            info: info('0.10.0'), installiert: installiert, uebersprungen: '0.10.0', manuell: true),
        isNotNull,
      );
    });

    test('eine Pflicht-Aktualisierung laesst sich nicht ueberspringen', () {
      expect(
        UpdateService.anbieten(info: info('0.10.0', pflicht: true), installiert: installiert, uebersprungen: '0.10.0'),
        isNotNull,
      );
    });
  });

  group('Nachsehen beim Server', () {
    late HttpServer server;
    late int abrufe;
    var antwortStatus = 200;
    var antwortText = '';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      abrufe = 0;
      antwortStatus = 200;
      antwortText = jsonEncode({
        'version': '0.10.0',
        'minSdk': 24,
        'apk': {'url': 'https://example.com/a.apk', 'bytes': 10},
      });
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        abrufe++;
        r.response.statusCode = antwortStatus;
        r.response.write(antwortText);
        r.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    String adresse() => 'http://127.0.0.1:${server.port}/version.json';

    test('findet die neuere Version', () async {
      final r = await UpdateService.pruefen(installierteVersion: '0.9.0', url: adresse());
      expect(r.angebot?.version.toString(), '0.10.0');
      expect(r.fehler, isNull);
    });

    test('fragt hoechstens einmal am Tag von selbst', () async {
      final t0 = DateTime(2026, 11, 20, 8);
      await UpdateService.pruefen(installierteVersion: '0.9.0', url: adresse(), jetzt: t0);
      final r = await UpdateService.pruefen(
          installierteVersion: '0.9.0', url: adresse(), jetzt: t0.add(const Duration(hours: 5)));
      expect(r.gedrosselt, isTrue);
      expect(abrufe, 1);

      await UpdateService.pruefen(
          installierteVersion: '0.9.0', url: adresse(), jetzt: t0.add(const Duration(hours: 25)));
      expect(abrufe, 2);
    });

    test('gezieltes Nachsehen umgeht die Drosselung', () async {
      final t0 = DateTime(2026, 11, 20, 8);
      await UpdateService.pruefen(installierteVersion: '0.9.0', url: adresse(), jetzt: t0);
      final r = await UpdateService.pruefen(
          installierteVersion: '0.9.0', url: adresse(), jetzt: t0.add(const Duration(minutes: 1)), manuell: true);
      expect(r.gedrosselt, isFalse);
      expect(abrufe, 2);
    });

    test('ein Serverfehler wird gemeldet und nicht als Pruefung gezaehlt', () async {
      antwortStatus = 404;
      final t0 = DateTime(2026, 11, 20, 8);
      final r = await UpdateService.pruefen(installierteVersion: '0.9.0', url: adresse(), jetzt: t0);
      expect(r.fehler, isNotNull);
      expect(r.angebot, isNull);

      // Beim naechsten Start wird es erneut versucht, statt einen Tag zu warten
      antwortStatus = 200;
      final wieder = await UpdateService.pruefen(
          installierteVersion: '0.9.0', url: adresse(), jetzt: t0.add(const Duration(minutes: 5)));
      expect(wieder.gedrosselt, isFalse);
      expect(wieder.angebot, isNotNull);
    });

    test('eine unlesbare version.json fuehrt zu keinem Angebot', () async {
      antwortText = '<html>Wartung</html>';
      final r = await UpdateService.pruefen(installierteVersion: '0.9.0', url: adresse());
      expect(r.angebot, isNull);
      expect(r.fehler, isNotNull);
    });

    test('uebersprungene Version bleibt still, gezielt gesucht erscheint sie', () async {
      await UpdateService.ueberspringen(AppVersion.parse('0.10.0')!);
      final still = await UpdateService.pruefen(installierteVersion: '0.9.0', url: adresse());
      expect(still.angebot, isNull);
      expect(still.neueste?.version.toString(), '0.10.0');

      final gezielt = await UpdateService.pruefen(installierteVersion: '0.9.0', url: adresse(), manuell: true);
      expect(gezielt.angebot, isNotNull);
    });
  });

  group('Herunterladen', () {
    late Directory ordner;
    late HttpServer server;
    final inhalt = List<int>.generate(200000, (i) => i % 251);

    UpdateInfo info(String pfad, {int? bytes, String? sha}) => UpdateInfo(
          version: AppVersion.parse('0.10.0')!,
          released: '',
          minSdk: 24,
          apkUrl: 'http://127.0.0.1:${server.port}$pfad',
          bytes: bytes,
          sha256: sha,
        );

    List<FileSystemEntity> dateien() => ordner.existsSync() ? ordner.listSync() : [];

    setUp(() async {
      ordner = await Directory.systemTemp.createTemp('update_test_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        try {
          switch (r.uri.path) {
            case '/apk':
              r.response.contentLength = inhalt.length;
              r.response.add(inhalt);
              break;
            case '/ohne-laenge':
              // Kein contentLength gesetzt -> Chunked-Uebertragung
              r.response.add(inhalt.sublist(0, 100000));
              await r.response.flush();
              r.response.add(inhalt.sublist(100000));
              break;
            case '/umleitung':
              // So macht es GitHub: Release-Datei -> anderer Host
              r.response.statusCode = HttpStatus.found;
              r.response.headers.set(HttpHeaders.locationHeader, '/apk');
              break;
            case '/langsam':
              for (var i = 0; i < 20; i++) {
                r.response.add(inhalt.sublist(i * 10000, (i + 1) * 10000));
                await r.response.flush();
                await Future<void>.delayed(const Duration(milliseconds: 30));
              }
              break;
            default:
              r.response.statusCode = HttpStatus.notFound;
          }
          await r.response.close();
        } catch (_) {
          // Der Client darf mittendrin abbrechen
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
      if (ordner.existsSync()) await ordner.delete(recursive: true);
    });

    test('vollstaendiger Download mit Fortschritt', () async {
      final meldungen = <int>[];
      final datei = await UpdateService.herunterladen(
        info('/apk', bytes: inhalt.length),
        ziel: ordner,
        fortschritt: (empfangen, gesamt) {
          meldungen.add(empfangen);
          expect(gesamt, inhalt.length);
        },
      );
      expect(await datei.readAsBytes(), inhalt);
      expect(datei.path, endsWith('.apk'));
      expect(meldungen.last, inhalt.length);
      expect(dateien().where((f) => f.path.endsWith('.part')), isEmpty);
    });

    test('ohne Laengenangabe des Servers hilft die Angabe aus version.json', () async {
      int? gemeldet;
      final datei = await UpdateService.herunterladen(
        info('/ohne-laenge', bytes: inhalt.length),
        ziel: ordner,
        fortschritt: (_, gesamt) => gemeldet = gesamt,
      );
      expect(gemeldet, inhalt.length);
      expect(await datei.length(), inhalt.length);
    });

    test('der Umleitung auf einen anderen Ort wird gefolgt', () async {
      final datei = await UpdateService.herunterladen(info('/umleitung', bytes: inhalt.length), ziel: ordner);
      expect(await datei.readAsBytes(), inhalt);
    });

    test('eine richtige Pruefsumme wird akzeptiert', () async {
      final sha = sha256.convert(inhalt).toString();
      final datei = await UpdateService.herunterladen(info('/apk', bytes: inhalt.length, sha: sha), ziel: ordner);
      expect(await datei.exists(), isTrue);
    });

    test('eine falsche Pruefsumme verhindert die Installation', () async {
      await expectLater(
        UpdateService.herunterladen(info('/apk', bytes: inhalt.length, sha: 'f' * 64), ziel: ordner),
        throwsA(isA<UpdateException>()),
      );
      expect(dateien(), isEmpty, reason: 'keine beschaedigte Datei darf liegenbleiben');
    });

    test('zu wenig Daten fuehren zum Fehler statt zu einer halben APK', () async {
      await expectLater(
        UpdateService.herunterladen(info('/ohne-laenge', bytes: inhalt.length + 5000), ziel: ordner),
        throwsA(isA<UpdateException>()),
      );
      expect(dateien(), isEmpty);
    });

    test('ein Verbindungsabriss mitten im Download hinterlaesst nichts', () async {
      // Rohe Verbindung: Laenge 1000 angekuendigt, 500 geliefert, dann Schluss
      final roh = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      roh.listen((socket) {
        var beantwortet = false;
        socket.listen((_) async {
          if (beantwortet) return;
          beantwortet = true;
          socket.write('HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n'
              'Content-Type: application/octet-stream\r\n\r\n');
          socket.add(List.filled(500, 7));
          await socket.flush();
          await socket.close();
        }, onError: (_) {});
      });

      final abgerissen = UpdateInfo(
        version: AppVersion.parse('0.10.0')!,
        released: '',
        minSdk: 24,
        apkUrl: 'http://127.0.0.1:${roh.port}/apk',
      );
      await expectLater(
        UpdateService.herunterladen(abgerissen, ziel: ordner),
        throwsA(isA<UpdateException>()),
      );
      expect(dateien(), isEmpty);
      await roh.close();
    });

    test('Abbrechen raeumt die Teildatei weg', () async {
      final abbruch = DownloadAbbruch();
      await expectLater(
        UpdateService.herunterladen(
          info('/langsam', bytes: inhalt.length),
          ziel: ordner,
          abbruch: abbruch,
          fortschritt: (empfangen, _) {
            if (empfangen >= 30000) abbruch.abbrechen();
          },
        ),
        throwsA(isA<UpdateAbgebrochen>()),
      );
      expect(dateien(), isEmpty);
    });

    test('ein HTTP-Fehler wird verstaendlich gemeldet', () async {
      await expectLater(
        UpdateService.herunterladen(info('/gibtsnicht'), ziel: ordner),
        throwsA(isA<UpdateException>().having((e) => e.meldung, 'meldung', contains('404'))),
      );
    });

    test('Aufraeumen entfernt alte Downloads', () async {
      await File('${ordner.path}/alt.apk').writeAsString('x');
      await File('${ordner.path}/alt.apk.part').writeAsString('x');
      await UpdateService.aufraeumen(ordner);
      expect(dateien(), isEmpty);
    });
  });
}
