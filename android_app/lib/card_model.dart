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

  /// Cardmarkets Produktnummer der zugeordneten Druckvariante.
  ///
  /// Wird fuer den Import eines Cardmarket-Bestandsexports gebraucht: Dessen
  /// Spalte `idProduct` trifft darueber exakt die richtige Karte, inklusive der
  /// Unterscheidung von normalem Artwork und Alt-Art.
  final int? idProduct;

  const CardPrice({
    required this.amount,
    required this.currency,
    required this.basis,
    required this.source,
    required this.asOf,
    this.confidence = PriceConfidence.unsicher,
    this.idProduct,
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
        idProduct: idProduct,
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
      idProduct: (j['idProduct'] as num?)?.toInt(),
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

  /// Alle Farben der Karte. Zweifarbige Leader haben zwei (z.B. Rot/Gruen) - beim
  /// Deckbau bestimmen sie, welche Karten erlaubt sind.
  final List<String> colors;

  final int? power;
  final int? costLife;

  /// Counter-Wert (bei Figuren 1000 oder 2000), sonst null.
  final int? counter;

  /// Typen wie "East Blue" oder "Straw Hat Crew".
  final List<String> types;

  /// Aus welchem Produkt dieses Motiv stammt, laut Bandai - etwa "Romance Dawn" oder
  /// "One Piece Card the Best". Null bei aelteren Katalogen.
  final String? produkt;

  /// Set-Codes dieses Produkts, z.B. ["OP01"] oder ["OP15", "EB04"]. Leer bei Promo-
  /// und Sammelprodukten ohne Code.
  final List<String> produktSets;

  final String effect;
  final String? img;
  final CardPrice? price;

  /// Bild-Fingerabdruck (dHash). Nur gesetzt, wenn es zur Kartennummer mehrere
  /// Artworks gibt - nur dort wird er zum Unterscheiden gebraucht.
  final String? imgHash;

  /// Karte, die nie auf Englisch erschienen ist. Ihr Bild stammt dann von der
  /// japanischen Kartenseite.
  final bool jpOnly;

  /// Alle Cardmarket-Preise zu dieser Kartennummer, aufsteigend. Dient der App dazu,
  /// die Spanne anzuzeigen und den Nutzer umschalten zu lassen, falls die automatische
  /// Zuordnung danebenliegt. Leer, wenn es nur eine Version gibt.
  final List<double> priceOptions;

  bool get hasPriceChoice => priceOptions.length > 1;

  /// Farbe(n) fuer die Anzeige: "Red" oder "Red/Green".
  String get color => colors.join('/');

  /// Welches Sammelkartenspiel. Aktuell nur One Piece, aber die Sammlung
  /// gruppiert bereits danach, damit weitere Spiele spaeter dazupassen.
  String get game => 'One Piece Card Game';

  /// Set-Kuerzel aus der Kartennummer, z.B. 'OP17' aus 'OP17-113'.
  String get setCode {
    final idx = baseId.indexOf('-');
    return idx > 0 ? baseId.substring(0, idx) : baseId;
  }

  /// Platz dieses Motivs unter allen Motiven der Nummer: 0 Normalversion, 1 die erste
  /// Alt-Art (-ALT), k die k-te (-ALTk). -1, wenn die ID nicht in das Schema passt.
  int get motivIndex => motivIndexVon(id, baseId);

  /// Ein Nachdruck (Bandais Bildname endet auf _r1, _r2 ...): gleiches Motiv wie die
  /// Normalversion, aber aus einem anderen Produkt.
  bool get istNachdruck => RegExp(r'_r\d+\.\w+$').hasMatch(img ?? '');

  /// Kurzbezeichnung des Motivs fuer die Anzeige.
  String get motivName => !alt ? 'Normal' : (istNachdruck ? 'Nachdruck' : 'Parallele');

  const OpCard({
    required this.id,
    required this.baseId,
    required this.alt,
    required this.name,
    required this.rarity,
    required this.cardType,
    this.colors = const [],
    this.power,
    this.costLife,
    this.counter,
    this.types = const [],
    this.produkt,
    this.produktSets = const [],
    required this.effect,
    this.img,
    this.price,
    this.imgHash,
    this.priceOptions = const [],
    this.jpOnly = false,
  });

  factory OpCard.fromJson(Map<String, dynamic> j) => OpCard(
        id: (j['id'] ?? '') as String,
        baseId: (j['baseId'] ?? '') as String,
        alt: (j['alt'] ?? false) as bool,
        name: (j['name'] ?? '') as String,
        rarity: (j['rarity'] ?? '') as String,
        cardType: (j['cardType'] ?? '') as String,
        colors: _farben(j),
        power: (j['power'] as num?)?.toInt(),
        costLife: (j['costLife'] as num?)?.toInt(),
        counter: (j['counter'] as num?)?.toInt(),
        types: (j['types'] as List?)?.map((e) => '$e').toList() ?? const [],
        produkt: j['produkt'] is String ? j['produkt'] as String : null,
        produktSets: (j['produktSets'] as List?)?.map((e) => '$e').toList() ?? const [],
        effect: (j['effect'] ?? '') as String,
        img: j['img'] as String?,
        price: CardPrice.fromJson(j['price'] as Map<String, dynamic>?),
        imgHash: j['imgHash'] as String?,
        jpOnly: (j['jpOnly'] ?? false) as bool,
        priceOptions:
            (j['priceOptions'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
      );

  /// Liest `colors` (Liste) und faellt auf das alte Einzelfeld `color` zurueck. Aeltere
  /// Katalogdateien kannten nur die erste Farbe.
  static List<String> _farben(Map<String, dynamic> j) {
    final liste = j['colors'];
    if (liste is List && liste.isNotEmpty) {
      return liste.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }
    final einzeln = j['color'];
    return einzeln is String && einzeln.isNotEmpty ? [einzeln] : const [];
  }
}

/// Platz eines Motivs: Nummer -> 0, Nummer-ALT -> 1, Nummer-ALTk -> k; -1 sonst.
int motivIndexVon(String id, String baseId) {
  final i = id.toUpperCase();
  final b = baseId.toUpperCase();
  if (i == b) return 0;
  if (!i.startsWith(b)) return -1;
  final m = RegExp(r'^-ALT(\d*)$').firstMatch(i.substring(b.length));
  if (m == null) return -1;
  final zahl = m.group(1)!;
  return zahl.isEmpty ? 1 : int.parse(zahl);
}

/// Umkehrung von [motivIndexVon]: 0 -> Nummer, 1 -> Nummer-ALT, k -> Nummer-ALTk.
String motivIdVon(String baseId, int index) => switch (index) {
      0 => baseId,
      1 => '$baseId-ALT',
      _ => '$baseId-ALT$index',
    };
