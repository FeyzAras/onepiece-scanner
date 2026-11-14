import 'dart:convert';

import 'card_model.dart';

/// Name eines Sets aus `assets/sets.json`.
class SetInfo {
  final String code;

  /// Offizieller Produktname, z.B. "Romance Dawn". Null, wenn das Set kein eigenes
  /// Produkt ist - die EB04-Karten etwa stecken in zwei verschiedenen Boostern.
  final String? name;

  /// Produkte, in denen die Karten dieses Sets enthalten sind, falls es keinen
  /// eigenen Namen gibt.
  final List<String> enthalten;

  const SetInfo({required this.code, this.name, this.enthalten = const []});

  String get anzeigename {
    if (name != null && name!.isNotEmpty) return name!;
    if (enthalten.isNotEmpty) return 'enthalten in ${enthalten.join(' und ')}';
    return code;
  }

  /// Liest `assets/sets.json`. Unbrauchbare Eintraege werden uebersprungen.
  static Map<String, SetInfo> parseAll(String raw) {
    try {
      final liste = jsonDecode(raw);
      if (liste is! List) return const {};
      final ergebnis = <String, SetInfo>{};
      for (final e in liste.whereType<Map>()) {
        final code = e['code'];
        if (code is! String || code.isEmpty) continue;
        final enthalten = e['enthalten'];
        ergebnis[code] = SetInfo(
          code: code,
          name: e['name'] is String ? e['name'] as String : null,
          enthalten: enthalten is List ? enthalten.map((x) => '$x').toList() : const [],
        );
      }
      return ergebnis;
    } catch (_) {
      return const {};
    }
  }
}

/// Wie weit ein Set gesammelt ist.
class SetFortschritt {
  final String code;
  final SetInfo? info;

  /// Grundkarten = normales Artwork. Danach zaehlt ein Set als komplett.
  final int grundGesamt;
  final int grundBesessen;

  /// Alt-Arts werden getrennt gezaehlt - wie bei Sammlern ueblich. Sie machen ein Set
  /// nicht "unvollstaendig", sind aber eine eigene Jagd.
  final int altGesamt;
  final int altBesessen;

  /// Fehlende Grundkarten, guenstigste zuerst.
  final List<OpCard> fehlend;

  /// Was es zum aktuellen Preis kosten wuerde, die Grundkarten zu komplettieren.
  final double kostenKomplett;

  /// Wie viele der fehlenden Karten keinen Preis haben - dann ist [kostenKomplett]
  /// eine Untergrenze.
  final int ohnePreis;

  const SetFortschritt({
    required this.code,
    required this.info,
    required this.grundGesamt,
    required this.grundBesessen,
    required this.altGesamt,
    required this.altBesessen,
    required this.fehlend,
    required this.kostenKomplett,
    required this.ohnePreis,
  });

  double get anteil => grundGesamt == 0 ? 0 : grundBesessen / grundGesamt;
  bool get komplett => grundGesamt > 0 && grundBesessen >= grundGesamt;
  bool get angefangen => grundBesessen > 0 || altBesessen > 0;
  String get anzeigename => info?.anzeigename ?? code;
}

class SetProgress {
  /// Berechnet den Fortschritt je Set.
  ///
  /// [besessen] enthaelt die Karten-IDs der Sammlung - Dubletten zaehlen einmal.
  /// Karten, die nur auf Japanisch erschienen sind, zaehlen nicht zur Gesamtzahl:
  /// Die Erkennung ist auf den englischen Druck ausgelegt, und ein englisches Set waere
  /// sonst nie komplett.
  ///
  /// Sortierung: angefangene Sets nach Fortschritt, danach die uebrigen nach Code.
  static List<SetFortschritt> berechnen({
    required List<OpCard> katalog,
    required Set<String> besessen,
    required double Function(OpCard card) preisVon,
    Map<String, SetInfo> infos = const {},
  }) {
    final proSet = <String, List<OpCard>>{};
    for (final karte in katalog) {
      if (karte.jpOnly) continue;
      proSet.putIfAbsent(karte.setCode, () => []).add(karte);
    }

    final ergebnis = <SetFortschritt>[];
    for (final eintrag in proSet.entries) {
      var grundGesamt = 0, grundBesessen = 0, altGesamt = 0, altBesessen = 0, ohnePreis = 0;
      var kosten = 0.0;
      final fehlend = <OpCard>[];

      for (final karte in eintrag.value) {
        final hat = besessen.contains(karte.id);
        if (karte.alt) {
          altGesamt++;
          if (hat) altBesessen++;
        } else {
          grundGesamt++;
          if (hat) {
            grundBesessen++;
          } else {
            fehlend.add(karte);
            final preis = preisVon(karte);
            if (preis > 0) {
              kosten += preis;
            } else {
              ohnePreis++;
            }
          }
        }
      }

      fehlend.sort((a, b) {
        final p = preisVon(a).compareTo(preisVon(b));
        return p != 0 ? p : a.id.compareTo(b.id);
      });

      ergebnis.add(SetFortschritt(
        code: eintrag.key,
        info: infos[eintrag.key],
        grundGesamt: grundGesamt,
        grundBesessen: grundBesessen,
        altGesamt: altGesamt,
        altBesessen: altBesessen,
        fehlend: fehlend,
        kostenKomplett: kosten,
        ohnePreis: ohnePreis,
      ));
    }

    ergebnis.sort((a, b) {
      if (a.angefangen != b.angefangen) return a.angefangen ? -1 : 1;
      if (a.angefangen) {
        final p = b.anteil.compareTo(a.anteil);
        if (p != 0) return p;
      }
      return a.code.compareTo(b.code);
    });
    return ergebnis;
  }
}
