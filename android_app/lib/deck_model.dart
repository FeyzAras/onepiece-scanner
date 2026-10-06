import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eine Karte in einer Deckliste.
class DeckCard {
  final String id;
  final int qty;
  const DeckCard(this.id, this.qty);

  static DeckCard? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null) return null;
    return DeckCard(id, (j['qty'] as num?)?.toInt() ?? 1);
  }
}

/// Ein Turnierdeck von onepiecetopdecks.com.
class Deck {
  final String name;
  final String? leaderId;
  final String? date;
  final String? region;
  final String? player;
  final String? placement;
  final String? tournament;
  final String? host;
  final String set;
  final List<DeckCard> cards;
  final int cardCount;

  const Deck({
    required this.name,
    this.leaderId,
    this.date,
    this.region,
    this.player,
    this.placement,
    this.tournament,
    this.host,
    required this.set,
    required this.cards,
    required this.cardCount,
  });

  static Deck? fromJson(Map<String, dynamic> j) {
    final cards = (j['cards'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(DeckCard.fromJson)
        .whereType<DeckCard>()
        .toList();
    if (cards.isEmpty) return null;
    return Deck(
      name: (j['name'] ?? 'Unbenannt') as String,
      leaderId: j['leaderId'] as String?,
      date: j['date'] as String?,
      region: j['region'] as String?,
      player: j['player'] as String?,
      placement: j['placement'] as String?,
      tournament: j['tournament'] as String?,
      host: j['host'] as String?,
      set: (j['set'] ?? '') as String,
      cards: cards,
      cardCount: (j['cardCount'] as num?)?.toInt() ?? cards.fold(0, (s, c) => s + c.qty),
    );
  }
}

class DeckData {
  final String updatedAt;
  final String sourceName;
  final String? sourceUrl;
  final List<Deck> decks;

  const DeckData({
    required this.updatedAt,
    required this.sourceName,
    this.sourceUrl,
    required this.decks,
  });

  static DeckData? parse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final decks = (map['decks'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(Deck.fromJson)
          .whereType<Deck>()
          .toList();
      if (decks.isEmpty) return null;
      final source = map['source'] as Map<String, dynamic>?;
      final urls = (source?['urls'] as List?)?.cast<Map<String, dynamic>>();
      return DeckData(
        updatedAt: (map['updatedAt'] ?? '') as String,
        sourceName: (source?['name'] ?? 'onepiecetopdecks.com') as String,
        sourceUrl: urls != null && urls.isNotEmpty ? urls.first['url'] as String? : null,
        decks: decks,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Laedt die Decklisten. Die App bringt einen Stand mit; beim Start wird versucht,
/// eine neuere Fassung aus dem Projekt-Repository zu holen, damit neue Turnierdecks
/// ohne App-Update ankommen.
class DeckStore {
  static const _cacheKey = 'decks_cache_v1';
  static const _remoteUrl =
      'https://raw.githubusercontent.com/FeyzAras/onepiece-scanner/master/docs/data/decks.json';

  /// Mitgelieferter Stand - funktioniert immer, auch ohne Netz.
  static Future<DeckData?> loadBundled() async {
    try {
      return DeckData.parse(await rootBundle.loadString('assets/decks.json'));
    } catch (_) {
      return null;
    }
  }

  /// Zuletzt heruntergeladener Stand.
  static Future<DeckData?> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    return raw == null ? null : DeckData.parse(raw);
  }

  /// Holt den aktuellen Stand aus dem Repository. Gibt null zurueck, wenn das nicht klappt
  /// (kein Netz, Datei nicht erreichbar) - dann bleibt der vorhandene Stand bestehen.
  static Future<DeckData?> fetchRemote() async {
    try {
      final res = await _get(_remoteUrl);
      if (res == null) return null;
      final data = DeckData.parse(res);
      if (data == null) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, res);
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _get(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}
