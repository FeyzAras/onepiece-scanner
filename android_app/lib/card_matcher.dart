import 'card_model.dart';

class MatchResult {
  final OpCard card;
  final double score;

  /// 'number' = ueber die aufgedruckte Kartennummer erkannt (eindeutig),
  /// 'name'   = ueber den Kartennamen erkannt (kann bei gleichnamigen Karten danebenliegen).
  final String how;

  const MatchResult(this.card, this.score, this.how);
}

const List<String> _knownPrefixes = ['OP', 'ST', 'EB', 'PRB', 'P'];

/// Kandidaten fuer eine Kartennummer: ein kurzer Kopf (Set-Code) + Trenner + drei Ziffern.
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

  MatchResult? match(String ocrText) {
    final byNumber = _matchByNumber(ocrText);
    if (byNumber != null) return byNumber;
    return _matchByName(ocrText);
  }

  MatchResult? _matchByNumber(String text) {
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
          if (card != null) return MatchResult(card, 3.0, 'number');
        }
      }
    }
    return null;
  }

  MatchResult? _matchByName(String text) {
    final ocrTokens = normalizeTokens(text);
    if (ocrTokens.isEmpty) return null;
    final ocrSet = ocrTokens.toSet();
    final ocrJoined = ocrTokens.join(' ');

    OpCard? best;
    double bestScore = 0;
    for (final card in cards) {
      final nameTokens = normalizeTokens(card.name);
      if (nameTokens.isEmpty) continue;
      var overlap = 0;
      for (final t in nameTokens) {
        if (ocrSet.contains(t)) overlap++;
      }
      var score = overlap / nameTokens.length;
      final nameJoined = nameTokens.join(' ');
      if (nameJoined.length > 2 && ocrJoined.contains(nameJoined)) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = card;
      }
    }
    if (best == null || bestScore < 1.3) return null;
    return MatchResult(best, bestScore, 'name');
  }
}
