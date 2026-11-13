import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_installer.dart';
import 'card_matcher.dart';
import 'card_model.dart';
import 'collection_export.dart';
import 'collection_import.dart';
import 'collection_store.dart';
import 'collection_view.dart';
import 'deck_model.dart';
import 'decks_view.dart';
import 'import_view.dart';
import 'price_store.dart';
import 'scanner_view.dart';
import 'update_service.dart';
import 'update_view.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const OpScannerApp());
}

class OpScannerApp extends StatelessWidget {
  const OpScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One Piece Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kAccent, secondary: kGold, surface: kSurface),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  CardMatcher? _matcher;
  final List<CollectionEntry> _collection = [];
  List<ScanFolder> _folders = const [];
  String _activeFolderId = CollectionStore.defaultFolderId;

  /// Vom Nutzer gewaehlte Druckvariante je Karten-ID: der Platz in der Versionsliste.
  final Map<String, int> _priceChoice = {};

  /// Gespeicherte Scans, zu denen der mitgelieferte Katalog keine Karte kennt.
  ///
  /// Sie werden nicht angezeigt, aber unveraendert weitergeschrieben. Sonst wuerde
  /// ein App-Update, das eine Karten-ID aendert, die betroffenen Karten beim naechsten
  /// Speichern endgueltig loeschen - unbemerkt.
  List<StoredScan> _unresolvedScans = const [];

  /// Eintraege, die sich gar nicht lesen liessen. Ebenfalls nur durchreichen.
  List<Map<String, dynamic>> _unreadableScans = const [];

  /// true, wenn die gespeicherte Sammlung nicht gelesen werden konnte. Der Rohtext
  /// liegt dann gesichert vor.
  bool _loadFailed = false;

  /// Tagesaktuelle Preise aus dem Repository. Null, solange nichts geladen wurde -
  /// dann gelten die im Katalog mitgelieferten Preise.
  LivePrices? _livePrices;

  DeckData? _decks;
  bool _decksLoading = true;

  @override
  void initState() {
    super.initState();
    // Update-Pruefung erst nach dem Laden und nie blockierend: Sie braucht Netz,
    // und ohne Netz soll die App trotzdem sofort benutzbar sein.
    _load().then((_) => _updateVorbereiten());
  }

  // ------------------------------------------------------------------- Update

  /// Installierte Version, z.B. "0.9.0". Leer, solange unbekannt.
  String _version = '';

  /// Angebotenes Update, oder null.
  UpdateInfo? _update;

  /// Hinweis fuer diese Sitzung weggeklickt.
  bool _updateHinweisAus = false;

  Future<void> _updateVorbereiten() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // ohne eigene Version keine Pruefung
    }
    // Reste frueherer Downloads entfernen - nach einer erfolgreichen Installation
    // startet die App neu und kann erst jetzt aufraeumen.
    unawaited(updateOrdner().then(UpdateService.aufraeumen));
    await _updatePruefen();
  }

  Future<void> _updatePruefen({bool manuell = false}) async {
    if (_version.isEmpty) {
      if (manuell) _melden('Die eigene Version ist unbekannt — Prüfung nicht möglich.');
      return;
    }
    final ergebnis = await UpdateService.pruefen(
      installierteVersion: _version,
      androidVersion: await AppInstaller.androidVersion(),
      manuell: manuell,
    );
    if (!mounted) return;

    setState(() {
      _update = ergebnis.angebot;
      if (manuell) _updateHinweisAus = false;
    });

    if (!manuell) return;
    final angebot = ergebnis.angebot;
    if (angebot != null) {
      await _updateZeigen(angebot);
    } else if (ergebnis.fehler != null) {
      _melden(ergebnis.fehler!);
    } else {
      _melden('Du hast die neueste Version ($_version).');
    }
  }

  Future<void> _updateZeigen(UpdateInfo info) => showUpdateSheet(
        context,
        info: info,
        installierteVersion: _version,
        vorInstallation: _persist,
        sicherungAnbieten: _sicherungTeilen,
      );

  /// Sichert die vollstaendige Sammlung - auch aus dem Update-Dialog heraus, falls
  /// Android das Update ablehnt.
  Future<void> _sicherungTeilen() async {
    try {
      await CollectionExport.share(
        entries: _collection,
        priceOf: _priceOf,
        choiceOf: (card) => _priceChoice[card.id],
        folderName: (id) => _folders
            .firstWhere((f) => f.id == id, orElse: () => const ScanFolder(id: '', name: '—'))
            .name,
        priceAsOf: _priceAsOf,
      );
    } catch (e) {
      _melden('Sicherung fehlgeschlagen: $e');
    }
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/cards.json');
    final cards = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(OpCard.fromJson).toList();
    final matcher = CardMatcher(cards);

    final state = await CollectionStore.load();
    final restored = <CollectionEntry>[];
    final unresolved = <StoredScan>[];
    for (final s in state.scans) {
      final card = matcher.byId(s.cardId);
      if (card != null) {
        restored.add(CollectionEntry(card: card, folderId: s.folderId, how: s.how, at: s.at));
      } else {
        // Katalog kennt diese ID nicht (mehr). Aufbewahren statt verwerfen.
        unresolved.add(s);
      }
    }

    if (!mounted) return;
    setState(() {
      _matcher = matcher;
      _folders = state.folders;
      _activeFolderId = state.activeFolderId;
      _unresolvedScans = unresolved;
      _unreadableScans = state.unreadableScans;
      _loadFailed = state.loadFailed;
      _priceChoice
        ..clear()
        ..addAll(state.priceChoice);
      _collection
        ..clear()
        ..addAll(restored);
    });

    await _loadPrices();
    _migrateLegacyChoices(state.legacyPriceAmounts, matcher);
    await _loadDecks();
  }

  Future<void> _loadPrices() async {
    final cached = await PriceStore.loadCached();
    if (mounted && cached != null) setState(() => _livePrices = cached);
    final remote = await PriceStore.fetchRemote();
    if (mounted && remote != null) setState(() => _livePrices = remote);
  }

  /// Eine fruehere Fassung speicherte die Preisauswahl als Betrag. Betraege veralten,
  /// sobald die Preise aktualisiert werden - deshalb wird daraus einmalig der Platz
  /// in der Versionsliste bestimmt.
  void _migrateLegacyChoices(Map<String, double> legacy, CardMatcher matcher) {
    if (legacy.isEmpty) return;
    var changed = false;
    legacy.forEach((cardId, amount) {
      final card = matcher.byId(cardId);
      if (card == null) return;
      final options = _optionsFor(card);
      if (options.length < 2) return;
      var best = 0;
      for (var i = 1; i < options.length; i++) {
        if ((options[i] - amount).abs() < (options[best] - amount).abs()) best = i;
      }
      _priceChoice[cardId] = best;
      changed = true;
    });
    if (changed) {
      setState(() {});
      _persist();
    }
  }

  Future<void> _loadDecks() async {
    if (mounted) setState(() => _decksLoading = true);
    // Reihenfolge: zuletzt geladener Stand -> mitgelieferter Stand -> frischer Abruf
    final cached = await DeckStore.loadCached() ?? await DeckStore.loadBundled();
    if (mounted && cached != null) setState(() => _decks = cached);
    final remote = await DeckStore.fetchRemote();
    if (!mounted) return;
    setState(() {
      if (remote != null) _decks = remote;
      _decksLoading = false;
    });
  }

  Future<void> _persist() => CollectionStore.save(CollectionState(
        folders: _folders,
        activeFolderId: _activeFolderId,
        // Die nicht aufloesbaren Eintraege muessen mit, sonst loescht sie der
        // naechste Speichervorgang endgueltig.
        scans: [..._collection.map((e) => e.toStored()), ..._unresolvedScans],
        priceChoice: _priceChoice,
        unreadableScans: _unreadableScans,
      ));

  /// Alle Cardmarket-Versionen dieser Kartennummer - bevorzugt tagesaktuell,
  /// sonst aus dem mitgelieferten Katalog.
  List<double> _optionsFor(OpCard card) =>
      _livePrices?.optionsByBaseId[card.baseId] ?? card.priceOptions;

  /// Geltender Einzelpreis, in dieser Reihenfolge:
  /// vom Nutzer gewaehlte Version -> tagesaktueller Preis -> Preis aus dem Katalog.
  double _priceOf(OpCard card) {
    final choice = _priceChoice[card.id];
    if (choice != null) {
      final options = _optionsFor(card);
      if (choice < options.length) return options[choice];
    }
    return _livePrices?.byCardId[card.id] ?? card.price?.amount ?? 0;
  }

  /// Stand der geltenden Preisdaten.
  String get _priceAsOf => _livePrices?.asOf ?? '';

  void _choosePrice(OpCard card, int? optionIndex) {
    setState(() {
      if (optionIndex == null) {
        _priceChoice.remove(card.id);
      } else {
        _priceChoice[card.id] = optionIndex;
      }
    });
    _persist();
    if (!mounted) return;
    final options = _optionsFor(card);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(optionIndex == null
          ? 'Preis zurückgesetzt: ${card.name}'
          : 'Preis gesetzt: ${options[optionIndex].toStringAsFixed(2)} € für ${card.name}'),
      duration: const Duration(seconds: 2),
    ));
  }

  ScanFolder get _activeFolder => _folders.firstWhere(
        (f) => f.id == _activeFolderId,
        orElse: () => const ScanFolder(
          id: CollectionStore.defaultFolderId,
          name: CollectionStore.defaultFolderName,
        ),
      );

  void _onScanned(MatchResult result) {
    setState(() {
      _collection.insert(
        0,
        CollectionEntry(card: result.card, folderId: _activeFolderId, how: result.how, at: DateTime.now()),
      );
    });
    _persist();
  }

  void _removeOne(OpCard card, String folderId) {
    final index = _collection.indexWhere((e) => e.card.id == card.id && e.folderId == folderId);
    if (index == -1) return;
    setState(() => _collection.removeAt(index));
    _persist();
  }

  void _switchArtwork(CollectionEntry entry, OpCard replacement) {
    final index = _collection.indexOf(entry);
    if (index == -1) return;
    setState(() {
      _collection[index] = CollectionEntry(
        card: replacement,
        folderId: entry.folderId,
        how: entry.how,
        at: entry.at,
      );
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Artwork gewechselt: ${replacement.name}'), duration: const Duration(seconds: 2)),
    );
  }

  // ------------------------------------------------------------------- Import

  Future<void> _import() async {
    final matcher = _matcher;
    if (matcher == null) return;

    final sicherungVom = await CollectionStore.backupTime();
    if (!mounted) return;

    final plan = await showImportSheet(
      context,
      matcher: matcher,
      folders: _folders,
      activeFolderId: _activeFolderId,
      priceOf: _priceOf,
      sicherungVom: sicherungVom,
      onRueckgaengig: () async {
        if (await CollectionStore.restoreBackup()) {
          await _load();
          _melden('Der letzte Import wurde rückgängig gemacht.');
        }
      },
    );
    if (plan == null) return;
    await _importAnwenden(plan);
  }

  /// Schreibt einen bestaetigten Import in die Sammlung.
  ///
  /// Vorher wird immer der bisherige Stand gesichert - ein Fehlgriff ist damit
  /// umkehrbar, solange kein zweiter Import hinterherkommt.
  Future<void> _importAnwenden(ImportPlan plan) async {
    final r = plan.result;

    // Vollstaendige Wiederherstellung: der gespeicherte Zustand wird woertlich
    // zurueckgeschrieben, samt Ordnern, Preisauswahl und unbekannten Eintraegen.
    if (r.format == ImportFormat.sicherung &&
        plan.modus == ImportMode.ersetzen &&
        r.sicherungRoh != null) {
      final ok = await CollectionStore.importRaw(r.sicherungRoh!);
      if (!ok) {
        _melden('Die Sicherung ließ sich nicht einspielen — es wurde nichts verändert.');
        return;
      }
      await _load();
      _melden('Sammlung wiederhergestellt: ${r.kartenAnzahl} Karten.', rueckgaengig: true);
      return;
    }

    await CollectionStore.backupNow();

    final folders = [..._folders];
    var naechsteId = DateTime.now().millisecondsSinceEpoch;
    String neueOrdnerId() => '${naechsteId++}';

    // Zielordner bestimmen
    String? festesZiel;
    if (plan.ziel == ImportZiel.aktiverOrdner) {
      festesZiel = plan.ordnerId ?? _activeFolderId;
    } else if (plan.ziel == ImportZiel.neuerOrdner) {
      final name = (plan.neuerName ?? '').trim();
      final vorhanden = folders.where((f) => f.name.toLowerCase() == name.toLowerCase());
      if (vorhanden.isNotEmpty) {
        festesZiel = vorhanden.first.id;
      } else {
        festesZiel = neueOrdnerId();
        folders.add(ScanFolder(id: festesZiel, name: name.isEmpty ? 'Import' : name));
      }
    }

    /// Ordner einer Zeile - bei "aus der Datei" ueber ID, sonst ueber den Namen.
    String ordnerFuer(ImportRow z) {
      if (festesZiel != null) return festesZiel;
      final id = z.ordnerId;
      if (id != null && folders.any((f) => f.id == id)) return id;
      final name = z.ordnerName?.trim();
      if (name != null && name.isNotEmpty) {
        final treffer = folders.where((f) => f.name.toLowerCase() == name.toLowerCase());
        if (treffer.isNotEmpty) return treffer.first.id;
        final neu = id ?? neueOrdnerId();
        folders.add(ScanFolder(id: neu, name: name));
        return neu;
      }
      return _activeFolderId;
    }

    // Was soll am Ende wo liegen
    final zuSchreiben = <({OpCard card, String folder, int anzahl})>[];
    final zielOrdner = <String>{};
    for (final z in r.treffer) {
      final ordner = ordnerFuer(z);
      zielOrdner.add(ordner);
      zuSchreiben.add((card: z.card!, folder: ordner, anzahl: z.anzahl));
    }

    final neu = [..._collection];

    if (plan.modus == ImportMode.ersetzen) {
      neu.removeWhere((e) => zielOrdner.contains(e.folderId));
    }

    // Bestand je (Karte, Ordner) - fuer "auffuellen"
    final bestand = <String, int>{};
    for (final e in neu) {
      final k = '${e.card.id}\u0000${e.folderId}';
      bestand[k] = (bestand[k] ?? 0) + 1;
    }

    final jetzt = DateTime.now();
    var geschrieben = 0;
    var gekappt = false;

    for (final s in zuSchreiben) {
      final k = '${s.card.id}\u0000${s.folder}';
      var wieviele = s.anzahl;
      if (plan.modus == ImportMode.auffuellen) {
        wieviele = s.anzahl - (bestand[k] ?? 0);
        if (wieviele <= 0) continue;
      }
      for (var i = 0; i < wieviele; i++) {
        if (geschrieben >= CollectionImport.maxGesamt) {
          gekappt = true;
          break;
        }
        neu.add(CollectionEntry(card: s.card, folderId: s.folder, how: 'import', at: jetzt));
        geschrieben++;
      }
      bestand[k] = (bestand[k] ?? 0) + wieviele;
      if (gekappt) break;
    }

    // Neueste zuerst, wie es die Sammlung auch sonst haelt
    neu.sort((a, b) => b.at.compareTo(a.at));

    setState(() {
      _folders = folders;
      _collection
        ..clear()
        ..addAll(neu);
      if (festesZiel != null && folders.any((f) => f.id == festesZiel)) {
        _activeFolderId = festesZiel;
      }
    });
    await _persist();

    final nichtZugeordnet = r.fehler.length;
    _melden(
      '$geschrieben Karten übernommen'
      '${nichtZugeordnet > 0 ? ', $nichtZugeordnet Zeilen nicht zugeordnet' : ''}'
      '${gekappt ? ' (bei ${CollectionImport.maxGesamt} abgebrochen)' : ''}.',
      rueckgaengig: true,
    );
  }

  void _melden(String text, {bool rueckgaengig = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      duration: Duration(seconds: rueckgaengig ? 8 : 4),
      action: rueckgaengig
          ? SnackBarAction(
              label: 'Rückgängig',
              onPressed: () async {
                if (await CollectionStore.restoreBackup()) {
                  await _load();
                  _melden('Der Import wurde rückgängig gemacht.');
                }
              },
            )
          : null,
    ));
  }

  int _ownedCount(String baseId) => _collection
      .where((e) => e.card.baseId.toUpperCase() == baseId.toUpperCase())
      .length;

  OpCard? _cardOf(String baseId) {
    final matcher = _matcher;
    if (matcher == null) return null;
    return matcher.byId(baseId) ?? matcher.byId('$baseId-ALT');
  }

  Future<void> _manageFolders() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ordner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 4),
                const Text('Neu gescannte Karten landen im ausgewählten Ordner.',
                    style: TextStyle(color: kDim, fontSize: 12.5)),
                const SizedBox(height: 14),
                for (final folder in _folders)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      folder.id == _activeFolderId ? Icons.folder : Icons.folder_outlined,
                      color: folder.id == _activeFolderId ? kGold : kDim,
                    ),
                    title: Text(folder.name, style: const TextStyle(fontSize: 14.5)),
                    subtitle: Text('${_collection.where((e) => e.folderId == folder.id).length} Karten',
                        style: const TextStyle(color: kDim, fontSize: 12)),
                    trailing: _folders.length > 1
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 19, color: kDim),
                            onPressed: () async {
                              final ok = await _confirmDeleteFolder(folder);
                              if (ok) setSheetState(() {});
                            },
                          )
                        : null,
                    onTap: () {
                      setState(() => _activeFolderId = folder.id);
                      _persist();
                      Navigator.pop(ctx2);
                    },
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    final created = await _createFolder();
                    if (created) setSheetState(() {});
                  },
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  label: const Text('Neuen Ordner anlegen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Neuer Ordner'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'z. B. Tauschkarten'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return false;
    final folder = ScanFolder(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name);
    setState(() {
      _folders = [..._folders, folder];
      _activeFolderId = folder.id;
    });
    await _persist();
    return true;
  }

  Future<bool> _confirmDeleteFolder(ScanFolder folder) async {
    final count = _collection.where((e) => e.folderId == folder.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('„${folder.name}" löschen?'),
        content: Text(count == 0
            ? 'Der Ordner ist leer.'
            : 'Die $count Karten darin werden ebenfalls entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return false;
    setState(() {
      _collection.removeWhere((e) => e.folderId == folder.id);
      _folders = _folders.where((f) => f.id != folder.id).toList();
      if (_activeFolderId == folder.id) _activeFolderId = _folders.first.id;
    });
    await _persist();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              ScannerView(
                matcher: _matcher,
                activeFolderName: _activeFolder.name,
                onScanned: _onScanned,
                onPickFolder: _manageFolders,
              ),
              CollectionView(
                entries: _collection,
                folders: _folders,
                loadFailed: _loadFailed,
                onRemoveOne: _removeOne,
                onSwitchArtwork: _switchArtwork,
                variantsOf: (card) => _matcher?.variantsOf(card) ?? [card],
                onManageFolders: _manageFolders,
                onImport: _import,
                onCheckUpdate: () => _updatePruefen(manuell: true),
                appVersion: _version,
                priceOf: _priceOf,
                optionsFor: _optionsFor,
                choiceOf: (card) => _priceChoice[card.id],
                onChoosePrice: _choosePrice,
                priceAsOf: _priceAsOf,
              ),
              DecksView(
                data: _decks,
                loading: _decksLoading,
                ownedCount: _ownedCount,
                cardOf: _cardOf,
                onRefresh: _loadDecks,
              ),
            ],
          ),
          // Schwebt ueber der Navigationsleiste, nicht im Layoutfluss: Die Ansichten
          // berechnen ihre Kopfzeilen selbst, ein eingeschobener Streifen wuerde sie
          // verschieben und die Kamera stauchen.
          if (update != null && !_updateHinweisAus)
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: UpdateBanner(
                info: update,
                onAnsehen: () => _updateZeigen(update),
                onSchliessen: () => setState(() => _updateHinweisAus = true),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: kSurface,
        indicatorColor: kAccent,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner, color: Colors.white),
            label: 'Scannen',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _collection.isNotEmpty,
              label: Text('${_collection.length}'),
              backgroundColor: kGold,
              textColor: const Color(0xFF241A00),
              child: const Icon(Icons.grid_view_outlined),
            ),
            selectedIcon: const Icon(Icons.grid_view, color: Colors.white),
            label: 'Sammlung',
          ),
          const NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style, color: Colors.white),
            label: 'Decks',
          ),
        ],
      ),
    );
  }
}
