import 'package:flutter/material.dart';

import 'card_model.dart';
import 'collection_store.dart';
import 'widgets.dart';

/// Ein Eintrag der Sammlung: eine Karte, wie oft sie gescannt wurde und in welchem Ordner.
class CollectionEntry {
  final OpCard card;
  final String folderId;
  final String how;
  final DateTime at;

  CollectionEntry({required this.card, required this.folderId, required this.how, required this.at});

  StoredScan toStored() => StoredScan(cardId: card.id, folderId: folderId, how: how, at: at);
}

/// Zusammengefasste Karte: gleiche Karte mehrfach gescannt -> eine Zeile mit Anzahl.
class StackedCard {
  final OpCard card;
  final List<CollectionEntry> entries;

  /// Tatsaechlich geltender Einzelpreis - entweder der automatisch zugeordnete
  /// oder der vom Nutzer gewaehlte.
  final double unitPrice;

  StackedCard(this.card, this.entries, this.unitPrice);

  int get count => entries.length;
  double get totalValue => unitPrice * count;
  String get how => entries.first.how;
}

enum SortMode { neueste, name, set, preis }

extension SortModeLabel on SortMode {
  String get label => switch (this) {
        SortMode.neueste => 'Zuletzt gescannt',
        SortMode.name => 'Name',
        SortMode.set => 'Set',
        SortMode.preis => 'Preis',
      };
}

class CollectionView extends StatefulWidget {
  final List<CollectionEntry> entries;
  final List<ScanFolder> folders;
  final void Function(OpCard card, String folderId) onRemoveOne;
  final void Function(CollectionEntry entry, OpCard replacement) onSwitchArtwork;
  final List<OpCard> Function(OpCard card) variantsOf;
  final VoidCallback onManageFolders;

  /// Geltender Einzelpreis einer Karte (automatisch zugeordnet oder vom Nutzer gewaehlt).
  final double Function(OpCard card) priceOf;

  /// Setzt einen abweichenden Preis, oder loescht die Auswahl bei null.
  final void Function(OpCard card, double? amount) onChoosePrice;

  const CollectionView({
    super.key,
    required this.entries,
    required this.folders,
    required this.onRemoveOne,
    required this.onSwitchArtwork,
    required this.variantsOf,
    required this.onManageFolders,
    required this.priceOf,
    required this.onChoosePrice,
  });

  @override
  State<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<CollectionView> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  SortMode _sort = SortMode.neueste;
  String? _folderFilter; // null = alle Ordner

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<StackedCard> get _stacked {
    final filtered = widget.entries.where((e) {
      if (_folderFilter != null && e.folderId != _folderFilter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.card.name.toLowerCase().contains(q) ||
          e.card.id.toLowerCase().contains(q) ||
          e.card.setCode.toLowerCase().contains(q) ||
          e.card.cardType.toLowerCase().contains(q);
    });

    final byCard = <String, List<CollectionEntry>>{};
    for (final e in filtered) {
      byCard.putIfAbsent(e.card.id, () => []).add(e);
    }
    final stacks = byCard.values
        .map((list) => StackedCard(list.first.card, list, widget.priceOf(list.first.card)))
        .toList();

    switch (_sort) {
      case SortMode.neueste:
        stacks.sort((a, b) => b.entries
            .map((e) => e.at)
            .reduce((x, y) => x.isAfter(y) ? x : y)
            .compareTo(a.entries.map((e) => e.at).reduce((x, y) => x.isAfter(y) ? x : y)));
        break;
      case SortMode.name:
        stacks.sort((a, b) => a.card.name.toLowerCase().compareTo(b.card.name.toLowerCase()));
        break;
      case SortMode.set:
        stacks.sort((a, b) {
          final bySet = a.card.setCode.compareTo(b.card.setCode);
          return bySet != 0 ? bySet : a.card.baseId.compareTo(b.card.baseId);
        });
        break;
      case SortMode.preis:
        stacks.sort((a, b) => b.unitPrice.compareTo(a.unitPrice));
        break;
    }
    return stacks;
  }

  @override
  Widget build(BuildContext context) {
    final stacks = _stacked;
    final totalCards = stacks.fold<int>(0, (s, x) => s + x.count);
    final totalValue = stacks.fold<double>(0, (s, x) => s + x.totalValue);

    return Column(
      children: [
        _header(totalCards, totalValue, stacks.length),
        Expanded(
          child: stacks.isEmpty
              ? _emptyState()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.56,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: stacks.length,
                  itemBuilder: (context, i) => _cardTile(stacks[i]),
                ),
        ),
      ],
    );
  }

  Widget _header(int totalCards, double totalValue, int distinct) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 14, right: 14, bottom: 8),
      color: kSurface,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$totalCards', style: const TextStyle(color: kGold, fontWeight: FontWeight.bold, fontSize: 18)),
                  TextSpan(text: ' Karten · $distinct verschiedene', style: const TextStyle(fontSize: 13, color: kDim)),
                ])),
              ),
              Text(formatEuro(totalValue),
                  style: const TextStyle(color: kGold, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v.trim()),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Suchen: Name, Nummer, Set …',
              hintStyle: const TextStyle(color: kDim, fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 19, color: kDim),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18, color: kDim),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: kRow,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _folderChip(null, 'Alle Ordner'),
                for (final f in widget.folders) _folderChip(f.id, f.name),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.create_new_folder_outlined, size: 15, color: kDim),
                    label: const Text('Ordner', style: TextStyle(fontSize: 12)),
                    backgroundColor: kRow,
                    side: BorderSide.none,
                    onPressed: widget.onManageFolders,
                  ),
                ),
                const SizedBox(width: 10),
                for (final mode in SortMode.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(mode.label, style: const TextStyle(fontSize: 12)),
                      selected: _sort == mode,
                      showCheckmark: false,
                      avatar: _sort == mode ? const Icon(Icons.sort, size: 14, color: Color(0xFF241A00)) : null,
                      selectedColor: kGold,
                      backgroundColor: kRow,
                      side: BorderSide.none,
                      labelStyle: TextStyle(color: _sort == mode ? const Color(0xFF241A00) : kDim),
                      onSelected: (_) => setState(() => _sort = mode),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderChip(String? id, String name) {
    final selected = _folderFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(name, style: const TextStyle(fontSize: 12)),
        selected: selected,
        showCheckmark: false,
        selectedColor: kAccent,
        backgroundColor: kRow,
        side: BorderSide.none,
        labelStyle: TextStyle(color: selected ? Colors.white : kDim),
        onSelected: (_) => setState(() => _folderFilter = id),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _query.isNotEmpty
                ? 'Nichts gefunden für „$_query".'
                : 'Noch keine Karten in diesem Ordner.\nWechsle zum Scannen-Tab und halte eine Karte vor die Kamera.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kDim, fontSize: 13.5, height: 1.5),
          ),
        ),
      );

  Widget _cardTile(StackedCard stack) {
    return GestureDetector(
      onTap: () => _showDetails(stack),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) => CardImage(card: stack.card, width: c.maxWidth, radius: BorderRadius.circular(9)),
                  ),
                ),
                if (stack.count > 1)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: kAccent,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                      ),
                      child: Text('×${stack.count}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(stack.card.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          Text(stack.card.id, style: const TextStyle(fontSize: 10, color: kDim)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                stack.card.price == null ? '–' : formatEuro(stack.totalValue),
                style: const TextStyle(fontSize: 11, color: kGold, fontWeight: FontWeight.bold),
              ),
              // Hinweiszeichen, wenn die Zuordnung zur Druckvariante unsicher ist
              if (stack.card.price?.confidence == PriceConfidence.unsicher)
                const Padding(
                  padding: EdgeInsets.only(left: 3),
                  child: Icon(Icons.help_outline, size: 11, color: kDim),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Erklaert, worauf sich der Preis bezieht, zeigt die Spanne aller Cardmarket-Versionen
  /// dieser Kartennummer und laesst eine andere waehlen.
  ///
  /// Hintergrund: Cardmarket fuehrt pro Nummer mehrere Druckvarianten - bei OP01-001 acht,
  /// von 1,87 EUR bis 610 EUR. Die automatische Zuordnung kann danebenliegen, deshalb
  /// bleibt die Entscheidung einsehbar und korrigierbar.
  Widget _priceSection(BuildContext ctx, StackedCard stack) {
    final card = stack.card;
    final price = card.price!;
    final options = card.priceOptions;
    final chosenByUser = (stack.unitPrice - price.amount).abs() > 0.004;

    final confidenceColor = switch (price.confidence) {
      PriceConfidence.eindeutig => kOk,
      PriceConfidence.paar => kGold,
      PriceConfidence.unsicher => const Color(0xFFFF8A8A),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kRow, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  price.confidence == PriceConfidence.eindeutig ? Icons.verified_outlined : Icons.help_outline,
                  size: 15,
                  color: confidenceColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    chosenByUser ? 'von dir ausgewählt' : price.confidence.label,
                    style: TextStyle(fontSize: 12, color: chosenByUser ? kOk : confidenceColor),
                  ),
                ),
                if (chosenByUser)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onChoosePrice(card, null);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('zurücksetzen', style: TextStyle(fontSize: 11.5, color: kDim)),
                  ),
              ],
            ),
            if (options.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                'Cardmarket führt ${options.length} Versionen dieser Nummer: '
                '${formatEuro(options.first)} – ${formatEuro(options.last)}',
                style: const TextStyle(fontSize: 11.5, color: kDim, height: 1.4),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final option in options)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onChoosePrice(card, option);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: (stack.unitPrice - option).abs() < 0.004 ? kGold : kChip,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          formatEuro(option),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: (stack.unitPrice - option).abs() < 0.004
                                ? const Color(0xFF241A00)
                                : kDim,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Stimmt der Wert nicht, tippe die passende Version an – die Auswahl bleibt gespeichert.',
                style: TextStyle(fontSize: 10.5, color: kDim, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetails(StackedCard stack) {
    final card = stack.card;
    final price = card.price;
    final variants = widget.variantsOf(card).where((v) => v.id != card.id).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => FullScreenCard.show(ctx, card),
                    child: Stack(
                      children: [
                        CardImage(card: card, width: 120, radius: BorderRadius.circular(10)),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.zoom_in, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(card.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        const SizedBox(height: 4),
                        Text('${card.id} · ${card.rarity} · ${card.cardType}',
                            style: const TextStyle(color: kDim, fontSize: 12.5)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Chip2('×${stack.count} in der Sammlung',
                                background: kAccent, foreground: Colors.white, fontSize: 11),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(price == null ? 'kein Preis hinterlegt' : formatEuro(stack.unitPrice),
                            style: const TextStyle(color: kGold, fontWeight: FontWeight.bold, fontSize: 20)),
                        if (price != null)
                          Text('Cardmarket ${price.basisLabel} · Stand ${price.asOf}',
                              style: const TextStyle(color: kDim, fontSize: 11)),
                        if (stack.count > 1 && price != null)
                          Text('zusammen ${formatEuro(stack.totalValue)}',
                              style: const TextStyle(color: kDim, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
              if (price != null) _priceSection(ctx, stack),
              if (card.effect.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(card.effect, style: const TextStyle(color: Color(0xFFD7DBE0), fontSize: 12, height: 1.45)),
              ],
              if (variants.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Anderes Artwork mit derselben Nummer',
                    style: TextStyle(fontSize: 12, color: kDim, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final v in variants)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onSwitchArtwork(stack.entries.first, v);
                          },
                          child: Column(
                            children: [
                              CardImage(card: v, width: 58),
                              const SizedBox(height: 4),
                              const Text('wechseln', style: TextStyle(fontSize: 10, color: kGold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onRemoveOne(card, stack.entries.first.folderId);
                      },
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF8A8A),
                        backgroundColor: kChip,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      label: Text(stack.count > 1 ? 'Eine entfernen' : 'Entfernen'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => FullScreenCard.show(ctx, card),
                      icon: const Icon(Icons.zoom_in, size: 18),
                      style: TextButton.styleFrom(
                        foregroundColor: kDim,
                        backgroundColor: kChip,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      label: const Text('Vergrößern'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
