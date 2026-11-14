import 'package:flutter/foundation.dart';

import 'card_model.dart';

/// Karten, die der Nutzer noch sucht - je Karten-ID, wie viele Exemplare noch fehlen.
///
/// Ein gemeinsames Modell fuer alle Ansichten: Wer einen Stern setzt, sieht ihn sofort
/// ueberall, auch in einer gerade geoeffneten Set- oder Deck-Ansicht.
///
/// Gespeichert wird ueber [onAenderung] - aber nur bei echten Aenderungen, nie beim
/// [laden]. Sonst wuerde schon das Einlesen beim Start einen Speichervorgang ausloesen,
/// womoeglich bevor die Sammlung selbst geladen ist.
class Wunschliste extends ChangeNotifier {
  Wunschliste({this.onAenderung});

  VoidCallback? onAenderung;

  Map<String, int> _eintraege = {};

  Map<String, int> get eintraege => Map.unmodifiable(_eintraege);

  int anzahl(String cardId) => _eintraege[cardId] ?? 0;
  bool enthaelt(String cardId) => anzahl(cardId) > 0;

  /// Verschiedene Karten.
  int get verschiedene => _eintraege.length;

  /// Alle gesuchten Exemplare zusammen.
  int get exemplare => _eintraege.values.fold(0, (s, n) => s + n);

  bool get leer => _eintraege.isEmpty;

  /// Gespeicherten Stand uebernehmen - ohne Speichervorgang.
  void laden(Map<String, int> daten) {
    _eintraege = {
      for (final e in daten.entries)
        if (e.value > 0) e.key: e.value,
    };
    notifyListeners();
  }

  /// Setzt die Anzahl fuer eine Karte. 0 entfernt sie.
  void setzen(String cardId, int anzahl) {
    final vorher = _eintraege[cardId] ?? 0;
    final neu = anzahl.clamp(0, 99);
    if (neu == vorher) return;
    if (neu == 0) {
      _eintraege.remove(cardId);
    } else {
      _eintraege[cardId] = neu;
    }
    _geaendert();
  }

  /// Nimmt mehrere Karten auf und gibt zurueck, wie viele Eintraege sich geaendert haben.
  ///
  /// Je Karte gilt die **groessere** Anzahl, nicht die Summe: Wer eine Karte einmal fuer
  /// ein Set und dreimal fuer ein Deck braucht, braucht drei - nicht vier.
  int hinzufuegen(Map<String, int> neu) {
    final ergebnis = zusammenfuehren(_eintraege, neu);
    var geaendert = 0;
    for (final e in ergebnis.entries) {
      if (_eintraege[e.key] != e.value) geaendert++;
    }
    if (geaendert == 0) return 0;
    _eintraege = ergebnis;
    _geaendert();
    return geaendert;
  }

  /// Nach einem Scan: die gescannte Karte von der Wunschliste streichen.
  ///
  /// Zuerst genau diese Karte. Ist eine Alt-Art gescannt worden und die Normalversion
  /// gesucht, zaehlt sie ebenfalls - fuers Spielen ist das Artwork egal, und eine Alt-Art
  /// ist eher mehr als weniger. Umgekehrt nicht: Wer die Alt-Art sucht, will die Alt-Art.
  ///
  /// Gibt die gestrichene Karten-ID zurueck, oder null.
  String? abhaken(OpCard gescannt) {
    String? treffer;
    if (enthaelt(gescannt.id)) {
      treffer = gescannt.id;
    } else if (gescannt.alt && enthaelt(gescannt.baseId)) {
      treffer = gescannt.baseId;
    }
    if (treffer == null) return null;
    setzen(treffer, anzahl(treffer) - 1);
    return treffer;
  }

  void leeren() {
    if (_eintraege.isEmpty) return;
    _eintraege = {};
    _geaendert();
  }

  void _geaendert() {
    notifyListeners();
    onAenderung?.call();
  }

  // ----------------------------------------------------------- reine Hilfen

  static Map<String, int> zusammenfuehren(Map<String, int> liste, Map<String, int> neu) {
    final ergebnis = {...liste};
    for (final e in neu.entries) {
      if (e.value <= 0) continue;
      final vorher = ergebnis[e.key] ?? 0;
      if (e.value > vorher) ergebnis[e.key] = e.value.clamp(1, 99);
    }
    return ergebnis;
  }

  /// "4xOP01-001 2xST01-002" - das Format, das Deck-Seiten, Simulatoren und Haendler
  /// verstehen, und das der eigene Import wieder einliest.
  static String alsDeckliste(Map<String, int> liste) {
    final ids = liste.keys.toList()..sort();
    return ids.map((id) => '${liste[id]}x$id').join('\n');
  }

  /// Was die Liste zum aktuellen Preis kostet, und wie viele Karten keinen Preis haben.
  static ({double summe, int ohnePreis}) kosten(
    Map<String, int> liste,
    OpCard? Function(String id) karteVon,
    double Function(OpCard card) preisVon,
  ) {
    var summe = 0.0;
    var ohnePreis = 0;
    liste.forEach((id, n) {
      final karte = karteVon(id);
      final preis = karte == null ? 0.0 : preisVon(karte);
      if (preis > 0) {
        summe += preis * n;
      } else {
        ohnePreis++;
      }
    });
    return (summe: summe, ohnePreis: ohnePreis);
  }
}
