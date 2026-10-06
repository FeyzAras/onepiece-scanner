import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepiece_scanner/image_hash.dart';

/// Baut ein kuenstliches Graustufenbild, bei dem die Helligkeit von links nach rechts steigt.
Uint8List horizontalRamp(int width, int height) {
  final data = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      data[y * width + x] = (x * 255 ~/ (width - 1));
    }
  }
  return data;
}

/// Bild mit einem hellen Block in einer Ecke - zum Pruefen der Drehung.
Uint8List cornerBlock(int width, int height, {required bool topLeft}) {
  final data = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inBlock = topLeft ? (x < width ~/ 2 && y < height ~/ 2) : (x >= width ~/ 2 && y >= height ~/ 2);
      data[y * width + x] = inBlock ? 255 : 0;
    }
  }
  return data;
}

void main() {
  group('Fingerabdruck berechnen', () {
    test('liefert 16 Hex-Zeichen', () {
      final hash = ImageHash.fromYPlane(
        yPlane: horizontalRamp(200, 300),
        rowStride: 200,
        width: 200,
        height: 300,
        rotationDegrees: 0,
        crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
      );
      expect(hash, isNotNull);
      expect(hash!.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hash), isTrue);
    });

    test('gleiches Bild ergibt gleichen Fingerabdruck', () {
      Uint8List makeImage() => horizontalRamp(200, 300);
      String? hashOf(Uint8List data) => ImageHash.fromYPlane(
            yPlane: data,
            rowStride: 200,
            width: 200,
            height: 300,
            rotationDegrees: 0,
            crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
          );
      expect(hashOf(makeImage()), hashOf(makeImage()));
    });

    test('unterschiedliche Bilder ergeben unterschiedliche Fingerabdruecke', () {
      final a = ImageHash.fromYPlane(
        yPlane: cornerBlock(200, 300, topLeft: true),
        rowStride: 200, width: 200, height: 300, rotationDegrees: 0,
        crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
      );
      final b = ImageHash.fromYPlane(
        yPlane: cornerBlock(200, 300, topLeft: false),
        rowStride: 200, width: 200, height: 300, rotationDegrees: 0,
        crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
      );
      expect(a, isNot(b));
    });

    test('gespiegelter Helligkeitsverlauf kehrt jedes Bit um', () {
      // dHash vergleicht benachbarte Pixel. Dreht man den Verlauf um, muss sich
      // jedes einzelne Bit aendern - der Abstand ist dann maximal.
      final ramp = horizontalRamp(200, 300);
      final mirrored = Uint8List(ramp.length);
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 200; x++) {
          mirrored[y * 200 + x] = ramp[y * 200 + (199 - x)];
        }
      }
      String? hashOf(Uint8List data) => ImageHash.fromYPlane(
            yPlane: data, rowStride: 200, width: 200, height: 300, rotationDegrees: 0,
            crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
          );
      expect(ImageHash.distance(hashOf(ramp)!, hashOf(mirrored)!), 64);
    });

    test('zu kleiner Ausschnitt liefert null statt Absturz', () {
      final hash = ImageHash.fromYPlane(
        yPlane: horizontalRamp(200, 300),
        rowStride: 200, width: 200, height: 300, rotationDegrees: 0,
        crop: const CropRect(left: 0.5, top: 0.5, width: 0.01, height: 0.01),
      );
      expect(hash, isNull);
    });

    test('leere Bilddaten liefern null statt Absturz', () {
      final hash = ImageHash.fromYPlane(
        yPlane: Uint8List(0),
        rowStride: 0, width: 0, height: 0, rotationDegrees: 90,
        crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
      );
      expect(hash, isNull);
    });
  });

  group('Drehung', () {
    // Bei 90 Grad Drehung sind Breite und Hoehe der Anzeige getauscht. Ein Ausschnitt,
    // der ohne Drehung ueber den Bildrand hinausginge, muss trotzdem sauber verarbeitet werden.
    test('90 Grad liefert gueltigen Fingerabdruck', () {
      final hash = ImageHash.fromYPlane(
        yPlane: horizontalRamp(1280, 720),
        rowStride: 1280, width: 1280, height: 720, rotationDegrees: 90,
        crop: CropRect.cardCentered(displayAspect: 720 / 1280),
      );
      expect(hash, isNotNull);
      expect(hash!.length, 16);
    });

    test('gedrehtes und ungedrehtes Bild unterscheiden sich', () {
      final data = cornerBlock(400, 400, topLeft: true);
      final plain = ImageHash.fromYPlane(
        yPlane: data, rowStride: 400, width: 400, height: 400, rotationDegrees: 0,
        crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
      );
      final turned = ImageHash.fromYPlane(
        yPlane: data, rowStride: 400, width: 400, height: 400, rotationDegrees: 90,
        crop: const CropRect(left: 0, top: 0, width: 1, height: 1),
      );
      expect(plain, isNot(turned));
    });
  });

  group('Abstand zweier Fingerabdruecke', () {
    test('identisch ergibt 0', () {
      expect(ImageHash.distance('cd0e4f0f3b032b94', 'cd0e4f0f3b032b94'), 0);
    });

    test('ein unterschiedliches Bit ergibt 1', () {
      expect(ImageHash.distance('0000000000000000', '0000000000000001'), 1);
    });

    test('vollstaendig verschieden ergibt 64', () {
      expect(ImageHash.distance('0000000000000000', 'ffffffffffffffff'), 64);
    });

    test('echte Werte zweier Artworks liegen deutlich auseinander', () {
      // aus den Kartendaten: OP01-001 normal gegen Alt-Art
      final d = ImageHash.distance('cd0e4f0f3b032b94', '2f5d0f271f716363');
      expect(d, greaterThan(kAbstandGenugUnterschiedlich));
    });

    test('unterschiedliche Laenge ergibt maximalen Abstand', () {
      expect(ImageHash.distance('abc', 'abcdef0123456789'), 64);
    });
  });
}

/// Ab diesem Abstand gelten zwei Artworks als sicher unterscheidbar.
const int kAbstandGenugUnterschiedlich = 10;
