import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_installer.dart';
import 'update_service.dart';
import 'widgets.dart';

/// Ordner fuer heruntergeladene Updates.
Future<Directory> updateOrdner() async {
  final tmp = await getTemporaryDirectory();
  return Directory('${tmp.path}${Platform.pathSeparator}updates');
}

/// Schmaler Hinweis ueber der Navigationsleiste, wenn eine neue Version da ist.
///
/// Bewusst als schwebende Karte unten und nicht oben: Oben saessen Kamerabild und
/// Sammlungskopf, deren Hoehe die Ansichten selbst berechnen.
class UpdateBanner extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onAnsehen;
  final VoidCallback onSchliessen;

  const UpdateBanner({
    super.key,
    required this.info,
    required this.onAnsehen,
    required this.onSchliessen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kRow,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onAnsehen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x66FFB703)),
          ),
          child: Row(
            children: [
              const Icon(Icons.system_update, color: kGold, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Version ${info.version} ist da',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    const Text('Antippen zum Aktualisieren — die Sammlung bleibt erhalten',
                        style: TextStyle(fontSize: 11, color: kDim)),
                  ],
                ),
              ),
              IconButton(
                onPressed: onSchliessen,
                tooltip: 'Später',
                icon: const Icon(Icons.close, size: 18, color: kDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Oeffnet das Update-Blatt.
///
/// [vorInstallation] wird aufgerufen, bevor Android die APK bekommt - dort muss die
/// Sammlung sicher gespeichert werden. [sicherungAnbieten] oeffnet die Sicherung,
/// falls Android das Update ablehnt.
Future<void> showUpdateSheet(
  BuildContext context, {
  required UpdateInfo info,
  required String installierteVersion,
  required Future<void> Function() vorInstallation,
  required Future<void> Function() sicherungAnbieten,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    isDismissible: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _UpdateSheet(
      info: info,
      installierteVersion: installierteVersion,
      vorInstallation: vorInstallation,
      sicherungAnbieten: sicherungAnbieten,
    ),
  );
}

enum _Phase { angebot, berechtigung, download, installation, fehler }

class _UpdateSheet extends StatefulWidget {
  final UpdateInfo info;
  final String installierteVersion;
  final Future<void> Function() vorInstallation;
  final Future<void> Function() sicherungAnbieten;

  const _UpdateSheet({
    required this.info,
    required this.installierteVersion,
    required this.vorInstallation,
    required this.sicherungAnbieten,
  });

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  _Phase _phase = _Phase.angebot;
  int _empfangen = 0;
  int? _gesamt;
  String? _fehler;
  File? _apk;
  DownloadAbbruch? _abbruch;

  StreamSubscription<InstallStatus>? _statusAbo;
  AppLifecycleListener? _lebenszyklus;

  @override
  void initState() {
    super.initState();
    _statusAbo = AppInstaller.status.listen(_aufStatus);
    // Rueckkehr aus den Android-Einstellungen: Die Einstellungsseite meldet nichts
    // zurueck, deshalb beim Wiedererscheinen der App selbst nachsehen.
    _lebenszyklus = AppLifecycleListener(onResume: () {
      if (_phase == _Phase.berechtigung) _starten();
    });
  }

  @override
  void dispose() {
    _statusAbo?.cancel();
    _lebenszyklus?.dispose();
    _abbruch?.abbrechen();
    super.dispose();
  }

  // ------------------------------------------------------------------ Ablauf

  Future<void> _starten() async {
    if (!await AppInstaller.darfInstallieren()) {
      if (mounted) setState(() => _phase = _Phase.berechtigung);
      return;
    }

    // Schon heruntergeladen (z.B. nach "Abbrechen" im Android-Dialog)? Dann direkt weiter.
    final vorhanden = _apk;
    if (vorhanden != null && await vorhanden.exists()) {
      await _installieren(vorhanden);
      return;
    }

    final abbruch = DownloadAbbruch();
    setState(() {
      _phase = _Phase.download;
      _empfangen = 0;
      _gesamt = widget.info.bytes;
      _abbruch = abbruch;
      _fehler = null;
    });

    try {
      final ordner = await updateOrdner();
      final apk = await UpdateService.herunterladen(
        widget.info,
        ziel: ordner,
        abbruch: abbruch,
        fortschritt: (empfangen, gesamt) {
          if (mounted) {
            setState(() {
              _empfangen = empfangen;
              _gesamt = gesamt;
            });
          }
        },
      );
      _apk = apk;
      await _installieren(apk);
    } on UpdateAbgebrochen {
      if (mounted) setState(() => _phase = _Phase.angebot);
    } on UpdateException catch (e) {
      _zeigeFehler(e.meldung);
    } catch (e) {
      _zeigeFehler('Unerwarteter Fehler: $e');
    }
  }

  Future<void> _installieren(File apk) async {
    if (!mounted) return;
    setState(() => _phase = _Phase.installation);
    try {
      // Erst die Sammlung sicher auf den Speicher bringen. Waehrend der Installation
      // beendet Android die App - ein noch laufender Speichervorgang ginge verloren.
      await widget.vorInstallation();
      await AppInstaller.installieren(apk.path);
    } on PlatformException catch (e) {
      _zeigeFehler('Android hat die Installation nicht angenommen: ${e.message ?? e.code}');
    } catch (e) {
      _zeigeFehler('Installation konnte nicht starten: $e');
    }
  }

  void _aufStatus(InstallStatus s) {
    if (!mounted) return;
    if (s.wartetAufNutzer || s.erfolgreich) return; // Android zeigt seinen Dialog bzw. startet neu

    if (s.abgebrochen) {
      setState(() => _phase = _Phase.angebot);
      return;
    }

    if (s.istKonflikt) {
      Navigator.of(context).pop();
      showKonfliktDialog(context, technisch: s.message, sicherungAnbieten: widget.sicherungAnbieten);
      return;
    }

    _zeigeFehler(switch (s.code) {
      InstallStatus.incompatible => 'Diese Fassung passt nicht zu deinem Gerät.',
      InstallStatus.storage => 'Auf dem Gerät ist nicht genug Speicherplatz frei.',
      InstallStatus.blocked => 'Android hat die Installation blockiert.',
      _ => 'Die Installation ist fehlgeschlagen.',
    } + (s.message != null ? '\n\n${s.message}' : ''));
  }

  void _zeigeFehler(String text) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.fehler;
      _fehler = text;
    });
  }

  Future<void> _ueberspringen() async {
    await UpdateService.ueberspringen(widget.info.version);
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------ Aufbau

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).padding.bottom + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.system_update, color: kGold),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Version ${widget.info.version}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Text('installiert: ${widget.installierteVersion}',
                  style: const TextStyle(fontSize: 11.5, color: kDim)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (widget.info.released.isNotEmpty) 'vom ${_datum(widget.info.released)}',
              if (widget.info.groesseText.isNotEmpty) widget.info.groesseText,
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: kDim),
          ),
          const SizedBox(height: 14),
          ...switch (_phase) {
            _Phase.angebot => _angebot(),
            _Phase.berechtigung => _berechtigung(),
            _Phase.download => _download(),
            _Phase.installation => _installation(),
            _Phase.fehler => _fehlerAnsicht(),
          },
        ],
      ),
    );
  }

  List<Widget> _angebot() => [
        if (widget.info.notes.isNotEmpty) ...[
          const Text('Neu in dieser Version', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final n in widget.info.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ', style: TextStyle(color: kGold)),
                          Expanded(child: Text(n, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _hinweis(
          Icons.verified_user_outlined,
          'Deine Sammlung bleibt beim Update erhalten. Die neue Fassung legt sich über die alte.',
          kOk,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _starten,
            icon: const Icon(Icons.download),
            label: const Text('Jetzt aktualisieren'),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Später')),
            const Spacer(),
            if (!widget.info.mandatory)
              TextButton(
                onPressed: _ueberspringen,
                child: const Text('Diese Version überspringen', style: TextStyle(color: kDim)),
              ),
          ],
        ),
      ];

  List<Widget> _berechtigung() => [
        _hinweis(
          Icons.lock_open,
          'Android muss einmalig erlauben, dass diese App Updates installieren darf.\n\n'
          'In den Einstellungen „Aus dieser Quelle zulassen" einschalten und zurückkehren — '
          'danach geht es von selbst weiter. Das ist nur beim ersten Mal nötig.',
          kGold,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: AppInstaller.einstellungenOeffnen,
            icon: const Icon(Icons.settings),
            label: const Text('Einstellungen öffnen'),
          ),
        ),
        TextButton(onPressed: _starten, child: const Text('Schon erlaubt — weiter')),
      ];

  List<Widget> _download() {
    final gesamt = _gesamt;
    final anteil = gesamt != null && gesamt > 0 ? (_empfangen / gesamt).clamp(0.0, 1.0) : null;
    return [
      const Text('Wird heruntergeladen …', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: anteil,
          minHeight: 8,
          color: kGold,
          backgroundColor: kRow,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        gesamt != null ? '${_mb(_empfangen)} von ${_mb(gesamt)}' : _mb(_empfangen),
        style: const TextStyle(fontSize: 11.5, color: kDim),
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => _abbruch?.abbrechen(),
          child: const Text('Abbrechen'),
        ),
      ),
    ];
  }

  List<Widget> _installation() => [
        const Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Android fragt jetzt, ob die App aktualisiert werden soll.\n'
                'Dort „Aktualisieren" bzw. „Installieren" antippen.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _hinweis(
          Icons.info_outline,
          'Die App schließt sich dabei kurz und startet in der neuen Version.',
          kDim,
        ),
      ];

  List<Widget> _fehlerAnsicht() => [
        _hinweis(Icons.error_outline, _fehler ?? 'Unbekannter Fehler', kAccent),
        const SizedBox(height: 10),
        _hinweis(
          Icons.shield_outlined,
          'Nicht deinstallieren — damit wäre deine Sammlung weg. Die bisherige Version läuft weiter.',
          kGold,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            TextButton(
              onPressed: () => AppInstaller.imBrowserOeffnen(widget.info.apkUrl),
              child: const Text('Im Browser laden'),
            ),
            const Spacer(),
            FilledButton(onPressed: _starten, child: const Text('Erneut versuchen')),
          ],
        ),
      ];

  Widget _hinweis(IconData icon, String text, Color farbe) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: farbe.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: farbe.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: farbe),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4))),
          ],
        ),
      );

  static String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';

  static String _datum(String iso) {
    final teile = iso.split('-');
    return teile.length == 3 ? '${teile[2]}.${teile[1]}.${teile[0]}' : iso;
  }
}

/// Android lehnt das Update ab, weil Signatur oder Version nicht passen.
///
/// Der wichtigste Satz hier ist der Warnhinweis: Die naheliegende Reaktion auf
/// "App nicht installiert" waere Deinstallieren - und das loescht die Sammlung.
Future<void> showKonfliktDialog(
  BuildContext context, {
  String? technisch,
  required Future<void> Function() sicherungAnbieten,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      icon: const Icon(Icons.warning_amber_rounded, color: kAccent, size: 34),
      title: const Text('Bitte NICHT deinstallieren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Android lehnt das Update ab: Die neue Fassung passt nicht zur installierten.\n\n'
            'Deinstallieren würde deine Sammlung löschen. Die bisherige Version läuft normal '
            'weiter — sichere zuerst deine Sammlung und melde den Fehler.',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
          if (technisch != null) ...[
            const SizedBox(height: 12),
            Text(technisch, style: const TextStyle(fontSize: 10.5, color: kDim)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Schließen')),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await sicherungAnbieten();
          },
          child: const Text('Sammlung jetzt sichern'),
        ),
      ],
    ),
  );
}
