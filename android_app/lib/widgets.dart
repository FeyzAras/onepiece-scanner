import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'card_model.dart';

const kBg = Color(0xFF0B0D10);
const kSurface = Color(0xFF15181D);
const kRow = Color(0xFF1D2128);
const kChip = Color(0xFF2A2F38);
const kAccent = Color(0xFFE0383D);
const kGold = Color(0xFFFFB703);
const kDim = Color(0xFF9AA1AC);
const kOk = Color(0xFF3DDC84);

/// Kartenbild im richtigen Seitenverhaeltnis, mit Zwischenspeicher auf dem Geraet.
class CardImage extends StatelessWidget {
  final OpCard card;
  final double width;
  final BorderRadius? radius;

  const CardImage({super.key, required this.card, required this.width, this.radius});

  @override
  Widget build(BuildContext context) {
    final height = width * 88 / 63;
    final placeholder = Container(width: width, height: height, color: const Color(0xFF2B313A));
    final image = card.img == null
        ? placeholder
        : CachedNetworkImage(
            imageUrl: card.img!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    return ClipRRect(borderRadius: radius ?? BorderRadius.circular(7), child: image);
  }
}

/// Kartenbild im Vollbild, zum Heranzoomen.
class FullScreenCard extends StatelessWidget {
  final OpCard card;
  const FullScreenCard({super.key, required this.card});

  static void show(BuildContext context, OpCard card) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FullScreenCard(card: card),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${card.name} · ${card.id}', style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: card.img == null
              ? const Icon(Icons.image_not_supported_outlined, size: 64, color: kDim)
              : CachedNetworkImage(
                  imageUrl: card.img!,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const CircularProgressIndicator(),
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.image_not_supported_outlined, size: 64, color: kDim),
                ),
        ),
      ),
    );
  }
}

/// Kleines Etikett, z.B. "Nummer + Name" oder "×3".
class Chip2 extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  final double fontSize;

  const Chip2(this.text, {super.key, this.background = kChip, this.foreground = kDim, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: fontSize, color: foreground, fontWeight: FontWeight.w600)),
    );
  }
}

String formatEuro(double value) => '${value.toStringAsFixed(2)} €';
