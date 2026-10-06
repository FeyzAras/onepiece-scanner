/// Wie sicher der Preis der tatsaechlich vorliegenden Druckvariante zugeordnet ist.
///
/// Cardmarket fuehrt pro Kartennummer mehrere Produkte (Originaldruck, Alt-Art,
/// Nachdrucke, Promos) - teils mit sehr unterschiedlichen Preisen. Die Zuordnung
/// erfolgt in der Datenaufbereitung, siehe scripts/import-cardmarket-prices.js.
enum PriceConfidence {
  /// In der Originaledition des Sets gibt es genau ein Produkt zu dieser Nummer.
  eindeutig,

  /// Zwei Produkte (normales Artwork und Alt-Art). Zugeordnet ueber die Annahme,
  /// dass die Alt-Art die teurere ist.
  paar,

  /// Mehr als zwei Produkte oder keine eindeutige Originaledition - Angabe kann danebenliegen.
  unsicher;

  static PriceConfidence parse(String? raw) => switch (raw) {
        'eindeutig' => PriceConfidence.eindeutig,
        'paar' => PriceConfidence.paar,
        _ => PriceConfidence.unsicher,
      };

  String get label => switch (this) {
        PriceConfidence.eindeutig => 'eindeutig zugeordnet',
        PriceConfidence.paar => 'normal/Alt-Art unterschieden',
        PriceConfidence.unsicher => 'Zuordnung unsicher',
      };
}

/// Preis einer Karte. Quelle sind die taeglich von Cardmarket selbst veroeffentlichten
/// Export-Dateien (siehe scripts/fetch-cardmarket.js). `basis` sagt, welcher Wert genommen
/// wurde: 'trend' ist Cardmarkets Trendpreis, sonst Durchschnitt bzw. niedrigster Preis.
class CardPrice {
  final double amount;
  final String currency;
  final String basis;
  final String source;
  final String asOf;
  final PriceConfidence confidence;

  const CardPrice({
    required this.amount,
    required this.currency,
    required this.basis,
    required this.source,
    required this.asOf,
    this.confidence = PriceConfidence.unsicher,
  });

  bool get isReal => source == 'cardmarket';

  String get basisLabel => switch (basis) {
        'trend' => 'Trend',
        'avg' => 'Durchschnitt',
        'avg7' => 'Ø 7 Tage',
        'avg30' => 'Ø 30 Tage',
        'low' => 'günstigster',
        _ => basis,
      };

  CardPrice copyWithAmount(double value) => CardPrice(
        amount: value,
        currency: currency,
        basis: basis,
        source: source,
        asOf: asOf,
        confidence: confidence,
      );

  static CardPrice? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final amount = (j['amount'] as num?)?.toDouble();
    if (amount == null) return null;
    return CardPrice(
      amount: amount,
      currency: (j['currency'] ?? 'EUR') as String,
      basis: (j['basis'] ?? 'trend') as String,
      source: (j['source'] ?? 'cardmarket') as String,
      asOf: (j['asOf'] ?? '') as String,
      confidence: PriceConfidence.parse(j['confidence'] as String?),
    );
  }
}

class OpCard {
  final String id;
  final String baseId;
  final bool alt;
  final String name;
  final String rarity;
  final String cardType;
  final String color;
  final int? power;
  final int? costLife;
  final String effect;
  final String? img;
  final CardPrice? price;

  /// Bild-Fingerabdruck (dHash). Nur gesetzt, wenn es zur Kartennummer mehrere
  /// Artworks gibt - nur dort wird er zum Unterscheiden gebraucht.
  final String? imgHash;

  /// Alle Cardmarket-Preise zu dieser Kartennummer, aufsteigend. Dient der App dazu,
  /// die Spanne anzuzeigen und den Nutzer umschalten zu lassen, falls die automatische
  /// Zuordnung danebenliegt. Leer, wenn es nur eine Version gibt.
  final List<double> priceOptions;

  bool get hasPriceChoice => priceOptions.length > 1;

  /// Welches Sammelkartenspiel. Aktuell nur One Piece, aber die Sammlung
  /// gruppiert bereits danach, damit weitere Spiele spaeter dazupassen.
  String get game => 'One Piece Card Game';

  /// Set-Kuerzel aus der Kartennummer, z.B. 'OP17' aus 'OP17-113'.
  String get setCode {
    final idx = baseId.indexOf('-');
    return idx > 0 ? baseId.substring(0, idx) : baseId;
  }

  const OpCard({
    required this.id,
    required this.baseId,
    required this.alt,
    required this.name,
    required this.rarity,
    required this.cardType,
    required this.color,
    this.power,
    this.costLife,
    required this.effect,
    this.img,
    this.price,
    this.imgHash,
    this.priceOptions = const [],
  });

  factory OpCard.fromJson(Map<String, dynamic> j) => OpCard(
        id: (j['id'] ?? '') as String,
        baseId: (j['baseId'] ?? '') as String,
        alt: (j['alt'] ?? false) as bool,
        name: (j['name'] ?? '') as String,
        rarity: (j['rarity'] ?? '') as String,
        cardType: (j['cardType'] ?? '') as String,
        color: (j['color'] ?? '') as String,
        power: (j['power'] as num?)?.toInt(),
        costLife: (j['costLife'] as num?)?.toInt(),
        effect: (j['effect'] ?? '') as String,
        img: j['img'] as String?,
        price: CardPrice.fromJson(j['price'] as Map<String, dynamic>?),
        imgHash: j['imgHash'] as String?,
        priceOptions:
            (j['priceOptions'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
      );
}
