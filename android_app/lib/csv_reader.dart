import 'dart:convert';

/// Liest CSV-Dateien, die aus ganz unterschiedlichen Quellen kommen koennen:
/// aus der eigenen Sicherung, aus Excel, aus einem Cardmarket-Export.
///
/// Bewusst selbst geschrieben statt als Paket eingebunden: Es geht um rund hundert
/// Zeilen, die sich vollstaendig testen lassen, und das Projekt kommt auch sonst ohne
/// Zusatzpakete aus, wo es sich vermeiden laesst (siehe die Netzzugriffe, die direkt
/// auf `HttpClient` aufsetzen statt auf `http`).
class CsvReader {
  /// Welche Trennzeichen ueberhaupt in Frage kommen, in der Reihenfolge der
  /// Wahrscheinlichkeit fuer dieses Projekt.
  static const _kandidaten = [';', '\t', ','];

  /// Macht aus den Rohbytes einer Datei Text.
  ///
  /// Zwei Fallstricke stecken hier drin:
  /// * Der eigene Export schreibt UTF-8 **mit** BOM, damit Excel die Umlaute richtig
  ///   anzeigt. Das BOM muss wieder weg, sonst heisst die erste Spalte nicht
  ///   "Kartennummer", sondern "﻿Kartennummer".
  /// * Von Excel gespeicherte Dateien sind oft Windows-1252. Ohne Rueckfall kaeme
  ///   jeder Umlaut als Fragezeichen durch - und in Ordnernamen bliebe er so stehen.
  static String decodeBytes(List<int> bytes) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // latin1 unterscheidet sich von Windows-1252 nur im Bereich 0x80-0x9F und
      // rettet die Umlaute zuverlaessig.
      text = latin1.decode(bytes);
    }
    return stripBom(text);
  }

  static String stripBom(String text) =>
      text.startsWith('﻿') ? text.substring(1) : text;

  /// Raet das Trennzeichen anhand der ersten brauchbaren Zeile.
  ///
  /// Gezaehlt wird nur **ausserhalb** von Anfuehrungszeichen - sonst gewinnt bei
  /// `Zoro; der "Beste"` das Semikolon aus dem Kartennamen.
  static String sniffSeparator(String text) {
    for (final zeile in const LineSplitter().convert(text)) {
      if (zeile.trim().isEmpty || zeile.startsWith('#')) continue;
      var bestes = _kandidaten.first;
      var meiste = 0;
      for (final kandidat in _kandidaten) {
        final anzahl = _countOutsideQuotes(zeile, kandidat);
        if (anzahl > meiste) {
          meiste = anzahl;
          bestes = kandidat;
        }
      }
      return bestes;
    }
    return _kandidaten.first;
  }

  static int _countOutsideQuotes(String zeile, String zeichen) {
    var inQuotes = false;
    var anzahl = 0;
    for (var i = 0; i < zeile.length; i++) {
      final c = zeile[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && c == zeichen) {
        anzahl++;
      }
    }
    return anzahl;
  }

  /// Zerlegt den Text in Zeilen und Felder.
  ///
  /// Beherrscht Anfuehrungszeichen, verdoppelte Anfuehrungszeichen (`""` = ein `"`),
  /// Zeilenumbrueche innerhalb eines Feldes und CRLF. Zeilen, die mit `#` beginnen,
  /// werden uebersprungen - der eigene Export stellt dort den Preisstand voran.
  static List<List<String>> parse(String text, {String? separator}) {
    final roh = stripBom(text).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final trenn = separator ?? sniffSeparator(roh);

    final zeilen = <List<String>>[];
    var felder = <String>[];
    final feld = StringBuffer();
    var inQuotes = false;
    var zeileLeer = true;

    void feldAbschliessen() {
      felder.add(feld.toString());
      feld.clear();
    }

    void zeileAbschliessen() {
      feldAbschliessen();
      // Vollstaendig leere Zeilen weglassen (haeufig am Dateiende)
      if (!(felder.length == 1 && felder.first.trim().isEmpty)) {
        zeilen.add(felder);
      }
      felder = <String>[];
      zeileLeer = true;
    }

    for (var i = 0; i < roh.length; i++) {
      final c = roh[i];

      // Kommentarzeile: bis zum Zeilenende ueberspringen
      if (zeileLeer && !inQuotes && c == '#' && felder.isEmpty && feld.isEmpty) {
        while (i < roh.length && roh[i] != '\n') {
          i++;
        }
        continue;
      }

      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < roh.length && roh[i + 1] == '"') {
            feld.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          feld.write(c);
        }
        continue;
      }

      if (c == '"' && feld.isEmpty) {
        inQuotes = true;
        zeileLeer = false;
      } else if (c == trenn) {
        feldAbschliessen();
        zeileLeer = false;
      } else if (c == '\n') {
        zeileAbschliessen();
      } else {
        feld.write(c);
        if (c.trim().isNotEmpty) zeileLeer = false;
      }
    }

    if (feld.isNotEmpty || felder.isNotEmpty) zeileAbschliessen();
    return zeilen;
  }

  /// Ordnet Spaltennamen ihrer Position zu - kleingeschrieben und ohne Leerraum,
  /// damit `Anzahl`, `anzahl` und ` Anzahl ` dasselbe treffen.
  ///
  /// Immer ueber Namen lesen, nie ueber die Position: Cardmarket hat seinen
  /// Spaltensatz ueber die Jahre mehrfach geaendert.
  static Map<String, int> headerIndex(List<String> kopfzeile) {
    final map = <String, int>{};
    for (var i = 0; i < kopfzeile.length; i++) {
      final name = kopfzeile[i].trim().toLowerCase();
      if (name.isNotEmpty && !map.containsKey(name)) map[name] = i;
    }
    return map;
  }

  /// Sucht die erste Spalte, deren Name zu einem der Synonyme passt.
  static int? findColumn(Map<String, int> index, List<String> synonyme) {
    for (final s in synonyme) {
      final treffer = index[s.toLowerCase()];
      if (treffer != null) return treffer;
    }
    return null;
  }

  /// Feldwert einer Zeile, oder leer wenn die Spalte fehlt oder die Zeile kuerzer ist.
  static String field(List<String> zeile, int? index) {
    if (index == null || index < 0 || index >= zeile.length) return '';
    return zeile[index].trim();
  }
}
