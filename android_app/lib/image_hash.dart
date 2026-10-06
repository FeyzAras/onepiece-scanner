import 'dart:math' as math;
import 'dart:typed_data';

/// Bild-Fingerabdruck (dHash) zum Unterscheiden von Karten mit gleicher Nummer.
///
/// Hintergrund: Zu sehr vielen Kartennummern gibt es zwei Versionen - normales Artwork und
/// Alt-Art. Nummer und Name sind identisch, nur das Bild unterscheidet sich. Welche Version
/// vor der Kamera liegt, laesst sich deshalb nur am Bild entscheiden.
///
/// Verfahren (identisch zu scripts/build-image-hashes.js, damit die Werte vergleichbar sind):
/// Bildausschnitt auf 9x8 Graustufen verkleinern, je zwei waagerecht benachbarte Pixel
/// vergleichen -> 64 Bit, dargestellt als 16 Hex-Zeichen.
class ImageHash {
  /// Berechnet den Fingerabdruck aus der Helligkeitsebene (Y) eines Kamerabildes.
  ///
  /// [yPlane]      Helligkeitswerte, zeilenweise
  /// [rowStride]   Bytes pro Zeile in [yPlane] (kann groesser als [width] sein)
  /// [width]/[height] Groesse des Sensorbildes
  /// [rotationDegrees] Drehung des Sensorbildes gegenueber der Anzeige (0/90/180/270)
  /// [crop]        Auszuwertender Bereich, in Anteilen des **angezeigten** Bildes (0..1)
  static String? fromYPlane({
    required Uint8List yPlane,
    required int rowStride,
    required int width,
    required int height,
    required int rotationDegrees,
    required CropRect crop,
  }) {
    if (width <= 0 || height <= 0 || yPlane.isEmpty) return null;

    // Groesse des Bildes so, wie es angezeigt wird (bei 90/270 sind Breite und Hoehe getauscht)
    final rotated = rotationDegrees == 90 || rotationDegrees == 270;
    final dispW = rotated ? height : width;
    final dispH = rotated ? width : height;

    final left = (crop.left * dispW).round();
    final top = (crop.top * dispH).round();
    final cropW = (crop.width * dispW).round();
    final cropH = (crop.height * dispH).round();
    if (cropW < 9 || cropH < 8) return null;

    // 9x8 Rasterpunkte innerhalb des Ausschnitts abtasten
    final samples = Uint8List(9 * 8);
    for (var gy = 0; gy < 8; gy++) {
      for (var gx = 0; gx < 9; gx++) {
        final dx = left + ((gx + 0.5) * cropW / 9).floor();
        final dy = top + ((gy + 0.5) * cropH / 8).floor();
        final value = _sampleDisplayed(
          yPlane: yPlane,
          rowStride: rowStride,
          width: width,
          height: height,
          rotationDegrees: rotationDegrees,
          dispX: dx,
          dispY: dy,
        );
        samples[gy * 9 + gx] = value;
      }
    }

    final bits = StringBuffer();
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        bits.write(samples[row * 9 + col] > samples[row * 9 + col + 1] ? '1' : '0');
      }
    }
    final raw = bits.toString();
    final hex = StringBuffer();
    for (var i = 0; i < 64; i += 4) {
      hex.write(int.parse(raw.substring(i, i + 4), radix: 2).toRadixString(16));
    }
    return hex.toString();
  }

  /// Rechnet einen Punkt der Anzeige in Sensorkoordinaten zurueck und liest den Helligkeitswert.
  static int _sampleDisplayed({
    required Uint8List yPlane,
    required int rowStride,
    required int width,
    required int height,
    required int rotationDegrees,
    required int dispX,
    required int dispY,
  }) {
    int sx;
    int sy;
    switch (rotationDegrees) {
      case 90:
        sx = dispY;
        sy = height - 1 - dispX;
        break;
      case 180:
        sx = width - 1 - dispX;
        sy = height - 1 - dispY;
        break;
      case 270:
        sx = width - 1 - dispY;
        sy = dispX;
        break;
      default:
        sx = dispX;
        sy = dispY;
    }
    sx = sx.clamp(0, width - 1);
    sy = sy.clamp(0, height - 1);
    final index = sy * rowStride + sx;
    if (index < 0 || index >= yPlane.length) return 0;
    return yPlane[index];
  }

  /// Anzahl unterschiedlicher Bits zweier Fingerabdruecke (0 = identisch, 64 = maximal verschieden).
  static int distance(String a, String b) {
    if (a.length != b.length) return 64;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      final x = int.tryParse(a[i], radix: 16);
      final y = int.tryParse(b[i], radix: 16);
      if (x == null || y == null) return 64;
      diff += _bitCount4(x ^ y);
    }
    return diff;
  }

  static int _bitCount4(int v) {
    var n = v & 0xF;
    var count = 0;
    while (n != 0) {
      count += n & 1;
      n >>= 1;
    }
    return count;
  }
}

/// Ausschnitt in Anteilen (0..1) des angezeigten Bildes.
class CropRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const CropRect({required this.left, required this.top, required this.width, required this.height});

  /// Mittiger Ausschnitt im Kartenformat 63:88 - passend zum Sucherrahmen der App.
  /// [widthFraction] ist die Breite des Rahmens im Verhaeltnis zur Bildbreite,
  /// [verticalShift] verschiebt ihn nach oben (negativ) bzw. unten.
  factory CropRect.cardCentered({
    required double displayAspect, // Breite / Hoehe des angezeigten Bildes
    double widthFraction = 0.68,
    double verticalShift = -0.10,
  }) {
    final w = widthFraction;
    // Hoehe in Anteilen: Rahmenhoehe = Rahmenbreite * 88/63, umgerechnet aufs Bildseitenverhaeltnis
    final h = math.min(1.0, w * (88 / 63) * displayAspect);
    final left = (1 - w) / 2;
    final top = ((1 - h) / 2 + verticalShift).clamp(0.0, 1.0 - h);
    return CropRect(left: left, top: top, width: w, height: h);
  }
}
