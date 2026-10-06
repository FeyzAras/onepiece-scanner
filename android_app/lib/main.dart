import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_matcher.dart';
import 'card_model.dart';
import 'collection_store.dart';
import 'collection_view.dart';
import 'deck_model.dart';
import 'decks_view.dart';
import 'scanner_view.dart';
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

  DeckData? _decks;
  bool _decksLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/cards.json');
    final cards = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(OpCard.fromJson).toList();
    final matcher = CardMatcher(cards);

    final state = await CollectionStore.load();
    final restored = <CollectionEntry>[];
    for (final s in state.scans) {
      final card = matcher.byId(s.cardId);
      if (card != null) {
        restored.add(CollectionEntry(card: card, folderId: s.folderId, how: s.how, at: s.at));
      }
    }

    if (!mounted) return;
    setState(() {
      _matcher = matcher;
      _folders = state.folders;
      _activeFolderId = state.activeFolderId;
      _collection
        ..clear()
        ..addAll(restored);
    });

    await _loadDecks();
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
        scans: _collection.map((e) => e.toStored()).toList(),
      ));

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
    return Scaffold(
      body: IndexedStack(
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
            onRemoveOne: _removeOne,
            onSwitchArtwork: _switchArtwork,
            variantsOf: (card) => _matcher?.variantsOf(card) ?? [card],
            onManageFolders: _manageFolders,
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
