import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_model.dart';
import 'price_history.dart';
import 'widgets.dart';

/// Preisverlauf einer Karte fuer die Kartendetails. Laedt nur das Set dieser Karte.
class KartenPreisVerlauf extends StatefulWidget {
  final OpCard card;
  final HistoryStore store;

  /// true, wenn der Nutzer fuer diese Karte eine andere Druckvariante gewaehlt hat -
  /// dann zeigt der Verlauf nicht die Version, mit der die Sammlung rechnet.
  final bool eigeneWahl;

  const KartenPreisVerlauf({super.key, required this.card, required this.store, this.eigeneWahl = false});

  @override
  State<KartenPreisVerlauf> createState() => _KartenPreisVerlaufState();
}

class _KartenPreisVerlaufState extends State<KartenPreisVerlauf> {
  List<PreisPunkt>? _punkte;

  @override
  void initState() {
    super.initState();
    widget.store.laden(widget.card.setCode).then((h) {
      if (mounted) setState(() => _punkte = h?.verlaufVon(widget.card.id) ?? const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final punkte = _punkte;
    if (punkte == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('Preisverlauf wird geladen …', style: TextStyle(color: kDim, fontSize: 11.5)),
      );
    }
    if (punkte.length < 2) return const SizedBox.shrink();

    final tief = punkte.reduce((a, b) => a.wert <= b.wert ? a : b);
    final hoch = punkte.reduce((a, b) => a.wert >= b.wert ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Preisverlauf seit ${datumKurz(punkte.first.datum, mitJahr: true)}',
            style: const TextStyle(fontSize: 12, color: kDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        LinienDiagramm(punkte: punkte, hoehe: 110, kompakt: true),
        const SizedBox(height: 6),
        // Die Extremwerte auch als Text - das Diagramm ist nie der einzige Weg zur Zahl
        Text(
          'Tiefst ${formatEuro(tief.wert)} am ${datumKurz(tief.datum)} · '
          'Höchst ${formatEuro(hoch.wert)} am ${datumKurz(hoch.datum)}',
          style: const TextStyle(fontSize: 11, color: kDim),
        ),
        if (widget.eigeneWahl)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Zeigt die automatisch zugeordnete Version — du hast eine andere gewählt.',
              style: TextStyle(fontSize: 10.5, color: kDim),
            ),
          ),
      ],
    );
  }
}

/// Liniendiagramm fuer einen Verlauf in Euro - ohne Zusatzpaket.
///
/// Gestaltung nach den dataviz-Regeln: 2-px-Linie mit runden Enden, Flaeche als Hauch
/// (10 %), Endpunkt mit Ring in der Flaechenfarbe, haarduenne durchgezogene Hilfslinien,
/// Achsenbeschriftung in Textfarbe statt in der Linienfarbe. Eine einzelne Reihe braucht
/// keine Legende - der Titel ueber dem Diagramm sagt, was es zeigt.
///
/// Antippen oder Wischen zeigt eine senkrechte Linie, die auf den naechsten Tag
/// einrastet, mit Wert und Datum. Niemand muss eine 2-px-Linie treffen.
class LinienDiagramm extends StatefulWidget {
  final List<PreisPunkt> punkte;

  /// Hoehe der Zeichenflaeche, ohne die Datumsleiste darunter.
  final double hoehe;

  /// Farbe der Flaeche, auf der das Diagramm liegt - fuer den Ring um die Punkte.
  final Color flaeche;

  final bool kompakt;

  const LinienDiagramm({
    super.key,
    required this.punkte,
    this.hoehe = 160,
    this.flaeche = kSurface,
    this.kompakt = false,
  });

  @override
  State<LinienDiagramm> createState() => _LinienDiagrammState();
}

class _LinienDiagrammState extends State<LinienDiagramm> {
  int? _auswahl;

  static const _datumsBand = 20.0;

  @override
  void didUpdateWidget(covariant LinienDiagramm alt) {
    super.didUpdateWidget(alt);
    if (alt.punkte.length != widget.punkte.length) _auswahl = null;
  }

  @override
  Widget build(BuildContext context) {
    final punkte = widget.punkte;
    if (punkte.length < 2) {
      return SizedBox(
        height: widget.hoehe + _datumsBand,
        child: Center(
          child: Text(
            punkte.isEmpty ? 'Noch kein Verlauf vorhanden.' : 'Noch zu wenig Tage für einen Verlauf.',
            style: const TextStyle(color: kDim, fontSize: 12),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final breite = constraints.maxWidth;
      final geometrie = _Geometrie(punkte, breite, widget.hoehe, kompakt: widget.kompakt);

      void waehle(Offset o) {
        final i = geometrie.naechsterIndex(o.dx);
        if (i != _auswahl) setState(() => _auswahl = i);
      }

      final auswahl = _auswahl;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => waehle(d.localPosition),
        onHorizontalDragStart: (d) => waehle(d.localPosition),
        onHorizontalDragUpdate: (d) => waehle(d.localPosition),
        child: SizedBox(
          width: breite,
          height: widget.hoehe + _datumsBand,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(breite, widget.hoehe + _datumsBand),
                painter: _LinienMaler(
                  geometrie: geometrie,
                  auswahl: auswahl,
                  flaeche: widget.flaeche,
                  kompakt: widget.kompakt,
                ),
              ),
              if (auswahl != null) _tooltip(geometrie, auswahl, breite),
            ],
          ),
        ),
      );
    });
  }

  /// Wert zuerst und kraeftig, das Datum dahinter und leiser - wer tippt, kennt die
  /// Reihe und will die Zahl.
  Widget _tooltip(_Geometrie g, int i, double breite) {
    const tipBreite = 116.0;
    final x = g.x(i);
    final links = (x - tipBreite / 2).clamp(0.0, math.max(0.0, breite - tipBreite)).toDouble();
    return Positioned(
      left: links,
      top: 0,
      child: IgnorePointer(
        child: Container(
          width: tipBreite,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: kRow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kChip),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatEuro(g.punkte[i].wert),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(datumKurz(g.punkte[i].datum, mitJahr: true),
                  style: const TextStyle(fontSize: 10.5, color: kDim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "2026-11-13" -> "13.11." bzw. "13.11.2026"
String datumKurz(String iso, {bool mitJahr = false}) {
  final t = iso.split('-');
  if (t.length != 3) return iso;
  return mitJahr ? '${t[2]}.${t[1]}.${t[0]}' : '${t[2]}.${t[1]}.';
}

/// Rechnet Werte in Bildpunkte um - eine Stelle fuer Zeichnen und Antippen.
class _Geometrie {
  final List<PreisPunkt> punkte;
  final double breite;
  final double hoehe;
  final bool kompakt;

  late final List<double> _zeit;
  late final double unten, oben, schritt;
  late final double links;
  static const rechts = 8.0;
  static const obenRand = 6.0;

  _Geometrie(this.punkte, this.breite, this.hoehe, {required this.kompakt}) {
    final start = DateTime.parse(punkte.first.datum).millisecondsSinceEpoch.toDouble();
    _zeit = [for (final p in punkte) DateTime.parse(p.datum).millisecondsSinceEpoch - start];

    final werte = punkte.map((p) => p.wert);
    var lo = werte.reduce(math.min);
    var hi = werte.reduce(math.max);
    if ((hi - lo).abs() < 1e-9) {
      final rand = hi.abs() > 0 ? hi.abs() * 0.1 : 1.0;
      lo -= rand;
      hi += rand;
    }
    schritt = _schoenerSchritt((hi - lo) / 3);
    unten = math.max(0, (lo / schritt).floor() * schritt);
    oben = (hi / schritt).ceil() * schritt;

    // Platz fuer die breiteste Achsenbeschriftung
    final tp = TextPainter(
      text: TextSpan(text: achsenText(oben, schritt), style: TextStyle(fontSize: kompakt ? 9.5 : 10.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    links = tp.width + 8;
  }

  /// Runde Rasterschritte: 1, 2, 5, 10, 20, 50 ... (und 0,1 / 0,2 / 0,5 darunter).
  static double _schoenerSchritt(double roh) {
    if (roh <= 0) return 1;
    final zehner = math.pow(10, (math.log(roh) / math.ln10).floor()).toDouble();
    final n = roh / zehner;
    final f = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
    return f * zehner;
  }

  double x(int i) {
    final spanne = _zeit.last == 0 ? 1 : _zeit.last;
    return links + (breite - links - rechts) * (_zeit[i] / spanne);
  }

  double y(double wert) {
    final spanne = oben - unten == 0 ? 1 : oben - unten;
    return obenRand + (hoehe - obenRand) * (1 - (wert - unten) / spanne);
  }

  int naechsterIndex(double dx) {
    var beste = 0;
    var abstand = double.infinity;
    for (var i = 0; i < punkte.length; i++) {
      final d = (x(i) - dx).abs();
      if (d < abstand) {
        abstand = d;
        beste = i;
      }
    }
    return beste;
  }

  /// Achsenbeschriftung: ganze Euro ab einem Schritt von 1, darunter mit Cent.
  static String achsenText(double wert, double schritt) =>
      schritt >= 1 ? '${wert.round()} €' : '${wert.toStringAsFixed(2)} €';
}

class _LinienMaler extends CustomPainter {
  final _Geometrie geometrie;
  final int? auswahl;
  final Color flaeche;
  final bool kompakt;

  _LinienMaler({required this.geometrie, required this.auswahl, required this.flaeche, required this.kompakt});

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometrie;
    final textStil = TextStyle(color: kDim, fontSize: kompakt ? 9.5 : 10.5);

    // Hilfslinien und Achsenwerte
    final gitter = Paint()
      ..color = kGitter
      ..strokeWidth = 1;
    for (var w = g.unten; w <= g.oben + g.schritt * 0.001; w += g.schritt) {
      final y = g.y(w).roundToDouble() + 0.5;
      canvas.drawLine(Offset(g.links, y), Offset(size.width - _Geometrie.rechts, y), gitter);
      final tp = TextPainter(
        text: TextSpan(text: _Geometrie.achsenText(w, g.schritt), style: textStil),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(g.links - tp.width - 6, y - tp.height / 2));
    }

    // Flaeche und Linie
    final linie = Path();
    for (var i = 0; i < g.punkte.length; i++) {
      final p = Offset(g.x(i), g.y(g.punkte[i].wert));
      i == 0 ? linie.moveTo(p.dx, p.dy) : linie.lineTo(p.dx, p.dy);
    }
    final boden = g.y(g.unten);
    final flaechenPfad = Path.from(linie)
      ..lineTo(g.x(g.punkte.length - 1), boden)
      ..lineTo(g.x(0), boden)
      ..close();
    canvas.drawPath(flaechenPfad, Paint()..color = kChartLinie.withValues(alpha: 0.10));
    canvas.drawPath(
      linie,
      Paint()
        ..color = kChartLinie
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Datumsleiste: erster und letzter Tag
    final erster = TextPainter(
      text: TextSpan(text: datumKurz(g.punkte.first.datum), style: textStil),
      textDirection: TextDirection.ltr,
    )..layout();
    final letzter = TextPainter(
      text: TextSpan(text: datumKurz(g.punkte.last.datum), style: textStil),
      textDirection: TextDirection.ltr,
    )..layout();
    final yDatum = g.hoehe + 5;
    erster.paint(canvas, Offset(g.links, yDatum));
    letzter.paint(canvas, Offset(size.width - _Geometrie.rechts - letzter.width, yDatum));

    // Auswahl: senkrechte Haarlinie
    final a = auswahl;
    if (a != null) {
      final x = g.x(a).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(x, _Geometrie.obenRand),
        Offset(x, g.hoehe),
        Paint()
          ..color = kDim.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      _punkt(canvas, Offset(g.x(a), g.y(g.punkte[a].wert)));
    }

    // Endpunkt: der heutige Stand
    _punkt(canvas, Offset(g.x(g.punkte.length - 1), g.y(g.punkte.last.wert)));
  }

  /// Punkt mit 8 px Durchmesser und 2-px-Ring in der Flaechenfarbe - bleibt auch dort
  /// lesbar, wo er auf der Linie sitzt.
  void _punkt(Canvas canvas, Offset p) {
    canvas.drawCircle(p, 6, Paint()..color = flaeche);
    canvas.drawCircle(p, 4, Paint()..color = kChartLinie);
  }

  @override
  bool shouldRepaint(covariant _LinienMaler alt) =>
      alt.geometrie.punkte != geometrie.punkte ||
      alt.geometrie.breite != geometrie.breite ||
      alt.auswahl != auswahl;
}

/// Fortschrittsbalken eines Sets.
///
/// Die Fuellung traegt den Anteil, die Spur darunter ist eine schwache Stufe desselben
/// Farbtons. Komplett wird gruen - aber nie allein durch die Farbe: Der Aufrufer zeigt
/// dazu Haken und Wort.
class FortschrittsBalken extends StatelessWidget {
  final double anteil;
  final bool komplett;
  final double hoehe;

  const FortschrittsBalken({super.key, required this.anteil, this.komplett = false, this.hoehe = 6});

  @override
  Widget build(BuildContext context) {
    final farbe = komplett ? kChartGut : kChartLinie;
    return ClipRRect(
      borderRadius: BorderRadius.circular(hoehe / 2),
      child: SizedBox(
        height: hoehe,
        child: Stack(
          children: [
            Container(color: farbe.withValues(alpha: 0.18)),
            FractionallySizedBox(
              widthFactor: anteil.clamp(0.0, 1.0),
              child: Container(color: farbe),
            ),
          ],
        ),
      ),
    );
  }
}
