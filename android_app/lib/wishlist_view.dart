import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'card_model.dart';
import 'widgets.dart';
import 'wishlist.dart';

/// Stern zum Vormerken einer Karte. Hoert selbst auf die Wunschliste - ein gesetzter
/// Stern erscheint sofort ueberall.
class WunschStern extends StatelessWidget {
  final Wunschliste wunschliste;
  final OpCard card;

  /// Wie viele Exemplare beim Setzen eingetragen werden.
  final int anzahl;

  final double groesse;

  const WunschStern({super.key, required this.wunschliste, required this.card, this.anzahl = 1, this.groesse = 22});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wunschliste,
      builder: (context, _) {
        final drauf = wunschliste.enthaelt(card.id);
        return IconButton(
          tooltip: drauf ? 'Von der Wunschliste nehmen' : 'Auf die Wunschliste',
          visualDensity: VisualDensity.compact,
          onPressed: () => wunschliste.setzen(card.id, drauf ? 0 : anzahl),
          icon: Icon(drauf ? Icons.star : Icons.star_border, color: drauf ? kGold : kDim, size: groesse),
        );
      },
    );
  }
}

/// Zusammenfassung fuer die Uebersicht: wie viele Karten, was sie kosten.
class WunschlistenKarte extends StatelessWidget {
  final Wunschliste wunschliste;
  final OpCard? Function(String id) karteVon;
  final double Function(OpCard card) preisVon;

  const WunschlistenKarte({super.key, required this.wunschliste, required this.karteVon, required this.preisVon});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wunschliste,
      builder: (context, _) {
        final k = Wunschliste.kosten(wunschliste.eintraege, karteVon, preisVon);
        return Material(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WunschlisteSeite(wunschliste: wunschliste, karteVon: karteVon, preisVon: preisVon),
            )),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.star, color: kGold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Wunschliste', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          wunschliste.leer
                              ? 'Noch leer — Karten mit ☆ vormerken, etwa in den Set-Details.'
                              : '${wunschliste.exemplare} Karten · ${wunschliste.verschiedene} verschiedene',
                          style: const TextStyle(fontSize: 12, color: kDim),
                        ),
                      ],
                    ),
                  ),
                  if (!wunschliste.leer)
                    Text(
                      '${k.ohnePreis > 0 ? 'ab ' : ''}${formatEuro(k.summe)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: kDim),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Die ganze Wunschliste: Mengen aendern, entfernen, als Deckliste teilen.
class WunschlisteSeite extends StatelessWidget {
  final Wunschliste wunschliste;
  final OpCard? Function(String id) karteVon;
  final double Function(OpCard card) preisVon;

  const WunschlisteSeite({super.key, required this.wunschliste, required this.karteVon, required this.preisVon});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wunschliste,
      builder: (context, _) {
        final ids = wunschliste.eintraege.keys.toList()..sort();
        final k = Wunschliste.kosten(wunschliste.eintraege, karteVon, preisVon);
        return Scaffold(
          backgroundColor: kBg,
          appBar: AppBar(
            backgroundColor: kSurface,
            title: const Text('Wunschliste', style: TextStyle(fontSize: 17)),
            actions: [
              if (!wunschliste.leer)
                IconButton(
                  tooltip: 'Als Deckliste teilen',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => SharePlus.instance.share(ShareParams(
                    text: Wunschliste.alsDeckliste(wunschliste.eintraege),
                    subject: 'One Piece Wunschliste',
                  )),
                ),
              if (!wunschliste.leer)
                IconButton(
                  tooltip: 'Liste leeren',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => _leeren(context),
                ),
            ],
          ),
          body: wunschliste.leer
              ? const _LeererZustand()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  children: [
                    Row(
                      children: [
                        Text('${wunschliste.exemplare} Karten',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(' · ${wunschliste.verschiedene} verschiedene',
                            style: const TextStyle(fontSize: 13, color: kDim)),
                        const Spacer(),
                        Text(formatEuro(k.summe),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kGold)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      k.ohnePreis > 0
                          ? 'Zum heutigen Cardmarket-Trendpreis. ${k.ohnePreis} Karte(n) ohne Preis — die Summe ist eine Untergrenze.'
                          : 'Zum heutigen Cardmarket-Trendpreis.',
                      style: const TextStyle(fontSize: 11, color: kDim),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Scannst du eine gesuchte Karte, wird sie hier automatisch abgehakt.',
                      style: TextStyle(fontSize: 11, color: kDim),
                    ),
                    const SizedBox(height: 12),
                    for (final id in ids) _zeile(context, id),
                  ],
                ),
        );
      },
    );
  }

  Widget _zeile(BuildContext context, String id) {
    final karte = karteVon(id);
    final anzahl = wunschliste.anzahl(id);
    final preis = karte == null ? 0.0 : preisVon(karte);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (karte != null)
            GestureDetector(
              onTap: () => FullScreenCard.show(context, karte),
              child: CardImage(card: karte, width: 38, radius: BorderRadius.circular(4)),
            )
          else
            Container(width: 38, height: 53, decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(karte?.name ?? id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                Text(
                  '$id${karte?.alt == true ? ' · Alt-Art' : ''} · ${preis > 0 ? formatEuro(preis) : 'kein Preis'}',
                  style: const TextStyle(fontSize: 11, color: kDim),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: anzahl == 1 ? 'Entfernen' : 'Eins weniger',
            onPressed: () => wunschliste.setzen(id, anzahl - 1),
            icon: Icon(anzahl == 1 ? Icons.delete_outline : Icons.remove, size: 19, color: kDim),
          ),
          SizedBox(
            width: 22,
            child: Text('$anzahl', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Eins mehr',
            onPressed: () => wunschliste.setzen(id, anzahl + 1),
            icon: const Icon(Icons.add, size: 19, color: kDim),
          ),
        ],
      ),
    );
  }

  Future<void> _leeren(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Wunschliste leeren?'),
        content: Text('${wunschliste.verschiedene} Karten werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leeren')),
        ],
      ),
    );
    if (ok == true) wunschliste.leeren();
  }
}

class _LeererZustand extends StatelessWidget {
  const _LeererZustand();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Noch keine Karten vorgemerkt.\n\n'
          'So kommen Karten auf die Liste:\n'
          '☆ in den Set-Details (Übersicht → ein Set antippen)\n'
          '„Fehlende auf die Wunschliste" bei einem Set oder Turnierdeck\n'
          '☆ in den Kartendetails deiner Sammlung',
          textAlign: TextAlign.center,
          style: TextStyle(color: kDim, height: 1.6, fontSize: 13),
        ),
      ),
    );
  }
}
