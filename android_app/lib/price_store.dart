import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Tagesaktuelle Preise, die die App beim Start aus dem Projekt-Repository nachlaedt.
///
/// Warum nicht einfach die Preise im Kartenkatalog der App? Der Katalog ist rund 3 MB gross
/// und aendert sich selten, die Preise aendern sich taeglich. Getrennt geladen heisst:
/// rund 150 KB pro Tag statt einer neuen App-Version bei jeder Preisaenderung.
///
/// Faellt der Abruf aus (kein Netz), gelten die zuletzt geladenen Preise, und davor die
/// im Katalog mitgelieferten. Es ist also immer ein Preis da, nur eventuell ein aelterer.
class LivePrices {
  /// Preis je Karten-ID (normale Version und Alt-Art getrennt).
  final Map<String, double> byCardId;

  /// Alle Cardmarket-Versionen je Kartennummer, aufsteigend. Noetig, damit eine vom
  /// Nutzer gewaehlte Version auch nach einer Preisaktualisierung noch dieselbe bleibt.
  final Map<String, List<double>> optionsByBaseId;

  /// Stand der Cardmarket-Daten (Datum).
  final String asOf;

  const LivePrices({required this.byCardId, required this.optionsByBaseId, required this.asOf});

  bool get isEmpty => byCardId.isEmpty;

  static LivePrices? parse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final prices = <String, double>{};
      (map['prices'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
        final amount = (value as num?)?.toDouble();
        if (amount != null && amount > 0) prices[key] = amount;
      });
      if (prices.isEmpty) return null;

      final options = <String, List<double>>{};
      (map['options'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
        final list = (value as List?)?.map((e) => (e as num).toDouble()).toList();
        if (list != null && list.length > 1) options[key] = list;
      });

      return LivePrices(
        byCardId: prices,
        optionsByBaseId: options,
        asOf: (map['asOf'] ?? '') as String,
      );
    } catch (_) {
      return null;
    }
  }
}

class PriceStore {
  static const _cacheKey = 'prices_cache_v1';
  static const _remoteUrl =
      'https://raw.githubusercontent.com/FeyzAras/onepiece-scanner/master/docs/data/prices.json';

  static Future<LivePrices?> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    return raw == null ? null : LivePrices.parse(raw);
  }

  /// Holt den aktuellen Stand. Gibt null zurueck, wenn das nicht klappt - dann bleibt
  /// der vorhandene Stand bestehen.
  static Future<LivePrices?> fetchRemote() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_remoteUrl));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final raw = await response.transform(utf8.decoder).join();
      final parsed = LivePrices.parse(raw);
      if (parsed == null) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, raw);
      return parsed;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
