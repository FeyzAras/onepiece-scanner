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

  /// Vom Nutzer gewaehlte Druckvariante, nach Karten-ID: der Platz in der aufsteigend
  /// sortierten Liste aller Cardmarket-Versionen dieser Kartennummer.
  ///
  /// Bewusst der Platz und nicht der Betrag: Die Preise werden taeglich aktualisiert.
  /// Ein gespeicherter Betrag wuerde dazu fuehren, dass genau die vom Nutzer korrigierten
  /// Karten als einzige auf einem alten Preis einfrieren.
  final Map<String, int> priceChoice;

  /// Aus einer frueheren Fassung uebernommene Betraege. Werden beim ersten Oeffnen in
  /// einen Platz umgerechnet, sobald die Versionsliste vorliegt.
  final Map<String, double> legacyPriceAmounts;

  /// Eintraege, die sich nicht als Scan lesen liessen (fehlende ID, falscher Typ).
  ///
  /// Sie werden unveraendert aufbewahrt und beim naechsten Speichern wieder
  /// mitgeschrieben. Frueher fielen sie einfach weg - ein stiller Datenverlust,
  /// der sich erst bemerkbar machte, wenn Karten fehlten.
  final List<Map<String, dynamic>> unreadableScans;

  /// true, wenn gespeicherte Daten vorhanden, aber nicht lesbar waren. Der Rohtext
  /// wurde dann unter einem Sicherungsschluessel abgelegt und ist wiederherstellbar.
  final bool loadFailed;

  const CollectionState({
    required this.folders,
    required this.activeFolderId,
    required this.scans,
    this.priceChoice = const {},
    this.legacyPriceAmounts = const {},
    this.unreadableScans = const [],
    this.loadFailed = false,
  });
}

/// Speichert Ordner und gescannte Karten dauerhaft auf dem Geraet.
class CollectionStore {
  static const _key = 'collection_v2';
  static const _legacyKey = 'scanned_cards_v1';
  static const defaultFolderId = 'default';
  static const defaultFolderName = 'Meine Sammlung';

  /// Stand vor dem letzten Import - fuer "rueckgaengig".
  static const _backupKey = 'collection_v2_backup';
  static const _backupAtKey = 'collection_v2_backup_at';

  /// Praefix fuer Rohtexte, die sich nicht lesen liessen.
  static const _brokenPrefix = 'collection_v2_broken_';

  /// Liest den gespeicherten Zustand aus einem JSON-Text.
  ///
  /// Absichtlich nachsichtig: einzelne kaputte Eintraege sollen nicht den ganzen
  /// Bestand unlesbar machen. Gibt null zurueck, wenn der Text als Ganzes nicht
  /// zu gebrauchen ist - dann greift der Aufrufer zur Sicherung.
  ///
  /// Achtung: Fuer den Import ist diese Nachsicht zu gefaehrlich (eine leere Datei
  /// waere ein gueltiger leerer Zustand und wuerde die Sammlung loeschen). Dafuer
  /// gibt es [importRaw] mit einer strengeren Pruefung.
  static CollectionState? parse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final folders = (map['folders'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(ScanFolder.fromJson)
          .whereType<ScanFolder>()
          .toList();

      final scans = <StoredScan>[];
      final unreadable = <Map<String, dynamic>>[];
      for (final entry in (map['scans'] as List? ?? [])) {
        if (entry is! Map) {
          continue;
        }
        final j = entry.cast<String, dynamic>();
        final scan = StoredScan.fromJson(j);
        if (scan != null) {
          scans.add(scan);
        } else {
          unreadable.add(j);
        }
      }
      // Eintraege, die eine frühere Fassung als unbekannt zurueckgelegt hat
      for (final entry in (map['unknown'] as List? ?? [])) {
        if (entry is Map) unreadable.add(entry.cast<String, dynamic>());
      }

      final choice = <String, int>{};
      (map['priceChoice'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
        final index = (value as num?)?.toInt();
        if (index != null && index >= 0) choice[key] = index;
      });
      final legacy = <String, double>{};
      (map['prices'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
        final amount = (value as num?)?.toDouble();
        if (amount != null && !choice.containsKey(key)) legacy[key] = amount;
      });

      return CollectionState(
        folders: folders.isEmpty ? _defaultFolders() : folders,
        activeFolderId: (map['active'] as String?) ?? defaultFolderId,
        scans: scans,
        priceChoice: choice,
        legacyPriceAmounts: legacy,
        unreadableScans: unreadable,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<CollectionState> load() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      final parsed = parse(raw);
      if (parsed != null) return parsed;

      // Beschaedigte Daten: NICHT stillschweigend verwerfen. Frueher wurde hier leer
      // gestartet und der naechste Speichervorgang ueberschrieb den Rohtext endgueltig.
      await _keepBroken(prefs, raw);
      return CollectionState(
        folders: _defaultFolders(),
        activeFolderId: defaultFolderId,
        scans: const [],
        loadFailed: true,
      );
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

  /// Legt einen unlesbaren Rohtext zur Seite. Hoechstens drei Stueck, damit die
  /// Einstellungsdatei nicht unbegrenzt waechst.
  static Future<void> _keepBroken(SharedPreferences prefs, String raw) async {
    final vorhanden = prefs.getKeys().where((k) => k.startsWith(_brokenPrefix)).toList()..sort();
    for (final alt in vorhanden.take(vorhanden.length >= 3 ? vorhanden.length - 2 : 0)) {
      await prefs.remove(alt);
    }
    await prefs.setString('$_brokenPrefix${DateTime.now().millisecondsSinceEpoch}', raw);
  }

  static List<ScanFolder> _defaultFolders() =>
      [const ScanFolder(id: defaultFolderId, name: defaultFolderName)];

  static String encode(CollectionState state) => jsonEncode({
        'v': 2,
        'folders': state.folders.map((f) => f.toJson()).toList(),
        'active': state.activeFolderId,
        'scans': state.scans.map((s) => s.toJson()).toList(),
        'priceChoice': state.priceChoice,
        if (state.unreadableScans.isNotEmpty) 'unknown': state.unreadableScans,
      });

  static Future<void> save(CollectionState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encode(state));
  }

  /// Der gespeicherte Rohtext, unveraendert. Grundlage der Sicherungsdatei:
  /// So kann die Sicherung gar nicht vom tatsaechlich Gespeicherten abweichen.
  static Future<String?> exportRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Spielt einen gesicherten Zustand ein und legt den bisherigen zur Seite.
  ///
  /// Streng: Eine leere oder halbe Datei wird abgelehnt. [parse] allein wuerde
  /// `{}` als gueltigen leeren Zustand durchwinken - und damit die Sammlung loeschen.
  static Future<bool> importRaw(String json) async {
    final geprueft = parse(json);
    if (geprueft == null) return false;
    if (geprueft.scans.isEmpty && geprueft.unreadableScans.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final bisher = prefs.getString(_key);
    if (bisher != null) {
      await prefs.setString(_backupKey, bisher);
      await prefs.setInt(_backupAtKey, DateTime.now().millisecondsSinceEpoch);
    }
    await prefs.setString(_key, encode(geprueft));
    return true;
  }

  /// Sichert den aktuellen Stand, bevor ein Import ihn veraendert.
  static Future<void> backupNow() async {
    final prefs = await SharedPreferences.getInstance();
    final bisher = prefs.getString(_key);
    if (bisher == null) return;
    await prefs.setString(_backupKey, bisher);
    await prefs.setInt(_backupAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Zeitpunkt der letzten Sicherung, oder null wenn es keine gibt.
  static Future<DateTime?> backupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_backupAtKey);
    if (millis == null || prefs.getString(_backupKey) == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Macht den letzten Import rueckgaengig.
  static Future<bool> restoreBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final sicherung = prefs.getString(_backupKey);
    if (sicherung == null) return false;
    await prefs.setString(_key, sicherung);
    await prefs.remove(_backupKey);
    await prefs.remove(_backupAtKey);
    return true;
  }

  static Future<void> discardBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backupKey);
    await prefs.remove(_backupAtKey);
  }
}
