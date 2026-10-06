import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ein Ordner, in den gescannte Karten einsortiert werden.
class ScanFolder {
  final String id;
  final String name;

  const ScanFolder({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static ScanFolder? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    if (id == null || name == null) return null;
    return ScanFolder(id: id, name: name);
  }
}

/// Ein gespeicherter Scan. Gespeichert wird nur die Karten-ID plus Metadaten;
/// die vollen Kartendaten kommen beim Laden aus dem mitgelieferten Katalog.
class StoredScan {
  final String cardId;
  final String folderId;
  final String how;
  final DateTime at;

  StoredScan({required this.cardId, required this.folderId, required this.how, required this.at});

  Map<String, dynamic> toJson() => {
        'id': cardId,
        'folder': folderId,
        'how': how,
        'at': at.millisecondsSinceEpoch,
      };

  static StoredScan? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null) return null;
    return StoredScan(
      cardId: id,
      folderId: (j['folder'] ?? CollectionStore.defaultFolderId) as String,
      how: (j['how'] ?? 'number') as String,
      at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
    );
  }
}

class CollectionState {
  final List<ScanFolder> folders;
  final String activeFolderId;
  final List<StoredScan> scans;

  const CollectionState({required this.folders, required this.activeFolderId, required this.scans});
}

/// Speichert Ordner und gescannte Karten dauerhaft auf dem Geraet.
class CollectionStore {
  static const _key = 'collection_v2';
  static const _legacyKey = 'scanned_cards_v1';
  static const defaultFolderId = 'default';
  static const defaultFolderName = 'Meine Sammlung';

  static Future<CollectionState> load() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final folders = (map['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(ScanFolder.fromJson)
            .whereType<ScanFolder>()
            .toList();
        final scans = (map['scans'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(StoredScan.fromJson)
            .whereType<StoredScan>()
            .toList();
        return CollectionState(
          folders: folders.isEmpty ? _defaultFolders() : folders,
          activeFolderId: (map['active'] as String?) ?? defaultFolderId,
          scans: scans,
        );
      } catch (_) {
        // beschaedigte Daten: lieber leer starten als abstuerzen
      }
    }

    // Aus der Vorversion uebernehmen, damit bereits gescannte Karten nicht verloren gehen
    final legacy = prefs.getString(_legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      try {
        final list = (jsonDecode(legacy) as List).cast<Map<String, dynamic>>();
        final scans = list
            .map((j) => StoredScan(
                  cardId: (j['id'] ?? '') as String,
                  folderId: defaultFolderId,
                  how: (j['how'] ?? 'number') as String,
                  at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
                ))
            .where((s) => s.cardId.isNotEmpty)
            .toList();
        return CollectionState(folders: _defaultFolders(), activeFolderId: defaultFolderId, scans: scans);
      } catch (_) {}
    }

    return CollectionState(folders: _defaultFolders(), activeFolderId: defaultFolderId, scans: const []);
  }

  static List<ScanFolder> _defaultFolders() =>
      [const ScanFolder(id: defaultFolderId, name: defaultFolderName)];

  static Future<void> save(CollectionState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'folders': state.folders.map((f) => f.toJson()).toList(),
        'active': state.activeFolderId,
        'scans': state.scans.map((s) => s.toJson()).toList(),
      }),
    );
  }
}
