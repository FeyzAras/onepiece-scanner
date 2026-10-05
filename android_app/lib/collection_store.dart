import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ein gespeicherter Scan-Eintrag. Gespeichert wird nur die Karten-ID plus Metadaten;
/// die vollen Kartendaten kommen beim Laden aus dem mitgelieferten Katalog.
class StoredScan {
  final String cardId;
  final String how;
  final DateTime at;

  StoredScan({required this.cardId, required this.how, required this.at});

  Map<String, dynamic> toJson() => {
        'id': cardId,
        'how': how,
        'at': at.millisecondsSinceEpoch,
      };

  static StoredScan? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null) return null;
    return StoredScan(
      cardId: id,
      how: (j['how'] ?? 'number') as String,
      at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Speichert die gescannte Sammlung dauerhaft auf dem Geraet, damit sie beim
/// naechsten Start wieder da ist.
class CollectionStore {
  static const _key = 'scanned_cards_v1';

  static Future<List<StoredScan>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(StoredScan.fromJson).whereType<StoredScan>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<StoredScan> scans) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(scans.map((s) => s.toJson()).toList()));
  }
}
