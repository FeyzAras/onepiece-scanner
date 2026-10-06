import 'package:flutter/material.dart';

import 'card_model.dart';
import 'deck_model.dart';
import 'widgets.dart';

/// Wie gut ein Deck mit der eigenen Sammlung abgedeckt ist.
class DeckCoverage {
  final int owned;
  final int needed;
  const DeckCoverage(this.owned, this.needed);

  double get ratio => needed == 0 ? 0 : owned / needed;
  int get missing => needed - owned;
}

class DecksView extends StatefulWidget {
  final DeckData? data;
  final bool loading;

  /// Wie oft die Karte mit dieser Nummer in der Sammlung liegt (Artwork egal).
  final int Function(String baseId) ownedCount;
  final OpCard? Function(String baseId) cardOf;
  final VoidCallback onRefresh;

  const DecksView({
    super.key,
    required this.data,
    required this.loading,
    required this.ownedCount,
    required this.cardOf,
    required this.onRefresh,
  });

  @override
  State<DecksView> createState() => _DecksViewState();
}

class _DecksViewState extends State<DecksView> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _onlyBuildable = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DeckCoverage _coverage(Deck deck) {
    var owned = 0;
    var needed = 0;
    for (final c in deck.cards) {
      needed += c.qty;
      owned += widget.ownedCount(c.id).clamp(0, c.qty);
    }
    return DeckCoverage(owned, needed);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data == null) {
      return Center(
        child: widget.loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Keine Decklisten geladen.',
                        style: TextStyle(color: kDim), textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: widget.onRefresh, child: const Text('Erneut versuchen')),
                  ],
                ),
              ),
      );
    }

    var decks = data.decks;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      decks = decks
          .where((d) =>
              d.name.toLowerCase().contains(q) ||
              (d.player ?? '').toLowerCase().contains(q) ||
              (d.tournament ?? '').toLowerCase().contains(q) ||
              (d.leaderId ?? '').toLowerCase().contains(q))
          .toList();
    }
    final withCoverage = decks.map((d) => (deck: d, cov: _coverage(d))).toList()
      ..sort((a, b) => b.cov.ratio.compareTo(a.cov.ratio));
    final shown = _onlyBuildable ? withCoverage.where((x) => x.cov.ratio >= 0.5).toList() : withCoverage;

    return Column(
      children: [
        _header(data, shown.length),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Keine Decks gefunden.', style: TextStyle(color: kDim))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _deckTile(shown[i].deck, shown[i].cov),
                ),
        ),
      ],
    );
  }

  Widget _header(DeckData data, int count) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 14, right: 14, bottom: 8),
      color: kSurface,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$count', style: const TextStyle(color: kGold, fontWeight: FontWeight.bold, fontSize: 18)),
                  const TextSpan(text: ' Turnierdecks', style: TextStyle(fontSize: 13, color: kDim)),
                ])),
              ),
              IconButton(
                onPressed: widget.onRefresh,
                icon: widget.loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 20, color: kDim),
                tooltip: 'Decklisten aktualisieren',
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Quelle: ${data.sourceName} · Stand ${data.updatedAt}',
                style: const TextStyle(fontSize: 11, color: kDim)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v.trim()),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Deck, Spieler oder Turnier suchen …',
              hintStyle: const TextStyle(color: kDim, fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 19, color: kDim),
              filled: true,
              fillColor: kRow,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Nur Decks, die ich halb besitze', style: TextStyle(fontSize: 12)),
              selected: _onlyBuildable,
              showCheckmark: false,
              selectedColor: kGold,
              backgroundColor: kRow,
              side: BorderSide.none,
              labelStyle: TextStyle(color: _onlyBuildable ? const Color(0xFF241A00) : kDim),
              onSelected: (v) => setState(() => _onlyBuildable = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deckTile(Deck deck, DeckCoverage cov) {
    final leader = deck.leaderId == null ? null : widget.cardOf(deck.leaderId!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showDeck(deck, cov),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kRow, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              if (leader != null)
                CardImage(card: leader, width: 46)
              else
                Container(width: 46, height: 64, decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(7))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(
                      [deck.placement, deck.tournament, deck.region].where((x) => x != null && x.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kDim, fontSize: 11.5),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: cov.ratio,
                        minHeight: 5,
                        backgroundColor: kChip,
                        valueColor: AlwaysStoppedAnimation(cov.ratio >= 0.999 ? kOk : kGold),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('${cov.owned} von ${cov.needed} Karten in deiner Sammlung',
                        style: const TextStyle(color: kDim, fontSize: 10.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kDim, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeck(Deck deck, DeckCoverage cov) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx2, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Center(
              child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFF3A3F47), borderRadius: BorderRadius.circular(3))),
            ),
            const SizedBox(height: 14),
            Text(deck.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
            const SizedBox(height: 4),
            Text(
              [deck.player, deck.placement, deck.tournament, deck.host, deck.date]
                  .where((x) => x != null && x.isNotEmpty)
                  .join(' · '),
              style: const TextStyle(color: kDim, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kRow, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${cov.owned} von ${cov.needed} Karten',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(cov.missing == 0 ? 'Du hast alles!' : 'Es fehlen ${cov.missing} Karten',
                            style: TextStyle(color: cov.missing == 0 ? kOk : kDim, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('${(cov.ratio * 100).round()} %',
                      style: TextStyle(color: cov.ratio >= 0.999 ? kOk : kGold, fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Decklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            for (final entry in deck.cards) _deckCardRow(entry),
          ],
        ),
      ),
    );
  }

  Widget _deckCardRow(DeckCard entry) {
    final card = widget.cardOf(entry.id);
    final owned = widget.ownedCount(entry.id);
    final enough = owned >= entry.qty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          if (card != null)
            GestureDetector(
              onTap: () => FullScreenCard.show(context, card),
              child: CardImage(card: card, width: 34),
            )
          else
            Container(width: 34, height: 47, decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(5))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card?.name ?? entry.id,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(entry.id, style: const TextStyle(fontSize: 10.5, color: kDim)),
              ],
            ),
          ),
          Text('$owned/${entry.qty}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: enough ? kOk : (owned > 0 ? kGold : kDim),
              )),
          const SizedBox(width: 8),
          Icon(enough ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 17, color: enough ? kOk : kChip),
        ],
      ),
    );
  }
}
