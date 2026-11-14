import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'card_matcher.dart';
import 'card_model.dart';
import 'line_chart.dart';
import 'my_decks.dart';
import 'widgets.dart';

/// Was die Deck-Ansichten von aussen brauchen - an einer Stelle gebuendelt.
class DeckUmgebung {
  final MeineDecks decks;
  final CardMatcher? matcher;
  final int Function(String baseId) besitzZurNummer;
  final void Function(Map<String, int> karten) aufWunschliste;

  const DeckUmgebung({
    required this.decks,
    required this.matcher,
    required this.besitzZurNummer,
    required this.aufWunschliste,
  });

  OpCard? karte(String id) => matcher?.byId(id);
  List<OpCard> get katalog => matcher?.cards ?? const [];
}

/// Liste der eigenen Decks mit "Neues Deck" und "Deckliste einfuegen".
class MeineDeckListe extends StatelessWidget {
  final DeckUmgebung umgebung;

  const MeineDeckListe({super.key, required this.umgebung});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: umgebung.decks,
      builder: (context, _) {
        final decks = umgebung.decks.decks;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _neuesDeck(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Neues Deck'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _einfuegen(context),
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Liste einfügen'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (decks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                child: Text(
                  'Noch keine eigenen Decks.\n\n'
                  '„Neues Deck" beginnt mit der Wahl eines Leaders. „Liste einfügen" übernimmt '
                  'eine Deckliste aus der Zwischenablage (1xOP01-001 …).\n\n'
                  'Oder als Vorlage: Turnierdecks → ein Deck antippen → „Als eigenes Deck übernehmen".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kDim, height: 1.5, fontSize: 13),
                ),
              ),
            for (final d in decks) _kachel(context, d),
          ],
        );
      },
    );
  }

  Widget _kachel(BuildContext context, MeinDeck d) {
    final leader = d.leaderId == null ? null : umgebung.karte(d.leaderId!);
    final p = DeckRegeln.pruefen(d, umgebung.karte);
    final a = DeckAbdeckung.berechnen(d, umgebung.karte, umgebung.besitzZurNummer);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => DeckEditorSeite.oeffnen(context, umgebung, d.id),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kRow, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              if (leader != null)
                CardImage(card: leader, width: 46)
              else
                Container(
                    width: 46,
                    height: 64,
                    decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(7)),
                    child: const Icon(Icons.person_outline, color: kDim)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(p.gueltig ? Icons.check_circle : Icons.info_outline,
                            size: 14, color: p.gueltig ? kChartGut : kGold),
                        const SizedBox(width: 4),
                        Text(
                          p.gueltig
                              ? (p.vorbehalt ? 'spielbereit, mit Vorbehalt' : 'spielbereit')
                              : '${d.anzahl}/50 · ${p.meldungen.length} Hinweis(e)',
                          style: const TextStyle(fontSize: 11.5, color: kDim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FortschrittsBalken(
                      anteil: a.benoetigt == 0 ? 0 : a.vorhanden / a.benoetigt,
                      komplett: a.benoetigt > 0 && a.vorhanden >= a.benoetigt,
                      hoehe: 5,
                    ),
                    const SizedBox(height: 3),
                    Text('${a.vorhanden} von ${a.benoetigt} Karten in deiner Sammlung',
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

  Future<void> _neuesDeck(BuildContext context) async {
    final leader = await LeaderWahlSeite.waehlen(context, umgebung);
    if (leader == null || !context.mounted) return;
    final id = umgebung.decks.anlegen(name: '${leader.name}-Deck', leaderId: leader.id);
    DeckEditorSeite.oeffnen(context, umgebung, id);
  }

  Future<void> _einfuegen(BuildContext context) async {
    final matcher = umgebung.matcher;
    if (matcher == null) return;
    final text = await _textDialog(context);
    if (text == null || text.trim().isEmpty || !context.mounted) return;

    final r = DeckText.ausText(text, matcher);
    if (r.karten.isEmpty && r.leaderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('In dem Text steht keine erkennbare Kartennummer.')),
      );
      return;
    }
    final leader = r.leaderId == null ? null : umgebung.karte(r.leaderId!);
    final id = umgebung.decks.anlegen(
      name: leader != null ? '${leader.name}-Deck' : 'Eingefügtes Deck',
      leaderId: r.leaderId,
      karten: r.karten,
    );
    if (r.nichtErkannt.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${r.nichtErkannt.length} Zeile(n) nicht erkannt: ${r.nichtErkannt.take(3).join(', ')}'),
        duration: const Duration(seconds: 6),
      ));
    }
    DeckEditorSeite.oeffnen(context, umgebung, id);
  }

  static Future<String?> _textDialog(BuildContext context) {
    final feld = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Deckliste einfügen'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: feld,
                minLines: 6,
                maxLines: 10,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: '1xOP01-001\n4xOP01-013\n…',
                  filled: true,
                  fillColor: kRow,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final daten = await Clipboard.getData(Clipboard.kTextPlain);
                    feld.text = daten?.text ?? '';
                  },
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: const Text('Aus Zwischenablage'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, feld.text), child: const Text('Übernehmen')),
        ],
      ),
    );
  }
}

/// Ein Deck bearbeiten: Leader, Karten, laufende Regelpruefung, Statistik, Sammlung.
class DeckEditorSeite extends StatelessWidget {
  final DeckUmgebung umgebung;
  final String deckId;

  const DeckEditorSeite({super.key, required this.umgebung, required this.deckId});

  static void oeffnen(BuildContext context, DeckUmgebung umgebung, String deckId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeckEditorSeite(umgebung: umgebung, deckId: deckId),
    ));
  }

  static const _typReihenfolge = ['CHARACTER', 'EVENT', 'STAGE'];
  static const _typName = {'CHARACTER': 'Charaktere', 'EVENT': 'Events', 'STAGE': 'Stages'};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: umgebung.decks,
      builder: (context, _) {
        final deck = umgebung.decks.deck(deckId);
        if (deck == null) {
          return const Scaffold(backgroundColor: kBg, body: Center(child: Text('Deck gelöscht.')));
        }
        final pruefung = DeckRegeln.pruefen(deck, umgebung.karte);
        final statistik = DeckStatistik.berechnen(deck, umgebung.karte);
        final abdeckung = DeckAbdeckung.berechnen(deck, umgebung.karte, umgebung.besitzZurNummer);
        final leader = pruefung.leader ?? (deck.leaderId == null ? null : umgebung.karte(deck.leaderId!));

        return Scaffold(
          backgroundColor: kBg,
          appBar: AppBar(
            backgroundColor: kSurface,
            title: GestureDetector(
              onTap: () => _umbenennen(context, deck),
              child: Text(deck.name, style: const TextStyle(fontSize: 17)),
            ),
            actions: [
              IconButton(
                tooltip: 'Als Deckliste teilen',
                icon: const Icon(Icons.ios_share),
                onPressed: () => SharePlus.instance.share(ShareParams(text: DeckText.alsText(deck), subject: deck.name)),
              ),
              PopupMenuButton<String>(
                color: kRow,
                onSelected: (w) {
                  if (w == 'name') _umbenennen(context, deck);
                  if (w == 'loeschen') _loeschen(context, deck);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'name', child: Text('Umbenennen')),
                  PopupMenuItem(value: 'loeschen', child: Text('Deck löschen')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
            children: [
              _leaderZeile(context, deck, leader),
              const SizedBox(height: 12),
              _status(deck, pruefung),
              const SizedBox(height: 12),
              _statistik(statistik),
              const SizedBox(height: 12),
              _sammlung(abdeckung),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Karten (${deck.anzahl})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => KartenSucheSeite.oeffnen(context, umgebung, deckId),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Karten hinzufügen'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ..._kartenListe(context, deck, pruefung),
            ],
          ),
        );
      },
    );
  }

  Widget _leaderZeile(BuildContext context, MeinDeck deck, OpCard? leader) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          if (leader != null)
            GestureDetector(onTap: () => FullScreenCard.show(context, leader), child: CardImage(card: leader, width: 52))
          else
            Container(width: 52, height: 72, decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(7))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Leader', style: TextStyle(fontSize: 11, color: kDim)),
                Text(leader?.name ?? 'Noch keiner gewählt',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (leader != null)
                  Text('${leader.id} · ${leader.colors.join(' / ')}',
                      style: const TextStyle(fontSize: 11.5, color: kDim)),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              final neu = await LeaderWahlSeite.waehlen(context, umgebung);
              if (neu != null) umgebung.decks.ersetzen(deck.kopieMit(leaderId: neu.id));
            },
            child: Text(leader == null ? 'Wählen' : 'Ändern'),
          ),
        ],
      ),
    );
  }

  Widget _status(MeinDeck deck, DeckPruefung p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${deck.anzahl}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const Text(' / 50 Karten', style: TextStyle(fontSize: 14, color: kDim)),
              const Spacer(),
              if (p.gueltig) ...[
                const Icon(Icons.check_circle, color: kChartGut, size: 18),
                const SizedBox(width: 5),
                Text(p.vorbehalt ? 'spielbereit*' : 'spielbereit', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          FortschrittsBalken(anteil: deck.anzahl / 50, komplett: p.gueltig),
          if (!p.gueltig) ...[
            const SizedBox(height: 10),
            for (final m in p.meldungen)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 15, color: kGold),
                    const SizedBox(width: 6),
                    Expanded(child: Text(m, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                  ],
                ),
              ),
          ],
          if (p.sonderregel != null && p.sonderregel!.beschreibung.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Regel dieses Leaders: ${p.sonderregel!.beschreibung} — wird geprüft.',
                style: const TextStyle(fontSize: 12, height: 1.35)),
          ],
          if (p.vorbehalt) ...[
            const SizedBox(height: 6),
            Text(
              '* Dieser Leader hat eine Sonderregel, die die App nicht prüfen kann: '
              '„${p.sonderregel!.ungeprueft.join(' / ')}"',
              style: const TextStyle(fontSize: 11.5, color: kGold, height: 1.35),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Geprüft nach den offiziellen Regeln 1.2.1: 1 Leader, genau 50 Karten, höchstens 4 je '
            'Kartennummer, nur Farben des Leaders — samt Karten, die beliebig viele Kopien erlauben, und '
            'Kosten- oder Typgrenzen des Leaders. Nicht geprüft: Sperrlisten.',
            style: TextStyle(fontSize: 10.5, color: kDim, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _statistik(DeckStatistik s) {
    final typen = _typReihenfolge
        .where((t) => (s.nachTyp[t] ?? 0) > 0)
        .map((t) => '${s.nachTyp[t]} ${_typName[t]}')
        .join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kostenkurve', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          KostenKurve(werte: s.kostenKurve),
          const SizedBox(height: 10),
          Text(typen.isEmpty ? 'Noch keine Karten.' : typen, style: const TextStyle(fontSize: 12, color: kDim)),
          Text('Counter: ${s.counter1000}× 1000 · ${s.counter2000}× 2000',
              style: const TextStyle(fontSize: 12, color: kDim)),
        ],
      ),
    );
  }

  Widget _sammlung(DeckAbdeckung a) {
    final fehlt = a.benoetigt - a.vorhanden;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${a.vorhanden} von ${a.benoetigt} Karten in deiner Sammlung',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          FortschrittsBalken(
            anteil: a.benoetigt == 0 ? 0 : a.vorhanden / a.benoetigt,
            komplett: a.benoetigt > 0 && fehlt == 0,
          ),
          const SizedBox(height: 4),
          const Text('Jedes Artwork zählt — zum Spielen ist es egal.', style: TextStyle(fontSize: 10.5, color: kDim)),
          if (fehlt > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => umgebung.aufWunschliste(a.fehlend),
                icon: const Icon(Icons.star_border, size: 18),
                label: Text('$fehlt fehlende Karten auf die Wunschliste'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _kartenListe(BuildContext context, MeinDeck deck, DeckPruefung p) {
    if (deck.karten.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('Noch leer — „Karten hinzufügen" zeigt nur Karten in den Farben des Leaders.',
              style: TextStyle(color: kDim, fontSize: 12.5)),
        ),
      ];
    }
    final falsch = {for (final k in p.falscheFarbe) k.id, for (final k in p.falscherTyp) k.id};
    final sonder = {for (final k in p.sonderregelVerstoss) k.id};
    final ueberGrenze = p.zuViele.keys.toSet();

    final gruppen = <String, List<MapEntry<String, int>>>{};
    for (final e in deck.karten.entries) {
      final typ = umgebung.karte(e.key)?.cardType ?? '?';
      gruppen.putIfAbsent(typ, () => []).add(e);
    }
    final reihenfolge = [..._typReihenfolge, ...gruppen.keys.where((t) => !_typReihenfolge.contains(t))];

    final ergebnis = <Widget>[];
    for (final typ in reihenfolge) {
      final liste = gruppen[typ];
      if (liste == null) continue;
      liste.sort((a, b) {
        final ka = umgebung.karte(a.key)?.costLife ?? 0;
        final kb = umgebung.karte(b.key)?.costLife ?? 0;
        return ka != kb ? ka.compareTo(kb) : a.key.compareTo(b.key);
      });
      final summe = liste.fold(0, (s, e) => s + e.value);
      ergebnis.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text('${_typName[typ] ?? typ} ($summe)',
            style: const TextStyle(fontSize: 12, color: kDim, fontWeight: FontWeight.w600)),
      ));
      for (final e in liste) {
        ergebnis.add(_kartenZeile(context, deck, e.key, e.value,
            falsch: falsch.contains(e.key),
            sonderregel: sonder.contains(e.key),
            ueberGrenze: ueberGrenze.contains(umgebung.karte(e.key)?.baseId)));
      }
    }
    return ergebnis;
  }

  Widget _kartenZeile(BuildContext context, MeinDeck deck, String id, int anzahl,
      {required bool falsch, required bool sonderregel, required bool ueberGrenze}) {
    final karte = umgebung.karte(id);
    final kopien = karte == null ? anzahl : DeckRegeln.kopienDerNummer(deck, karte.baseId, umgebung.karte);
    final grenze = karte == null ? DeckRegeln.maxKopien : DeckRegeln.grenze(karte);
    final hinweis = karte == null
        ? 'unbekannte Karte'
        : falsch
            ? (karte.cardType == 'LEADER' ? 'Leader gehören nicht ins Deck' : 'Farbe passt nicht zum Leader')
            : sonderregel
                ? 'verstößt gegen die Regel des Leaders'
                : ueberGrenze
                    ? 'mehr als 4 dieser Nummer'
                    : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (karte != null)
            GestureDetector(onTap: () => FullScreenCard.show(context, karte), child: CardImage(card: karte, width: 34))
          else
            Container(width: 34, height: 47, decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(5))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(karte?.name ?? id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                Text(
                  hinweis ?? '$id${karte?.costLife != null ? ' · Kosten ${karte!.costLife}' : ''}',
                  style: TextStyle(fontSize: 10.5, color: hinweis != null ? kAccent : kDim),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => umgebung.decks.setzeKarte(deckId, id, anzahl - 1),
            icon: Icon(anzahl == 1 ? Icons.delete_outline : Icons.remove, size: 18, color: kDim),
          ),
          SizedBox(width: 18, child: Text('$anzahl', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: kopien >= grenze ? null : () => umgebung.decks.setzeKarte(deckId, id, anzahl + 1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _umbenennen(BuildContext context, MeinDeck deck) async {
    final feld = TextEditingController(text: deck.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Deck umbenennen'),
        content: TextField(controller: feld, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, feld.text.trim()), child: const Text('Speichern')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) umgebung.decks.ersetzen(deck.kopieMit(name: name));
  }

  Future<void> _loeschen(BuildContext context, MeinDeck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('„${deck.name}" löschen?'),
        content: const Text('Die Karten deiner Sammlung bleiben unberührt — nur die Deckliste geht weg.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      umgebung.decks.loeschen(deck.id);
    }
  }
}

/// Saeulen fuer die Kosten 0 bis 10+ - schmal, oben abgerundet, unten gerade auf der
/// Grundlinie, die Anzahl ueber jeder Saeule.
class KostenKurve extends StatelessWidget {
  final List<int> werte;
  const KostenKurve({super.key, required this.werte});

  @override
  Widget build(BuildContext context) {
    final maxWert = werte.fold(0, (m, w) => w > m ? w : m);
    const hoehe = 70.0;
    return SizedBox(
      height: hoehe + 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < werte.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (werte[i] > 0)
                    Text('${werte[i]}', style: const TextStyle(fontSize: 10.5, color: Colors.white)),
                  const SizedBox(height: 2),
                  Container(
                    width: 14,
                    height: maxWert == 0 ? 0 : hoehe * werte[i] / maxWert,
                    decoration: const BoxDecoration(
                      color: kChartLinie,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  Container(height: 1, color: kGitter),
                  const SizedBox(height: 3),
                  Text(i == 10 ? '10+' : '$i', style: const TextStyle(fontSize: 10, color: kDim)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Karten zum Deck hinzufuegen - nur, was zum Leader passt.
class KartenSucheSeite extends StatefulWidget {
  final DeckUmgebung umgebung;
  final String deckId;

  const KartenSucheSeite({super.key, required this.umgebung, required this.deckId});

  static void oeffnen(BuildContext context, DeckUmgebung umgebung, String deckId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => KartenSucheSeite(umgebung: umgebung, deckId: deckId)));
  }

  @override
  State<KartenSucheSeite> createState() => _KartenSucheSeiteState();
}

class _KartenSucheSeiteState extends State<KartenSucheSeite> {
  String _suche = '';
  String? _typ;

  @override
  Widget build(BuildContext context) {
    final u = widget.umgebung;
    return ListenableBuilder(
      listenable: u.decks,
      builder: (context, _) {
        final deck = u.decks.deck(widget.deckId);
        if (deck == null) return const Scaffold(backgroundColor: kBg);
        final leader = deck.leaderId == null ? null : u.karte(deck.leaderId!);
        final q = _suche.toLowerCase();

        final treffer = u.katalog
            .where((k) => DeckRegeln.passt(k, leader?.cardType == 'LEADER' ? leader : null))
            .where((k) => _typ == null || k.cardType == _typ)
            .where((k) => q.isEmpty || k.name.toLowerCase().contains(q) || k.id.toLowerCase().contains(q))
            .take(120)
            .toList();

        return Scaffold(
          backgroundColor: kBg,
          appBar: AppBar(
            backgroundColor: kSurface,
            title: Text('Karten · ${deck.anzahl}/50', style: const TextStyle(fontSize: 16)),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _suche = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Name oder Nummer …',
                    prefixIcon: const Icon(Icons.search, size: 19, color: kDim),
                    filled: true,
                    fillColor: kRow,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip(null, 'Alle'),
                    _chip('CHARACTER', 'Charaktere'),
                    _chip('EVENT', 'Events'),
                    _chip('STAGE', 'Stages'),
                  ],
                ),
              ),
              if (leader != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Text('Nur Karten in ${leader.colors.join(' / ')} — den Farben von ${leader.name}.',
                      style: const TextStyle(fontSize: 11, color: kDim)),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: treffer.length,
                  itemBuilder: (context, i) => _zeile(context, deck, treffer[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String? typ, String text) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(text, style: const TextStyle(fontSize: 12)),
          selected: _typ == typ,
          showCheckmark: false,
          onSelected: (_) => setState(() => _typ = typ),
        ),
      );

  Widget _zeile(BuildContext context, MeinDeck deck, OpCard k) {
    final u = widget.umgebung;
    final imDeck = deck.karten[k.id] ?? 0;
    final kopien = DeckRegeln.kopienDerNummer(deck, k.baseId, u.karte);
    final besitz = u.besitzZurNummer(k.baseId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          GestureDetector(onTap: () => FullScreenCard.show(context, k), child: CardImage(card: k, width: 34)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${k.name}${k.alt ? ' (Alt-Art)' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                Text(
                  '${k.id} · Kosten ${k.costLife ?? '–'} · ${k.colors.join('/')}'
                  '${besitz > 0 ? ' · ×$besitz im Besitz' : ''}',
                  style: const TextStyle(fontSize: 10.5, color: kDim),
                ),
              ],
            ),
          ),
          if (imDeck > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('$imDeck', style: const TextStyle(fontWeight: FontWeight.w700, color: kGold)),
            ),
          IconButton(
            tooltip: kopien >= DeckRegeln.grenze(k) ? 'Schon 4 dieser Nummer im Deck' : 'Hinzufügen',
            onPressed: kopien >= DeckRegeln.grenze(k) ? null : () => u.decks.setzeKarte(widget.deckId, k.id, imDeck + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

/// Leader auswaehlen.
class LeaderWahlSeite extends StatefulWidget {
  final DeckUmgebung umgebung;
  const LeaderWahlSeite({super.key, required this.umgebung});

  static Future<OpCard?> waehlen(BuildContext context, DeckUmgebung umgebung) =>
      Navigator.of(context).push<OpCard>(MaterialPageRoute(builder: (_) => LeaderWahlSeite(umgebung: umgebung)));

  @override
  State<LeaderWahlSeite> createState() => _LeaderWahlSeiteState();
}

class _LeaderWahlSeiteState extends State<LeaderWahlSeite> {
  String _suche = '';

  @override
  Widget build(BuildContext context) {
    final q = _suche.toLowerCase();
    final leader = widget.umgebung.katalog
        .where((k) => k.cardType == 'LEADER')
        .where((k) =>
            q.isEmpty ||
            k.name.toLowerCase().contains(q) ||
            k.id.toLowerCase().contains(q) ||
            k.colors.any((f) => f.toLowerCase().contains(q)))
        .toList();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kSurface, title: Text('Leader wählen (${leader.length})', style: const TextStyle(fontSize: 16))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _suche = v.trim()),
              decoration: InputDecoration(
                hintText: 'Name, Nummer oder Farbe (red, green …)',
                prefixIcon: const Icon(Icons.search, size: 19, color: kDim),
                filled: true,
                fillColor: kRow,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: leader.length,
              itemBuilder: (context, i) {
                final k = leader[i];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        CardImage(card: k, width: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${k.name}${k.alt ? ' (Alt-Art)' : ''}',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              Text('${k.id} · ${k.colors.join(' / ')}',
                                  style: const TextStyle(fontSize: 11, color: kDim)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: kDim),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
