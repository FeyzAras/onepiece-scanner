import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'card_matcher.dart';
import 'card_model.dart';
import 'collection_store.dart';

const Duration kFrameInterval = Duration(milliseconds: 350);
const Duration kSameCardCooldown = Duration(seconds: 5);

/// So oft muss dieselbe Kartennummer gelesen werden, bevor die Karte uebernommen wird.
/// Verhindert, dass ein einzelner Fehlgriff sofort in der Liste landet.
const int kConfirmationsNeeded = 2;

/// Laeuft die Bestaetigung laenger als das, wird neu angefangen.
const Duration kConfirmationWindow = Duration(seconds: 3);

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
        scaffoldBackgroundColor: const Color(0xFF0B0D10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE0383D),
          secondary: Color(0xFFFFB703),
          surface: Color(0xFF15181D),
        ),
      ),
      home: const ScannerPage(),
    );
  }
}

class ScanEntry {
  final OpCard card;
  final String how;
  final DateTime at;
  ScanEntry({required this.card, required this.how, required this.at});

  StoredScan toStored() => StoredScan(cardId: card.id, how: how, at: at);
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  CardMatcher? _matcher;
  final List<ScanEntry> _collection = [];

  bool _busy = false;
  bool _scanning = true;
  bool _cardsLoaded = false;
  String? _fatalError;
  String? _flash;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _flashTimer;

  // Mehrfachbestaetigung, damit nicht jeder Einzeltreffer sofort uebernommen wird
  String? _pendingId;
  int _pendingCount = 0;
  DateTime _pendingSince = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastAddedId;
  DateTime _lastAdd = DateTime.fromMillisecondsSinceEpoch(0);

  // Hinweis, wenn ein Name lesbar war, die Nummer aber nicht
  String? _hint;
  DateTime _hintAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Diagnose (Kopfzeile lange druecken)
  bool _showDiag = false;
  int _framesSeen = 0;
  int _framesAnalyzed = 0;
  int _framesFailed = 0;
  String _imageInfo = '-';
  String _lastOcr = '';
  String? _lastError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      await _loadCards();
      await _restoreCollection();
      await _initCamera();
    } catch (e) {
      if (mounted) setState(() => _fatalError = e.toString());
    }
  }

  Future<void> _loadCards() async {
    final raw = await rootBundle.loadString('assets/cards.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(OpCard.fromJson).toList();
    if (!mounted) return;
    setState(() {
      _matcher = CardMatcher(list);
      _cardsLoaded = true;
    });
  }

  Future<void> _restoreCollection() async {
    final stored = await CollectionStore.load();
    final matcher = _matcher;
    if (matcher == null || !mounted) return;
    final restored = <ScanEntry>[];
    for (final s in stored) {
      final card = matcher.byId(s.cardId);
      if (card != null) restored.add(ScanEntry(card: card, how: s.how, at: s.at));
    }
    setState(() {
      _collection
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _persist() => CollectionStore.save(_collection.map((e) => e.toStored()).toList());

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('Keine Kamera gefunden');
    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      _camera!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    await controller.startImageStream(_onFrame);
    setState(() => _controller = controller);
  }

  void _onFrame(CameraImage image) {
    _framesSeen++;
    if (!_scanning || _busy || _matcher == null) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame) < kFrameInterval) return;
    _lastFrame = now;
    _busy = true;
    _analyze(image).whenComplete(() => _busy = false);
  }

  Future<void> _analyze(CameraImage image) async {
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final recognized = await _recognizer.processImage(input);
      _framesAnalyzed++;
      final text = recognized.text;
      _lastOcr = text.replaceAll('\n', ' ⏎ ');
      _lastError = null;
      if (_showDiag && mounted) setState(() {});
      if (text.trim().isEmpty) return;

      final outcome = _matcher!.match(text);
      if (outcome.hasMatch) {
        _handleCandidate(outcome.match!);
      } else {
        _handleNoNumber(outcome.nameOnlyHint);
      }
    } catch (e) {
      _framesFailed++;
      _lastError = e.toString();
      if (_showDiag && mounted) setState(() {});
    }
  }

  /// Eine Kartennummer wurde gelesen. Uebernommen wird erst, wenn dieselbe Nummer
  /// mehrfach bestaetigt wurde.
  void _handleCandidate(MatchResult result) {
    final now = DateTime.now();
    final id = result.card.id;

    if (id == _lastAddedId && now.difference(_lastAdd) < kSameCardCooldown) return;

    if (_pendingId != id || now.difference(_pendingSince) > kConfirmationWindow) {
      _pendingId = id;
      _pendingCount = 1;
      _pendingSince = now;
    } else {
      _pendingCount++;
    }

    if (_pendingCount >= kConfirmationsNeeded) {
      _add(result, now);
      _pendingId = null;
      _pendingCount = 0;
    } else if (mounted) {
      setState(() {}); // Fortschrittsanzeige aktualisieren
    }
  }

  void _handleNoNumber(String? nameHint) {
    if (nameHint == null) return;
    final now = DateTime.now();
    if (now.difference(_hintAt) < const Duration(seconds: 2)) return;
    _hintAt = now;
    if (mounted) setState(() => _hint = nameHint);
    Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _add(MatchResult result, DateTime now) {
    _lastAddedId = result.card.id;
    _lastAdd = now;
    if (!mounted) return;
    setState(() {
      _collection.insert(0, ScanEntry(card: result.card, how: result.how, at: now));
      _flash = '${result.card.name} · ${result.card.id}';
      _hint = null;
    });
    HapticFeedback.mediumImpact();
    _persist();
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) {
      _lastError = 'Unbekannte Sensordrehung: ${camera.sensorOrientation}';
      return null;
    }

    final rawFormat = image.format.raw;
    final detected = InputImageFormatValue.fromRawValue(rawFormat is int ? rawFormat : -1);
    _imageInfo = '${image.width}x${image.height} · fmt=$rawFormat'
        '${detected != null ? ' (${detected.name})' : ''} · rot=${camera.sensorOrientation}°'
        ' · ${image.planes.length} Ebene(n)';

    Uint8List bytes;
    int bytesPerRow;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
      bytesPerRow = image.planes.first.bytesPerRow;
    } else if (image.planes.length == 3) {
      bytes = _yuv420ToNv21(image);
      bytesPerRow = image.width;
    } else {
      _lastError = 'Unerwartetes Bildformat: $rawFormat mit ${image.planes.length} Ebenen';
      return null;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final ySize = width * height;
    final out = Uint8List(ySize + ySize ~/ 2);

    final yPlane = image.planes[0];
    var offset = 0;
    for (var row = 0; row < height; row++) {
      final start = row * yPlane.bytesPerRow;
      out.setRange(offset, offset + width, yPlane.bytes, start);
      offset += width;
    }

    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final index = row * uvRowStride + col * uvPixelStride;
        out[offset++] = vPlane.bytes[index];
        out[offset++] = uPlane.bytes[index];
      }
    }
    return out;
  }

  void _toggleScanning() => setState(() => _scanning = !_scanning);

  void _remove(ScanEntry entry) {
    setState(() => _collection.remove(entry));
    _persist();
  }

  Future<void> _clearList() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sammlung leeren?'),
        content: Text('${_collection.length} Karte(n) werden dauerhaft entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leeren')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _collection.clear());
      _persist();
    }
  }

  Map<String, List<ScanEntry>> get _byGame {
    final map = <String, List<ScanEntry>>{};
    for (final entry in _collection) {
      map.putIfAbsent(entry.card.game, () => []).add(entry);
    }
    return map;
  }

  double _sum(List<ScanEntry> entries) =>
      entries.fold(0.0, (sum, e) => sum + (e.card.price?.amount ?? 0));

  double get _total => _sum(_collection);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraLayer(),
          const _GuideOverlay(),
          _buildTopBar(),
          if (_flash != null) _buildFlash() else if (_hint != null) _buildHint(),
          if (_showDiag) _buildDiagnostics(),
          _buildBottomControls(),
          _buildSheet(),
        ],
      ),
    );
  }

  Widget _buildCameraLayer() {
    if (_fatalError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 48, color: Color(0xFF9AA1AC)),
              const SizedBox(height: 14),
              const Text('Kamera konnte nicht gestartet werden',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_fatalError!, style: const TextStyle(color: Color(0xFF9AA1AC)), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  setState(() => _fatalError = null);
                  _init();
                },
                child: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()));
    }

    final preview = controller.value.previewSize!;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: preview.height,
        height: preview.width,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onLongPress: () => setState(() => _showDiag = !_showDiag),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 18, right: 16, bottom: 26),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xA6000000), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE0383D), shape: BoxShape.circle)),
              const SizedBox(width: 9),
              const Text('One Piece Scanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              if (!_cardsLoaded)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text('${_matcher?.cards.length ?? 0} Karten',
                    style: const TextStyle(color: Color(0xFF9AA1AC), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlash() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 62,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF3DDC84), borderRadius: BorderRadius.circular(30)),
          child: Text('✓ $_flash',
              style: const TextStyle(color: Color(0xFF06240F), fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  /// Hinweis, wenn ein Kartenname lesbar war, die Nummer aber nicht - dann wird bewusst
  /// nichts uebernommen, aber der Nutzer soll wissen, woran es liegt.
  Widget _buildHint() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 62,
      left: 24,
      right: 24,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFFFB703), width: 1),
          ),
          child: Text('„$_hint" erkannt – Kartennummer unten rechts ins Bild halten',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFFFFB703))),
        ),
      ),
    );
  }

  Widget _buildDiagnostics() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3A3F47)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 11, color: Color(0xFFD7DBE0), height: 1.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DIAGNOSE  (lange auf die Kopfzeile tippen zum Ausblenden)',
                  style: TextStyle(fontSize: 10, color: Color(0xFFFFB703), fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Bilder von der Kamera: $_framesSeen'),
              Text('ausgewertet: $_framesAnalyzed · fehlgeschlagen: $_framesFailed'),
              Text('Bild: $_imageInfo'),
              Text('Bestätigung: ${_pendingId ?? '-'} ($_pendingCount von $kConfirmationsNeeded)'),
              const SizedBox(height: 4),
              Text('Gelesener Text: ${_lastOcr.isEmpty ? '(noch keiner)' : _lastOcr}',
                  maxLines: 4, overflow: TextOverflow.ellipsis),
              if (_lastError != null) ...[
                const SizedBox(height: 4),
                Text('Fehler: $_lastError',
                    maxLines: 8, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFFF8A8A))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final confirming = _pendingId != null && _pendingCount > 0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 196,
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    !_scanning
                        ? Icons.pause_circle_outline
                        : confirming
                            ? Icons.hourglass_top
                            : Icons.sensors,
                    size: 16,
                    color: _scanning ? const Color(0xFFFFB703) : const Color(0xFF9AA1AC),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    !_scanning
                        ? 'Pausiert'
                        : confirming
                            ? 'Prüfe $_pendingId …'
                            : 'Scannt automatisch',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _toggleScanning,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 4),
                ),
                child: Icon(_scanning ? Icons.pause : Icons.play_arrow, color: const Color(0xFFE0383D), size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet() {
    final groups = _byGame;
    return DraggableScrollableSheet(
      initialChildSize: 0.22,
      minChildSize: 0.22,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF15181D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -6))],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFF3A3F47), borderRadius: BorderRadius.circular(3))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Row(
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${_collection.length}',
                          style: const TextStyle(color: Color(0xFFFFB703), fontWeight: FontWeight.bold, fontSize: 16)),
                      const TextSpan(text: ' Karten', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ])),
                    const Spacer(),
                    Text('${_total.toStringAsFixed(2)} €',
                        style: const TextStyle(color: Color(0xFFFFB703), fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              _buildThumbStrip(),
              if (_collection.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 6, 24, 24),
                  child: Text(
                    'Halte eine Karte so in den Rahmen, dass die Kartennummer\nunten rechts (z. B. OP07-055) gut lesbar ist.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9AA1AC), fontSize: 12.5, height: 1.5),
                  ),
                )
              else ...[
                for (final game in groups.keys) ...[
                  _buildGameHeader(game, groups[game]!),
                  for (final entry in groups[game]!) _buildRow(entry),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  child: TextButton(
                    onPressed: _clearList,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2F38),
                      foregroundColor: const Color(0xFF9AA1AC),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('Sammlung leeren'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Streifen mit Miniaturbildern der zuletzt gescannten Karten - sichtbar,
  /// ohne die Liste aufklappen zu muessen.
  Widget _buildThumbStrip() {
    if (_collection.isEmpty) {
      return const SizedBox(height: 74);
    }
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _collection.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final entry = _collection[i];
          return GestureDetector(
            onTap: () => _showCardDetails(entry),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _cardImage(entry.card, width: 44),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: 48,
                  child: Text(
                    entry.card.price == null ? '–' : '${entry.card.price!.amount.toStringAsFixed(2)} €',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: Color(0xFFFFB703), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cardImage(OpCard card, {required double width}) {
    final height = width * 88 / 63;
    if (card.img == null) {
      return Container(width: width, height: height, color: const Color(0xFF2B313A));
    }
    return CachedNetworkImage(
      imageUrl: card.img!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(width: width, height: height, color: const Color(0xFF2B313A)),
      errorWidget: (context, url, error) =>
          Container(width: width, height: height, color: const Color(0xFF2B313A)),
    );
  }

  void _showCardDetails(ScanEntry entry) {
    final price = entry.card.price;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF15181D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: _cardImage(entry.card, width: 110)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.card.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 4),
                      Text('${entry.card.id} · ${entry.card.rarity} · ${entry.card.cardType}',
                          style: const TextStyle(color: Color(0xFF9AA1AC), fontSize: 12.5)),
                      const SizedBox(height: 10),
                      Text(price == null ? 'kein Preis hinterlegt' : '${price.amount.toStringAsFixed(2)} €',
                          style: const TextStyle(color: Color(0xFFFFB703), fontWeight: FontWeight.bold, fontSize: 20)),
                      if (price != null)
                        Text('Cardmarket ${price.basisLabel} · Stand ${price.asOf}',
                            style: const TextStyle(color: Color(0xFF9AA1AC), fontSize: 11)),
                      const SizedBox(height: 10),
                      Text(
                        entry.how == 'number+name'
                            ? 'Erkannt über Kartennummer und Name'
                            : 'Erkannt über Kartennummer',
                        style: const TextStyle(color: Color(0xFF3DDC84), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (entry.card.effect.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(entry.card.effect,
                    style: const TextStyle(color: Color(0xFFD7DBE0), fontSize: 12, height: 1.45)),
              ),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _remove(entry);
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF8A8A),
                minimumSize: const Size.fromHeight(44),
                backgroundColor: const Color(0xFF2A2F38),
              ),
              label: const Text('Aus der Sammlung entfernen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameHeader(String game, List<ScanEntry> entries) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 17, color: Color(0xFFFFB703)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(game,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          ),
          Text('${entries.length} · ${_sum(entries).toStringAsFixed(2)} €',
              style: const TextStyle(color: Color(0xFF9AA1AC), fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _buildRow(ScanEntry entry) {
    final price = entry.card.price;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: InkWell(
        onTap: () => _showCardDetails(entry),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF1D2128), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(7), child: _cardImage(entry.card, width: 48)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.card.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text('${entry.card.id} · ${entry.card.rarity}',
                        style: const TextStyle(color: Color(0xFF9AA1AC), fontSize: 12)),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14361F),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        entry.how == 'number+name' ? 'Nummer + Name' : 'Nummer',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF3DDC84)),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price == null ? '–' : '${price.amount.toStringAsFixed(2)} €',
                      style: const TextStyle(color: Color(0xFFFFB703), fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(price == null ? 'kein Preis' : 'Cardmarket ${price.basisLabel}',
                      style: const TextStyle(color: Color(0xFF9AA1AC), fontSize: 9)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _GuidePainter()));
  }
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = size.width * 0.68;
    final frameHeight = frameWidth * (88 / 63); // Kartenformat 63x88 mm
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2 - size.height * 0.1;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, frameWidth, frameHeight),
      const Radius.circular(14),
    );

    final overlay = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(rect),
    );
    canvas.drawPath(overlay, Paint()..color = const Color(0x8C000000));

    final corner = Paint()
      ..color = const Color(0xFFFFB703)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 28.0;
    final r = rect.outerRect;
    canvas.drawLine(Offset(r.left, r.top + len), Offset(r.left, r.top), corner);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + len, r.top), corner);
    canvas.drawLine(Offset(r.right - len, r.top), Offset(r.right, r.top), corner);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + len), corner);
    canvas.drawLine(Offset(r.left, r.bottom - len), Offset(r.left, r.bottom), corner);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + len, r.bottom), corner);
    canvas.drawLine(Offset(r.right - len, r.bottom), Offset(r.right, r.bottom), corner);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - len), corner);

    // Markierung, wo die Kartennummer sitzt - dort muss es scharf sein
    final hintRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.right - frameWidth * 0.42, r.bottom - frameHeight * 0.085, frameWidth * 0.36, frameHeight * 0.055),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      hintRect,
      Paint()
        ..color = const Color(0x66FFB703)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
