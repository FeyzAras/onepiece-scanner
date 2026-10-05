import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'card_matcher.dart';
import 'card_model.dart';

const Duration kFrameInterval = Duration(milliseconds: 450);
const Duration kSameCardCooldown = Duration(seconds: 4);

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
  final List<ScanEntry> _session = [];

  bool _busy = false;
  bool _scanning = true;
  bool _cardsLoaded = false;
  String? _fatalError;
  String? _flash;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastId;
  DateTime _lastAdd = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _flashTimer;

  // --- Diagnose: sichtbar ueber langen Druck auf die Kopfzeile ---
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
      if (_showDiag && mounted) {
        setState(() {
          _lastOcr = text.replaceAll('\n', ' ⏎ ');
          _lastError = null;
        });
      } else {
        _lastOcr = text.replaceAll('\n', ' ⏎ ');
      }
      if (text.trim().isEmpty) return;
      final result = _matcher!.match(text);
      if (result != null) _maybeAdd(result);
    } catch (e) {
      _framesFailed++;
      _lastError = e.toString();
      if (_showDiag && mounted) setState(() {});
    }
  }

  /// Baut aus einem Kamerabild das Eingabebild fuer ML Kit.
  /// ML Kit erwartet auf Android NV21. Die Kamera liefert das je nach Geraet direkt
  /// (eine Ebene) oder als YUV_420_888 (drei Ebenen) - letzteres wird hier umgewandelt.
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

  void _maybeAdd(MatchResult result) {
    final now = DateTime.now();
    if (result.card.id == _lastId && now.difference(_lastAdd) < kSameCardCooldown) return;
    _lastId = result.card.id;
    _lastAdd = now;
    if (!mounted) return;
    setState(() {
      _session.insert(0, ScanEntry(card: result.card, how: result.how, at: now));
      _flash = result.card.name;
    });
    HapticFeedback.mediumImpact();
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _toggleScanning() => setState(() => _scanning = !_scanning);

  void _remove(ScanEntry entry) => setState(() => _session.remove(entry));

  Future<void> _clearList() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liste leeren?'),
        content: Text('${_session.length} Karte(n) werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leeren')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _session.clear());
  }

  /// Gescannte Karten nach Sammelkartenspiel gruppiert - aktuell nur One Piece,
  /// aber vorbereitet fuer weitere Spiele.
  Map<String, List<ScanEntry>> get _byGame {
    final map = <String, List<ScanEntry>>{};
    for (final entry in _session) {
      map.putIfAbsent(entry.card.game, () => []).add(entry);
    }
    return map;
  }

  double _sum(List<ScanEntry> entries) =>
      entries.fold(0.0, (sum, e) => sum + (e.card.price?.amount ?? 0));

  double get _total => _sum(_session);

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
          if (_flash != null) _buildFlash(),
          if (_showDiag) _buildDiagnostics(),
          _buildBottomControls(),
          _buildSessionSheet(),
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
          child: Text('✓ $_flash', style: const TextStyle(color: Color(0xFF06240F), fontWeight: FontWeight.bold)),
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
              Text('davon ausgewertet: $_framesAnalyzed · fehlgeschlagen: $_framesFailed'),
              Text('Bild: $_imageInfo'),
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
    return Positioned(
      left: 0,
      right: 0,
      bottom: 150,
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_scanning ? Icons.sensors : Icons.pause_circle_outline,
                      size: 16, color: _scanning ? const Color(0xFFFFB703) : const Color(0xFF9AA1AC)),
                  const SizedBox(width: 7),
                  Text(_scanning ? 'Scannt automatisch' : 'Pausiert', style: const TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _toggleScanning,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 5),
                ),
                child: Icon(_scanning ? Icons.pause : Icons.play_arrow, color: const Color(0xFFE0383D), size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSheet() {
    final groups = _byGame;
    return DraggableScrollableSheet(
      initialChildSize: 0.13,
      minChildSize: 0.13,
      maxChildSize: 0.82,
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${_session.length}',
                          style: const TextStyle(color: Color(0xFFFFB703), fontWeight: FontWeight.bold, fontSize: 16)),
                      const TextSpan(text: ' Karten gescannt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ])),
                    const Spacer(),
                    Text('Gesamt: ${_total.toStringAsFixed(2)} €',
                        style: const TextStyle(color: Color(0xFFFFB703), fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (_session.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 14, 24, 30),
                  child: Text(
                    'Noch keine Karte erkannt.\nHalte eine Karte in den Rahmen – sie wird automatisch erfasst.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9AA1AC), fontSize: 13.5, height: 1.5),
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
                    child: const Text('Liste leeren'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF1D2128), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: entry.card.img == null
                  ? const SizedBox(width: 48, height: 67)
                  : Image.network(
                      entry.card.img!,
                      width: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const SizedBox(width: 48, height: 67),
                    ),
            ),
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
                      color: entry.how == 'number' ? const Color(0xFF14361F) : const Color(0xFF2A2F38),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      entry.how == 'number' ? 'über Kartennummer' : 'über Name',
                      style: TextStyle(
                        fontSize: 10,
                        color: entry.how == 'number' ? const Color(0xFF3DDC84) : const Color(0xFF9AA1AC),
                      ),
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
            IconButton(
              onPressed: () => _remove(entry),
              icon: const Icon(Icons.close, size: 18, color: Color(0xFF9AA1AC)),
            ),
          ],
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
    final frameWidth = size.width * 0.72;
    final frameHeight = frameWidth * (88 / 63); // Kartenformat 63x88 mm
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2 - size.height * 0.06;
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
