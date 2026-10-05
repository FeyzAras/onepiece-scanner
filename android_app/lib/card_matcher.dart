import 'card_model.dart';

/// Ergebnis eines Erkennungsversuchs.
///
/// Uebernommen wird eine Karte **nur**, wenn die aufgedruckte Kartennummer gelesen wurde
/// (z.B. OP07-055, unten rechts auf der Karte). Der Kartenname allein reicht nicht:
/// viele Karten heissen gleich, und Namen tauchen auch im Effekttext anderer Karten auf.
class MatchResult {
  final OpCard card;

  /// true, wenn zusaetzlich zur Nummer auch der Kartenname im gelesenen Text steht.
  /// Dann stimmen zwei unabhaengige Merkmale ueberein - hoechste Sicherheit.
  final bool nameConfirmed;

  const MatchResult(this.card, this.nameConfirmed);

  String get how => nameConfirmed ? 'number+name' : 'number';
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

/// Kandidaten fuer eine Kartennummer: kurzer Set-Code + Trenner + drei Ziffern.
/// Bewusst tolerant, weil OCR haeufig danebenliegt ("oo01.001" statt "OP01-001").
/// Akzeptiert wird am Ende nur, was einer real existierenden Karten-ID entspricht.
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

  CardMatcher(this.cards) : _byId = {for (final c in cards) c.id.toUpperCase(): c};

  OpCard? byId(String id) => _byId[id.toUpperCase()];

  MatchOutcome match(String ocrText) {
    final tokens = normalizeTokens(ocrText);
    final joined = tokens.join(' ');

    final card = _findByNumber(ocrText);
    if (card != null) {
      final nameTokens = normalizeTokens(card.name);
      final nameJoined = nameTokens.join(' ');
      final nameConfirmed = nameJoined.length > 2 && joined.contains(nameJoined);
      return MatchOutcome(match: MatchResult(card, nameConfirmed));
    }

    // Keine Nummer lesbar. Falls wenigstens ein Kartenname erkennbar ist, wird er als
    // Hinweis zurueckgegeben - aber NICHT als Treffer uebernommen.
    final nameGuess = _bestNameGuess(tokens, joined);
    return MatchOutcome(nameOnlyHint: nameGuess);
  }

  OpCard? _findByNumber(String text) {
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
          final card = _byId[id];
          if (card != null) return card;
        }
      }
    }
    return null;
  }

  String? _bestNameGuess(List<String> tokens, String joined) {
    if (tokens.isEmpty) return null;
    for (final card in cards) {
      final nameTokens = normalizeTokens(card.name);
      if (nameTokens.isEmpty) continue;
      final nameJoined = nameTokens.join(' ');
      if (nameJoined.length > 4 && joined.contains(nameJoined)) return card.name;
    }
    return null;
  }
}
