import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/card_model.dart';
import 'package:onepiece_scanner/card_versions.dart';
import 'package:onepiece_scanner/collection_store.dart';
import 'package:onepiece_scanner/collection_view.dart';

/// Die Kartendetails mit Motiven und Cardmarket-Versionen - in Handygroesse aufgebaut,
/// damit Ueberlaeufe im Layout als Fehler auffallen.
void main() {
  OpCard karte(String id, {double? preis, int? idProduct, String rarity = 'R'}) => OpCard(
        id: id,
        baseId: 'OP17-040',
        alt: id != 'OP17-040',
        name: 'Edward.Newgate',
        rarity: rarity,
        cardType: 'CHARACTER',
        effect: '',
        produkt: "The World’s Strongest Warriors",
        produktSets: const ['OP17'],
        price: preis == null
            ? null
            : CardPrice(
                amount: preis,
                currency: 'EUR',
                basis: 'trend',
                source: 'cardmarket',
                asOf: '2026-11-24',
                idProduct: idProduct,
                confidence: PriceConfidence.paar,
              ),
      );

  final normal = karte('OP17-040', preis: 0.16, idProduct: 904022);
  final parallele = karte('OP17-040-ALT', preis: 25.50, idProduct: 904023, rarity: 'TR');
  final versionen = VersionsDaten.parse('''
{"asOf":"2026-11-24",
 "ausgaben":{"6492":"The World's Strongest Warriors","6723":"The World's Strongest Warriors (Asia Region Legal)","6772":"The Dominance of God"},
 "versionen":{"OP17-040":[[904855,6723,6],[904022,6492,16,[0]],[904023,6492,2550,[1]],[923820,6772,7446]]}}
''')!;

  CollectionEntry eintrag(OpCard k) => CollectionEntry(card: k, folderId: 'default', how: 'number', at: DateTime(2026, 11, 24));

  late List<(List<CollectionEntry>, OpCard, bool)> umgestellt;
  late List<(OpCard, KartenVersion?)> gewaehlt;

  Future<void> aufbauen(WidgetTester tester, List<CollectionEntry> eintraege, {Map<String, int> wahl = const {}}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    umgestellt = [];
    gewaehlt = [];
    double preis(OpCard k) {
      final w = wahl[k.id];
      if (w != null) return versionen.produkt(k.baseId, w)!.preis;
      return k.price?.amount ?? 0;
    }

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: CollectionView(
          entries: eintraege,
          folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
          onRemoveOne: (_, _) {},
          onSwitchArtwork: (e, r, {bool wahlZuruecksetzen = false}) => umgestellt.add((e, r, wahlZuruecksetzen)),
          variantsOf: (_) => [parallele, normal],
          onManageFolders: () {},
          onImport: () {},
          priceOf: preis,
          versionenVon: (k) => versionen.von(k.baseId),
          wahlVon: (k) => wahl[k.id],
          onWaehleVersion: (k, v) => gewaehlt.add((k, v)),
          priceAsOf: '2026-11-24',
        ),
      ),
    ));
    await tester.tap(find.text('Edward.Newgate').first);
    await tester.pumpAndSettle();
  }

  Future<void> sichtbarTippen(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('zeigt alle Motive und alle Versionen mit Ausgabe und Preis', (tester) async {
    await aufbauen(tester, [eintrag(normal)]);
    expect(find.text('Motiv · 2 Versionen dieser Nummer'), findsOneWidget);
    expect(find.text('✓ Normal'), findsOneWidget);
    // Einmal unter dem Motivbild, einmal an seiner Cardmarket-Version
    expect(find.text('Parallele'), findsNWidgets(2));
    expect(find.text('Welche Version hast du?'), findsOneWidget);
    expect(find.text("The World's Strongest Warriors"), findsOneWidget);
    expect(find.text("The World's Strongest Warriors (Asia Region Legal)"), findsOneWidget);
    expect(find.text('The Dominance of God'), findsOneWidget);
    expect(find.text('Normal · automatisch'), findsOneWidget);
    expect(find.text('0,06 €'), findsOneWidget);
    expect(find.text('25,50 €'), findsOneWidget);
    expect(find.text('74,46 €'), findsOneWidget);
    expect(find.text('automatisch, Normal und Parallele unterschieden'), findsOneWidget);
  });

  testWidgets('eine Version ohne Motiv wird fuer diese Karte gemerkt', (tester) async {
    await aufbauen(tester, [eintrag(normal)]);
    await sichtbarTippen(tester, find.text('0,06 €'));
    expect(gewaehlt.single.$1.id, 'OP17-040');
    expect(gewaehlt.single.$2!.idProduct, 904855);
    expect(umgestellt, isEmpty);
  });

  testWidgets('die Version der Parallele stellt das Motiv um', (tester) async {
    await aufbauen(tester, [eintrag(normal)]);
    await sichtbarTippen(tester, find.text('25,50 €'));
    expect(umgestellt.single.$2.id, 'OP17-040-ALT');
    expect(umgestellt.single.$3, isTrue, reason: 'eine fruehere Wahl fuer die Parallele gilt nicht mehr');
    expect(gewaehlt, isEmpty);
  });

  testWidgets('bei mehreren Exemplaren wird gefragt, wie viele umgestellt werden', (tester) async {
    final a = eintrag(normal), b = eintrag(normal), c = eintrag(normal);
    // Das erste "Parallele" ist das Motivbild (der Abschnitt steht ueber den Versionen)
    final motivParallele = find.text('Parallele').first;
    await aufbauen(tester, [a, b, c]);
    await sichtbarTippen(tester, motivParallele);
    expect(find.text('Welche Exemplare?'), findsOneWidget);
    await tester.tap(find.text('Nur eins'));
    await tester.pumpAndSettle();
    expect(umgestellt.single.$1, hasLength(1));
    expect(umgestellt.single.$3, isFalse, reason: 'Motiv gewaehlt, nicht eine Version');

    await aufbauen(tester, [a, b, c]);
    await sichtbarTippen(tester, motivParallele);
    await tester.tap(find.text('Alle 3'));
    await tester.pumpAndSettle();
    expect(umgestellt.single.$1, hasLength(3));
  });

  testWidgets('eigene Wahl wird angezeigt und laesst sich zuruecksetzen', (tester) async {
    await aufbauen(tester, [eintrag(normal)], wahl: const {'OP17-040': 904855});
    expect(find.text('von dir gewählt'), findsOneWidget);
    // Der Preis oben kommt aus der gewaehlten Version
    expect(find.text('0,06 €'), findsWidgets);
    await sichtbarTippen(tester, find.text('zurücksetzen'));
    expect(gewaehlt.single.$2, isNull);
  });

  testWidgets('ein Motiv ohne zugeordnete Version bittet um die Wahl', (tester) async {
    final ohnePreis = karte('OP17-040-ALT2');
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CollectionView(
          entries: [eintrag(ohnePreis)],
          folders: const [ScanFolder(id: 'default', name: 'Meine Sammlung')],
          onRemoveOne: (_, _) {},
          onSwitchArtwork: (_, _, {bool wahlZuruecksetzen = false}) {},
          variantsOf: (_) => [normal, parallele, ohnePreis],
          onManageFolders: () {},
          onImport: () {},
          priceOf: (_) => 0,
          versionenVon: (k) => versionen.von(k.baseId),
          wahlVon: (_) => null,
          onWaehleVersion: (_, _) {},
          priceAsOf: '',
        ),
      ),
    ));
    expect(find.text('–'), findsOneWidget, reason: 'Kachel ohne Preis');
    await tester.tap(find.text('Edward.Newgate').first);
    await tester.pumpAndSettle();
    expect(find.text('kein Preis'), findsOneWidget);
    expect(find.text('keine Version zugeordnet – bitte wählen'), findsOneWidget);
  });
}
