import 'card_model.dart';
import 'image_hash.dart';

/// Ergebnis eines Erkennungsversuchs.
///
/// Uebernommen wird eine Karte **nur**, wenn die aufgedruckte Kartennummer gelesen wurde
/// (z.B. OP07-055, unten rechts auf der Karte). Der Kartenname allein reicht nicht:
/// viele Karten heissen gleich, und Namen tauchen auch im Effekttext anderer Karten auf.
class MatchResult {
  final OpCard card;

  /// true, wenn zusaetzlich zur Nummer auch der Kartenname im gelesenen Text steht.
  final bool nameConfirmed;

  /// Alle Karten mit dieser Nummer (normales Artwork und Alt-Art). Mehr als ein
  /// Eintrag heisst: Es musste am Bild entschieden werden.
  final List<OpCard> variants;

  /// Wie sicher die Artwork-Entscheidung war.
  final ArtworkPick artwork;

  const MatchResult(this.card, this.nameConfirmed, this.variants, this.artwork);

  String get how => nameConfirmed ? 'number+name' : 'number';
  bool get hasVariants => variants.length > 1;
}

enum ArtworkPick {
  /// Nur ein Artwork zu dieser Nummer - nichts zu entscheiden.
  single,

  /// Mehrere Artworks, per Bildvergleich entschieden.
  byImage,

  /// Mehrere Artworks, aber kein brauchbarer Bildvergleich moeglich -
  /// es wurde die Standardversion genommen.
  fallback,
}

/// Was ein Erkennungsdurchlauf ergeben hat - auch der Fall "Name gelesen, Nummer nicht"
/// wird zurueckgemeldet, damit die App einen sinnvollen Hinweis anzeigen kann.
class MatchOutcome {
  final MatchResult? match;
  final String? nameOnlyHint;

  const MatchOutcome({this.match, this.nameOnlyHint});

  bool get hasMatch => match != null;
}

const List<String> _knownPrefixes = ['OP', 'ST', 'EB', 'PRB', 'P'];

/// Ab diesem Abstand zwischen den beiden Artwork-Kandidaten gilt die Entscheidung
/// als belastbar. Darunter wird die Standardversion genommen.
const int kArtworkDecisionMargin = 4;

final RegExp _candidateRe = RegExp(r'\b([A-Za-z0-9]{1,5})\s*[-–—_.·]\s*(\d{3})\b');
final RegExp _headSplitRe = RegExp(r'^([A-Z0-9]*?)([0-9O]{0,2})$');

List<String> normalizeTokens(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

bool _differsByOne(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) diff++;
  }
  return diff == 1;
}

List<String> _prefixCandidates(String letters) {
  final out = <String>{};
  if (_knownPrefixes.contains(letters)) out.add(letters);
  for (final known in _knownPrefixes) {
    if (_differsByOne(letters, known)) out.add(known);
  }
  if (out.isEmpty) out.add(letters);
  return out.toList();
}

class CardMatcher {
  final List<OpCard> cards;
  final Map<String, OpCard> _byId;
  final Map<String, List<OpCard>> _byBaseId;

  CardMatcher(this.cards)
      : _byId = {for (final c in cards) c.id.toUpperCase(): c},
        _byBaseId = _groupByBase(cards);

  static Map<String, List<OpCard>> _groupByBase(List<OpCard> cards) {
    final map = <String, List<OpCard>>{};
    for (final c in cards) {
      map.putIfAbsent(c.baseId.toUpperCase(), () => []).add(c);
    }
    // Standardversion (ohne Alt-Art-Kennzeichnung) zuerst
    for (final list in map.values) {
      list.sort((a, b) => (a.alt ? 1 : 0).compareTo(b.alt ? 1 : 0));
    }
    return map;
  }

  OpCard? byId(String id) => _byId[id.toUpperCase()];

  List<OpCard> variantsOf(OpCard card) => _byBaseId[card.baseId.toUpperCase()] ?? [card];

  /// [cameraHash] ist der Bild-Fingerabdruck des aktuellen Kamerabildes. Er entscheidet,
  /// welches Artwork gemeint ist, wenn es zu einer Nummer mehrere gibt.
  MatchOutcome match(String ocrText, {String? cameraHash}) {
    final tokens = normalizeTokens(ocrText);
    final joined = tokens.join(' ');

    final baseId = _findNumber(ocrText);
    if (baseId != null) {
      final variants = _byBaseId[baseId] ?? const [];
      if (variants.isNotEmpty) {
        final picked = _pickVariant(variants, cameraHash);
        final nameTokens = normalizeTokens(picked.card.name);
        final nameJoined = nameTokens.join(' ');
        final nameConfirmed = nameJoined.length > 2 && joined.contains(nameJoined);
        return MatchOutcome(
          match: MatchResult(picked.card, nameConfirmed, variants, picked.pick),
        );
      }
    }

    return MatchOutcome(nameOnlyHint: _bestNameGuess(joined));
  }

  ({OpCard card, ArtworkPick pick}) _pickVariant(List<OpCard> variants, String? cameraHash) {
    if (variants.length == 1) return (card: variants.first, pick: ArtworkPick.single);

    if (cameraHash != null) {
      final scored = <({OpCard card, int distance})>[];
      for (final v in variants) {
        final h = v.imgHash;
        if (h != null) scored.add((card: v, distance: ImageHash.distance(cameraHash, h)));
      }
      if (scored.length >= 2) {
        scored.sort((a, b) => a.distance.compareTo(b.distance));
        final margin = scored[1].distance - scored[0].distance;
        if (margin >= kArtworkDecisionMargin) {
          return (card: scored.first.card, pick: ArtworkPick.byImage);
        }
      }
    }
    return (card: variants.first, pick: ArtworkPick.fallback);
  }

  String? _findNumber(String text) {
    for (final m in _candidateRe.allMatches(text)) {
      final rawHead = m.group(1)!.toUpperCase();
      final tail = m.group(2)!;
      final parts = _headSplitRe.firstMatch(rawHead);
      final letters = (parts?.group(1) ?? rawHead).replaceAll('0', 'O').replaceAll('1', 'I');
      final digits = (parts?.group(2) ?? '').replaceAll('O', '0');

      for (final prefix in _prefixCandidates(letters)) {
        final ids = <String>[
          if (digits.isNotEmpty) '$prefix${digits.padLeft(2, '0')}-$tail',
          '$prefix-$tail',
        ];
        for (final id in ids) {
          if (_byBaseId.containsKey(id)) return id;
        }
      }
    }
    return null;
  }

  String? _bestNameGuess(String joined) {
    if (joined.isEmpty) return null;
    for (final card in cards) {
      final nameTokens = normalizeTokens(card.name);
      if (nameTokens.isEmpty) continue;
      final nameJoined = nameTokens.join(' ');
      if (nameJoined.length > 4 && joined.contains(nameJoined)) return card.name;
    }
    return null;
  }
}
