import 'package:flutter/material.dart';

import 'card_model.dart';
import 'collection_view.dart';
import 'line_chart.dart';
import 'price_history.dart';
import 'set_progress.dart';
import 'widgets.dart';

/// Vierter Reiter: Wert der Sammlung ueber die Zeit und Fortschritt je Set.
///
/// Laedt den Verlauf erst, wenn der Reiter zum ersten Mal sichtbar wird - nie beim
/// App-Start. Ohne Netz bleibt der zuletzt geladene Stand stehen.
class OverviewView extends StatefulWidget {
  final List<CollectionEntry> entries;
  final List<OpCard> katalog;
  final double Function(OpCard card) priceOf;
  final Map<String, SetInfo> setInfos;
  final HistoryStore historyStore;

  /// true, solange der Reiter sichtbar ist.
  final bool aktiv;

  const OverviewView({
    super.key,
    required this.entries,
    required this.katalog,
    required this.priceOf,
    required this.setInfos,
    required this.historyStore,
    required this.aktiv,
  });

  @override
  State<OverviewView> createState() => _OverviewViewState();
}

class _OverviewViewState extends State<OverviewView> {
  List<PreisPunkt>? _verlauf;
  bool _laedt = false;
  bool _ohneNetz = false;
  bool _listeOffen = false;

  /// Fuer welchen Sammlungsstand der Verlauf berechnet wurde.
  int? _berechnetFuer;

  List<SetFortschritt>? _sets;
  int? _setsFuer;

  @override
  void initState() {
    super.initState();
    if (widget.aktiv) _verlaufLaden();
  }

  @override
  void didUpdateWidget(covariant OverviewView alt) {
    super.didUpdateWidget(alt);
    if (widget.aktiv && _berechnetFuer != _signatur) _verlaufLaden();
  }

  /// Aendert sich, sobald Karten dazukommen, wegfallen oder getauscht werden.
  int get _signatur => Object.hash(widget.entries.length, Object.hashAllUnordered(widget.entries.map((e) => e.card.id)));

  Future<void> _verlaufLaden({bool neu = false}) async {
    if (_laedt) return;
    final signatur = _signatur;
    setState(() {
      _laedt = true;
      _berechnetFuer = signatur;
    });

    if (neu) widget.historyStore.speicherLeeren();
    final ids = widget.entries.map((e) => e.card.id).toList();
    final codes = ids.map((id) => id.split('-').first).toSet();
    final historien = await widget.historyStore.ladenMehrere(codes);
    final verlauf = WertVerlauf.berechnen(kartenIds: ids, historien: historien);

    if (!mounted) return;
    setState(() {
      _laedt = false;
      _ohneNetz = codes.isNotEmpty && historien.isEmpty;
      _verlauf = verlauf;
    });
  }

  List<SetFortschritt> get _fortschritt {
    final signatur = Object.hash(_signatur, widget.katalog.length);
    if (_sets == null || _setsFuer != signatur) {
      _sets = SetProgress.berechnen(
        katalog: widget.katalog,
        besessen: widget.entries.map((e) => e.card.id).toSet(),
        preisVon: widget.priceOf,
        infos: widget.setInfos,
      );
      _setsFuer = signatur;
    }
    return _sets!;
  }

  @override
  Widget build(BuildContext context) {
    final sets = _fortschritt;
    final angefangen = sets.where((s) => s.angefangen).toList();
    final komplett = sets.where((s) => s.komplett).length;

    return RefreshIndicator(
      onRefresh: () => _verlaufLaden(neu: true),
      color: kGold,
      child: ListView(
        padding: EdgeInsets.fromLTRB(14, MediaQuery.of(context).padding.top + 12, 14, 24),
        children: [
          const Text('Übersicht', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _wertKarte(),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Sets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${angefangen.length} angefangen · $komplett komplett',
                  style: const TextStyle(fontSize: 12, color: kDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Gezählt werden Grundkarten; Alt-Arts stehen jeweils daneben.',
            style: TextStyle(fontSize: 11, color: kDim),
          ),
          const SizedBox(height: 10),
          for (final s in angefangen) _setZeile(s),
          if (angefangen.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Noch keine Karten gescannt.', style: TextStyle(color: kDim)),
            ),
          if (sets.length > angefangen.length)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Weitere Sets (${sets.length - angefangen.length})',
                    style: const TextStyle(fontSize: 13, color: kDim)),
                children: [for (final s in sets.where((s) => !s.angefangen)) _setZeile(s)],
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Wert

  Widget _wertKarte() {
    final heute = widget.entries.fold<double>(0, (s, e) => s + widget.priceOf(e.card));
    final verlauf = _verlauf;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wert deiner Sammlung', style: TextStyle(fontSize: 13, color: kDim)),
          const SizedBox(height: 2),
          // Die eine Hauptzahl dieser Ansicht
          Text(formatEuro(heute), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w600, height: 1.1)),
          const SizedBox(height: 6),
          if (verlauf != null && verlauf.length >= 2)
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _veraenderung(verlauf, 7, 'seit 7 Tagen'),
                _veraenderung(verlauf, 30, 'seit 30 Tagen'),
              ],
            ),
          const SizedBox(height: 14),
          if (verlauf == null)
            SizedBox(
              height: 180,
              child: Center(
                child: _laedt
                    ? const CircularProgressIndicator()
                    : const Text('Verlauf wird beim Öffnen geladen.', style: TextStyle(color: kDim)),
              ),
            )
          else
            // Beim Nachladen bleibt das alte Bild stehen, nur blasser - kein Springen
            AnimatedOpacity(
              opacity: _laedt ? 0.45 : 1,
              duration: const Duration(milliseconds: 200),
              child: LinienDiagramm(punkte: verlauf, hoehe: 160),
            ),
          const SizedBox(height: 8),
          Text(
            _ohneNetz
                ? 'Ohne Internet — der Verlauf erscheint, sobald eine Verbindung besteht.'
                : 'Was deine heutigen Karten an jedem Tag wert waren. Gerechnet mit der '
                    'automatisch zugeordneten Druckvariante.',
            style: const TextStyle(fontSize: 10.5, color: kDim, height: 1.35),
          ),
          if (verlauf != null && verlauf.length >= 2) _werteListe(verlauf),
        ],
      ),
    );
  }

  /// Vorzeichen und Pfeil tragen die Richtung - die Farbe ist nur Zugabe.
  Widget _veraenderung(List<PreisPunkt> verlauf, int tage, String zeitraum) {
    final v = WertVerlauf.veraenderung(verlauf, tage);
    if (v == null) return const SizedBox.shrink();
    final hoch = v.absolut >= 0;
    final farbe = v.absolut.abs() < 0.005 ? kDim : (hoch ? kOk : kAccent);
    final vorzeichen = hoch ? '+' : '−';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(hoch ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: farbe, size: 20),
        Text(
          '$vorzeichen${formatEuro(v.absolut.abs())} ($vorzeichen${v.prozent.abs().toStringAsFixed(1)} %)',
          style: TextStyle(color: farbe, fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        const SizedBox(width: 5),
        Text(zeitraum, style: const TextStyle(color: kDim, fontSize: 12)),
      ],
    );
  }

  /// Dieselben Werte als Liste - das Diagramm darf nie der einzige Weg zu einer Zahl sein.
  Widget _werteListe(List<PreisPunkt> verlauf) {
    final neueste = verlauf.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          onPressed: () => setState(() => _listeOffen = !_listeOffen),
          icon: Icon(_listeOffen ? Icons.expand_less : Icons.expand_more, size: 18, color: kDim),
          label: Text(_listeOffen ? 'Liste ausblenden' : 'Werte als Liste',
              style: const TextStyle(fontSize: 12, color: kDim)),
        ),
        if (_listeOffen)
          for (final p in neueste)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text(datumKurz(p.datum, mitJahr: true),
                      style: const TextStyle(fontSize: 12, color: kDim, fontFeatures: [FontFeature.tabularFigures()])),
                  const Spacer(),
                  Text(formatEuro(p.wert),
                      style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
      ],
    );
  }

  // ------------------------------------------------------------------ Sets

  Widget _setZeile(SetFortschritt s) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SetDetailView(fortschritt: s, priceOf: widget.priceOf),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(s.code, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.anzeigename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: kDim)),
                ),
                if (s.komplett) ...[
                  const Icon(Icons.check_circle, size: 16, color: kChartGut),
                  const SizedBox(width: 4),
                  const Text('komplett', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ] else
                  Text('${s.grundBesessen} von ${s.grundGesamt}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            FortschrittsBalken(anteil: s.anteil, komplett: s.komplett),
            const SizedBox(height: 5),
            Row(
              children: [
                Text(
                  s.altGesamt > 0 ? 'Alt-Arts ${s.altBesessen} von ${s.altGesamt}' : '',
                  style: const TextStyle(fontSize: 11, color: kDim),
                ),
                const Spacer(),
                if (!s.komplett)
                  Text(
                    'fehlen: ${s.ohnePreis > 0 ? 'ab ' : ''}${formatEuro(s.kostenKomplett)}',
                    style: const TextStyle(fontSize: 11, color: kDim),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Set im Detail: was fehlt, und was es kostet.
class SetDetailView extends StatelessWidget {
  final SetFortschritt fortschritt;
  final double Function(OpCard card) priceOf;

  const SetDetailView({super.key, required this.fortschritt, required this.priceOf});

  @override
  Widget build(BuildContext context) {
    final s = fortschritt;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text('${s.code} · ${s.anzeigename}', style: const TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Row(
            children: [
              Text('${s.grundBesessen} von ${s.grundGesamt} Grundkarten',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${(s.anteil * 100).round()} %', style: const TextStyle(color: kDim)),
            ],
          ),
          const SizedBox(height: 8),
          FortschrittsBalken(anteil: s.anteil, komplett: s.komplett, hoehe: 8),
          const SizedBox(height: 8),
          if (s.altGesamt > 0)
            Text('Alt-Arts: ${s.altBesessen} von ${s.altGesamt}', style: const TextStyle(color: kDim, fontSize: 12.5)),
          const SizedBox(height: 18),
          if (s.komplett)
            const Row(
              children: [
                Icon(Icons.check_circle, color: kChartGut),
                SizedBox(width: 8),
                Text('Alle Grundkarten dieses Sets sind in deiner Sammlung.'),
              ],
            )
          else ...[
            Row(
              children: [
                Text('Es fehlen ${s.fehlend.length} Karten',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(formatEuro(s.kostenKomplett),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kGold)),
              ],
            ),
            if (s.ohnePreis > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${s.ohnePreis} davon ohne Cardmarket-Preis — die Summe ist eine Untergrenze.',
                  style: const TextStyle(fontSize: 11, color: kDim),
                ),
              ),
            const SizedBox(height: 4),
            const Text('Günstigste zuerst, zum heutigen Cardmarket-Trendpreis.',
                style: TextStyle(fontSize: 11, color: kDim)),
            const SizedBox(height: 10),
            for (final karte in s.fehlend) _karteZeile(context, karte),
          ],
        ],
      ),
    );
  }

  Widget _karteZeile(BuildContext context, OpCard karte) {
    final preis = priceOf(karte);
    return InkWell(
      onTap: () => FullScreenCard.show(context, karte),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            CardImage(card: karte, width: 38, radius: BorderRadius.circular(4)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(karte.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  Text('${karte.id} · ${karte.rarity}', style: const TextStyle(fontSize: 11, color: kDim)),
                ],
              ),
            ),
            Text(preis > 0 ? formatEuro(preis) : 'kein Preis',
                style: TextStyle(fontSize: 12.5, color: preis > 0 ? Colors.white : kDim)),
          ],
        ),
      ),
    );
  }
}
