import 'card_model.dart';

/// PLATZHALTER-Preis. Keine echte Cardmarket-Anbindung.
/// Cardmarket veroeffentlicht taegliche Preis-Export-Dateien
/// (cardmarket.com/OnePiece/Data/Price-Guide, One Piece ist abgedeckt).
/// Der Download war aus der Entwicklungsumgebung heraus durch Cloudflare (HTTP 403)
/// blockiert, deshalb steht hier bis auf Weiteres ein deterministischer Platzhalter.
class CardPrice {
  final double amount;
  final String currency;
  final bool isMock;
  const CardPrice(this.amount, this.currency, {this.isMock = true});
}

const Map<String, double> _rarityWeight = {
  'L': 6,
  'SEC': 20,
  'SR': 8,
  'R': 3,
  'UC': 1.2,
  'C': 0.4,
  'P': 2,
  'L-Alt': 10,
  'SR-Alt': 9,
  'SEC-Alt': 22,
};

CardPrice mockPriceFor(OpCard card) {
  final base = _rarityWeight[card.rarity] ?? 1.0;
  var hash = 0;
  for (final unit in card.id.codeUnits) {
    hash = (hash * 31 + unit) & 0xFFFFFFFF;
  }
  final jitter = (hash % 500) / 100.0;
  final price = ((base + jitter) * 100).round() / 100.0;
  return CardPrice(price, 'EUR');
}
