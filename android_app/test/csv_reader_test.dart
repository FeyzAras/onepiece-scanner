import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/csv_reader.dart';

/// Die CSV-Dateien, die hier ankommen, stammen aus fremden Haenden: aus Excel,
/// aus einem Cardmarket-Export, aus einem Chat-Anhang. Jede davon hat ihre eigenen
/// Eigenheiten - Trennzeichen, Kodierung, Anfuehrungszeichen.
///
/// Diese Tests halten fest, womit der Leser umgehen koennen muss.
void main() {
  group('Zerlegen', () {
    test('einfache Zeilen mit Semikolon', () {
      final z = CsvReader.parse('a;b;c\n1;2;3\n');
      expect(z.length, 2);
      expect(z[0], ['a', 'b', 'c']);
      expect(z[1], ['1', '2', '3']);
    });

    test('Semikolon im gequoteten Feld trennt nicht', () {
      final z = CsvReader.parse('Nummer;Name\nOP01-001;"Zoro; der Beste"\n');
      expect(z[1], ['OP01-001', 'Zoro; der Beste']);
    });

    test('verdoppeltes Anfuehrungszeichen wird zu einem', () {
      final z = CsvReader.parse('Name\n"Zoro ""der Beste"""\n');
      expect(z[1].single, 'Zoro "der Beste"');
    });

    test('Zeilenumbruch im Feld beendet die Zeile nicht', () {
      final z = CsvReader.parse('a;b\n"erste\nzweite";x\n');
      expect(z.length, 2);
      expect(z[1][0], 'erste\nzweite');
      expect(z[1][1], 'x');
    });

    test('CRLF wird wie ein einfacher Umbruch behandelt', () {
      final z = CsvReader.parse('a;b\r\n1;2\r\n');
      expect(z.length, 2);
      expect(z[1], ['1', '2']);
    });

    test('BOM verschwindet aus der ersten Spalte', () {
      final z = CsvReader.parse('﻿Kartennummer;Name\nOP01-001;Zoro');
      expect(z[0][0], 'Kartennummer');
    });

    test('leere Schlusszeile erzeugt keine Geisterzeile', () {
      expect(CsvReader.parse('a;b\n1;2\n\n').length, 2);
      expect(CsvReader.parse('a;b\n1;2').length, 2);
    });

    test('abschliessendes Trennzeichen ergibt ein leeres Feld', () {
      expect(CsvReader.parse('a;b;c\n1;2;\n')[1], ['1', '2', '']);
    });

    test('Kommentarzeilen werden uebersprungen', () {
      final z = CsvReader.parse('# Stand 2026-11-12\nKartennummer;Name\nOP01-001;Zoro\n');
      expect(z.length, 2);
      expect(z[0][0], 'Kartennummer');
    });

    test('ein # mitten in der Datei ist kein Kommentar', () {
      final z = CsvReader.parse('a;b\nOP01-001;Nr #4\n');
      expect(z[1][1], 'Nr #4');
    });
  });

  group('Trennzeichen erkennen', () {
    test('Semikolon', () => expect(CsvReader.sniffSeparator('a;b;c\n1;2;3'), ';'));
    test('Komma', () => expect(CsvReader.sniffSeparator('a,b,c\n1,2,3'), ','));
    test('Tabulator', () => expect(CsvReader.sniffSeparator('a\tb\tc'), '\t'));

    test('Komma im Feld schlaegt das Semikolon nicht', () {
      expect(CsvReader.sniffSeparator('Nummer;Preis\nOP01-001;1,87'), ';');
    });

    test('Trennzeichen in Anfuehrungszeichen zaehlen nicht mit', () {
      expect(CsvReader.sniffSeparator('"a,b,c,d,e";x;y'), ';');
    });

    test('Kommentarzeile wird fuer die Erkennung uebergangen', () {
      expect(CsvReader.sniffSeparator('# ein, Kommentar, mit, Kommas\na;b;c'), ';');
    });
  });

  group('Kodierung', () {
    test('UTF-8 mit BOM wird sauber gelesen', () {
      final bytes = utf8.encode('﻿Ordner;Name\nDoppelte;Grüße');
      expect(CsvReader.decodeBytes(bytes), 'Ordner;Name\nDoppelte;Grüße');
    });

    test('Windows-1252 aus Excel zerstoert keine Umlaute', () {
      // 'Grüße' in latin1 - als UTF-8 gelesen waere das ein Formatfehler
      final bytes = latin1.encode('Ordner;Name\nDoppelte;Grüße');
      expect(CsvReader.decodeBytes(bytes), contains('Grüße'));
    });
  });

  group('Spalten finden', () {
    final index = CsvReader.headerIndex(['Kartennummer', ' Anzahl ', 'Ordner-ID']);

    test('Namen werden unabhaengig von Schreibweise und Leerraum getroffen', () {
      expect(CsvReader.findColumn(index, ['anzahl']), 1);
      expect(CsvReader.findColumn(index, ['KARTENNUMMER']), 0);
    });

    test('Synonyme werden der Reihe nach probiert', () {
      expect(CsvReader.findColumn(index, ['quantity', 'menge', 'anzahl']), 1);
      expect(CsvReader.findColumn(index, ['gibtsnicht']), isNull);
    });

    test('zu kurze Zeilen liefern leere Felder statt eines Absturzes', () {
      expect(CsvReader.field(['OP01-001'], 2), '');
      expect(CsvReader.field(['OP01-001'], null), '');
      expect(CsvReader.field(['OP01-001', ' 3 '], 1), '3');
    });
  });
}
