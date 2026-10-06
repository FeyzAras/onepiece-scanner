import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'card_matcher.dart';
import 'image_hash.dart';
import 'widgets.dart';

const Duration kFrameInterval = Duration(milliseconds: 350);
const Duration kSameCardCooldown = Duration(seconds: 5);

/// So oft muss dieselbe Kartennummer gelesen werden, bevor die Karte uebernommen wird.
const int kConfirmationsNeeded = 2;
const Duration kConfirmationWindow = Duration(seconds: 3);

/// Breite des Sucherrahmens im Verhaeltnis zur Bildschirmbreite, und wie weit er
/// nach oben versetzt ist. Dieselben Werte nutzt der Bildausschnitt fuer den
/// Artwork-Vergleich, damit beide denselben Bereich meinen.
const double kFrameWidthFraction = 0.68;
const double kFrameVerticalShift = -0.10;

class ScannerView extends StatefulWidget {
  final CardMatcher? matcher;
  final String activeFolderName;
  final void Function(MatchResult result) onScanned;
  final VoidCallback onPickFolder;

  const ScannerView({
    super.key,
    required this.matcher,
    required this.activeFolderName,
    required this.onScanned,
    required this.onPickFolder,
  });

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  bool _busy = false;
  bool _scanning = true;
  String? _fatalError;
  String? _flash;
  String? _hint;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _hintAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _flashTimer;

  String? _pendingId;
  int _pendingCount = 0;
  DateTime _pendingSince = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastAddedId;
  DateTime _lastAdd = DateTime.fromMillisecondsSinceEpoch(0);

  // Diagnose: Kopfzeile lange druecken
  bool _showDiag = false;
  int _framesSeen = 0;
  int _framesAnalyzed = 0;
  int _framesFailed = 0;
  String _imageInfo = '-';
  String _lastOcr = '';
  String _artworkInfo = '-';
  String? _lastError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
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
      setState(() {
        _controller = controller;
        _fatalError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _fatalError = e.toString());
    }
  }

  void _onFrame(CameraImage image) {
    _framesSeen++;
    if (!_scanning || _busy || widget.matcher == null) return;
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
      if (text.trim().isEmpty) {
        if (_showDiag && mounted) setState(() {});
        return;
      }

      final cameraHash = _hashOf(image);
      final outcome = widget.matcher!.match(text, cameraHash: cameraHash);
      if (outcome.hasMatch) {
        _handleCandidate(outcome.match!);
      } else {
        _handleNoNumber(outcome.nameOnlyHint);
      }
      if (_showDiag && mounted) setState(() {});
    } catch (e) {
      _framesFailed++;
      _lastError = e.toString();
      if (_showDiag && mounted) setState(() {});
    }
  }

  /// Fingerabdruck des Bildausschnitts im Sucherrahmen - entscheidet bei Karten mit
  /// mehreren Artworks, welche Version gemeint ist.
  String? _hashOf(CameraImage image) {
    final camera = _camera;
    if (camera == null || image.planes.isEmpty) return null;
    final rotation = camera.sensorOrientation;
    final rotated = rotation == 90 || rotation == 270;
    final dispW = rotated ? image.height : image.width;
    final dispH = rotated ? image.width : image.height;
    final hash = ImageHash.fromYPlane(
      yPlane: image.planes.first.bytes,
      rowStride: image.planes.first.bytesPerRow,
      width: image.width,
      height: image.height,
      rotationDegrees: rotation,
      crop: CropRect.cardCentered(
        displayAspect: dispW / dispH,
        widthFraction: kFrameWidthFraction,
        verticalShift: kFrameVerticalShift,
      ),
    );
    _artworkInfo = hash ?? '(kein Fingerabdruck)';
    return hash;
  }

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
      _lastAddedId = id;
      _lastAdd = now;
      _pendingId = null;
      _pendingCount = 0;
      widget.onScanned(result);
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _flash = '${result.card.name} · ${result.card.id}';
          _hint = null;
        });
      }
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 1700), () {
        if (mounted) setState(() => _flash = null);
      });
    } else if (mounted) {
      setState(() {});
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
      out.setRange(offset, offset + width, yPlane.bytes, row * yPlane.bytesPerRow);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && controller == null) {
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
    return Stack(
      fit: StackFit.expand,
      children: [
        _cameraLayer(),
        const _GuideOverlay(),
        _topBar(),
        if (_flash != null) _flashPill() else if (_hint != null) _hintPill(),
        if (_showDiag) _diagnostics(),
        _controls(),
      ],
    );
  }

  Widget _cameraLayer() {
    if (_fatalError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 48, color: kDim),
              const SizedBox(height: 14),
              const Text('Kamera konnte nicht gestartet werden',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_fatalError!, style: const TextStyle(color: kDim), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: _initCamera, child: const Text('Erneut versuchen')),
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

  Widget _topBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onLongPress: () => setState(() => _showDiag = !_showDiag),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 14, right: 14, bottom: 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xA6000000), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onPickFolder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kGold.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_outlined, size: 16, color: kGold),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text('Scannt in: ${widget.activeFolderName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 16, color: kDim),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flashPill() => Positioned(
        top: MediaQuery.of(context).padding.top + 64,
        left: 16,
        right: 16,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(color: kOk, borderRadius: BorderRadius.circular(30)),
            child: Text('✓ $_flash',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF06240F), fontWeight: FontWeight.bold)),
          ),
        ),
      );

  Widget _hintPill() => Positioned(
        top: MediaQuery.of(context).padding.top + 64,
        left: 24,
        right: 24,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: kGold, width: 1),
            ),
            child: Text('„$_hint" erkannt – Kartennummer unten rechts ins Bild halten',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: kGold)),
          ),
        ),
      );

  Widget _diagnostics() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 64,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3A3F47)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 11, color: Color(0xFFD7DBE0), height: 1.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DIAGNOSE  (lange auf die Kopfzeile tippen zum Ausblenden)',
                  style: TextStyle(fontSize: 10, color: kGold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Bilder: $_framesSeen · ausgewertet: $_framesAnalyzed · Fehler: $_framesFailed'),
              Text('Bild: $_imageInfo'),
              Text('Bestätigung: ${_pendingId ?? '-'} ($_pendingCount von $kConfirmationsNeeded)'),
              Text('Bild-Fingerabdruck: $_artworkInfo'),
              const SizedBox(height: 4),
              Text('Gelesener Text: ${_lastOcr.isEmpty ? '(noch keiner)' : _lastOcr}',
                  maxLines: 4, overflow: TextOverflow.ellipsis),
              if (_lastError != null) ...[
                const SizedBox(height: 4),
                Text('Fehler: $_lastError',
                    maxLines: 6, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFFF8A8A))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final confirming = _pendingId != null && _pendingCount > 0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 26,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    !_scanning ? Icons.pause_circle_outline : (confirming ? Icons.hourglass_top : Icons.sensors),
                    size: 16,
                    color: _scanning ? kGold : kDim,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    !_scanning ? 'Pausiert' : (confirming ? 'Prüfe $_pendingId …' : 'Scannt automatisch'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _scanning = !_scanning),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 4),
                ),
                child: Icon(_scanning ? Icons.pause : Icons.play_arrow, color: kAccent, size: 28),
              ),
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
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _GuidePainter()));
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = size.width * kFrameWidthFraction;
    final frameHeight = frameWidth * (88 / 63);
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2 + size.height * kFrameVerticalShift;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, frameWidth, frameHeight),
      const Radius.circular(14),
    );

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(rect),
      ),
      Paint()..color = const Color(0x8C000000),
    );

    final corner = Paint()
      ..color = kGold
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

    // Wo die Kartennummer sitzt - dort muss es scharf sein
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.right - frameWidth * 0.42, r.bottom - frameHeight * 0.085,
            frameWidth * 0.36, frameHeight * 0.055),
        const Radius.circular(4),
      ),
      Paint()
        ..color = const Color(0x66FFB703)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
