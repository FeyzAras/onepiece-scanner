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
      );
}
