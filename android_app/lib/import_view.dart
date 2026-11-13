import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_matcher.dart';
import 'card_model.dart';
import 'collection_import.dart';
import 'collection_store.dart';
import 'csv_reader.dart';
import 'widgets.dart';

/// Wohin die eingelesenen Karten sollen.
enum ImportZiel {
  aktiverOrdner,
  neuerOrdner,

  /// Ordner aus der Datei uebernehmen - nur bei eigener CSV oder Sicherung.
  ausDatei,
}

/// Was der Nutzer in der Vorschau entschieden hat.
class ImportPlan {
  final ImportResult result;
  final ImportMode modus;
  final ImportZiel ziel;

  /// Bei [ImportZiel.aktiverOrdner]: der gewaehlte vorhandene Ordner.
  final String? ordnerId;

  /// Bei [ImportZiel.neuerOrdner]: der Name des anzulegenden Ordners.
  final String? neuerName;

  const ImportPlan({
    required this.result,
    required this.modus,
    required this.ziel,
    this.ordnerId,
    this.neuerName,
  });
}

/// Oeffnet das Import-Blatt und gibt zurueck, was uebernommen werden soll.
///
/// Gibt null zurueck, wenn abgebrochen wurde. Es wird hier **nichts** gespeichert -
/// das Schreiben bleibt bewusst beim Aufrufer, der den Bestand besitzt.
Future<ImportPlan?> showImportSheet(
  BuildContext context, {
  required CardMatcher matcher,
  required List<ScanFolder> folders,
  required String activeFolderId,
  required double Function(OpCard card) priceOf,
  DateTime? sicherungVom,
  required Future<void> Function() onRueckgaengig,
}) {
  return showModalBottomSheet<ImportPlan>(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ImportSheet(
      matcher: matcher,
      folders: folders,
      activeFolderId: activeFolderId,
      priceOf: priceOf,
      sicherungVom: sicherungVom,
      onRueckgaengig: onRueckgaengig,
    ),
  );
}

class _ImportSheet extends StatefulWidget {
  final CardMatcher matcher;
  final List<ScanFolder> folders;
  final String activeFolderId;
  final double Function(OpCard card) priceOf;
  final DateTime? sicherungVom;
  final Future<void> Function() onRueckgaengig;

  const _ImportSheet({
    required this.matcher,
    required this.folders,
    required this.activeFolderId,
    required this.priceOf,
    required this.sicherungVom,
    required this.onRueckgaengig,
  });

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _ordnerName = TextEditingController();

  ImportResult? _ergebnis;
  String? _quelle; // Dateiname, nur zur Anzeige
  bool _laeuft = false;
  String? _fehler;

  ImportMode _modus = ImportMode.dazu;
  ImportZiel _ziel = ImportZiel.aktiverOrdner;
  late String _ordnerId = widget.activeFolderId;

  bool _fehlerAufgeklappt = false;
  bool _korrekturenAufgeklappt = false;

  @override
  void dispose() {
    _text.dispose();
    _ordnerName.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ Einlesen

  Future<void> _ausDatei() async {
    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    try {
      // Bewusst ohne Typfilter: Android graut Dateien aus, deren Typ nicht im
      // Filter steht - und genau die aus Chrome oder WhatsApp kommen oft als
      // "application/octet-stream" an. Geprueft wird stattdessen der Inhalt.
      final datei = await openFile();
      if (datei == null) {
        setState(() => _laeuft = false);
        return;
      }
      final bytes = await datei.readAsBytes();
      _auswerten(CsvReader.decodeBytes(bytes), quelle: datei.name);
    } catch (e) {
      setState(() {
        _laeuft = false;
        _fehler = 'Die Datei ließ sich nicht öffnen: $e';
      });
    }
  }

  Future<void> _ausZwischenablage() async {
    final daten = await Clipboard.getData(Clipboard.kTextPlain);
    final text = daten?.text ?? '';
    if (text.trim().isEmpty) {
      setState(() => _fehler = 'In der Zwischenablage steht kein Text.');
      return;
    }
    _text.text = text;
    _auswerten(text, quelle: 'Zwischenablage');
  }

  void _ausTextfeld() => _auswerten(_text.text, quelle: 'eingefügter Text');

  void _auswerten(String text, {required String quelle, ImportFormat? alsFormat}) {
    final ergebnis = CollectionImport.read(text, matcher: widget.matcher, alsFormat: alsFormat);
    setState(() {
      _laeuft = false;
      _fehler = null;
      _ergebnis = ergebnis;
      _quelle = quelle;
      _text.text = text;

      // Eine vollstaendige Sicherung will man wiederherstellen, keine Liste anhaengen
      if (ergebnis.format == ImportFormat.sicherung) {
        _modus = ImportMode.ersetzen;
        _ziel = ImportZiel.ausDatei;
      } else if (_ordnerInDatei(ergebnis)) {
        _ziel = ImportZiel.ausDatei;
      } else {
        _ziel = ImportZiel.aktiverOrdner;
      }
    });
  }

  bool _ordnerInDatei(ImportResult r) =>
      r.treffer.any((z) => z.ordnerName != null || z.ordnerId != null);

  // -------------------------------------------------------------------- Aufbau

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
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
            const Text('Liste einlesen',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Sicherungsdatei, eigener CSV-Export, Deckliste oder einfach eine '
              'Nummer je Zeile — das Format wird selbst erkannt.',
              style: TextStyle(fontSize: 12, color: kDim, height: 1.35),
            ),
            const SizedBox(height: 14),
            if (_ergebnis == null) ..._quelleWaehlen() else ..._vorschau(_ergebnis!),
            if (_fehler != null) ...[
              const SizedBox(height: 12),
              _hinweisKasten(_fehler!, const Color(0x33FF5252), const Color(0x66FF5252)),
            ],
            if (widget.sicherungVom != null) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: kChip),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.history, size: 16, color: kDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stand vor dem letzten Import: ${_zeit(widget.sicherungVom!)}',
                      style: const TextStyle(fontSize: 11.5, color: kDim),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await widget.onRueckgaengig();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Rückgängig', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _quelleWaehlen() => [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _laeuft ? null : _ausDatei,
                icon: _laeuft
                    ? const SizedBox(
                        width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.folder_open, size: 18),
                label: const Text('Datei auswählen'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _laeuft ? null : _ausZwischenablage,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Einfügen'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          minLines: 5,
          maxLines: 8,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: '4xOP01-001\n2xST01-002\nOP09-004\n…',
            hintStyle: TextStyle(fontSize: 13, color: kDim),
            filled: true,
            fillColor: kRow,
            border: OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _text.text.trim().isEmpty ? null : _ausTextfeld,
            child: const Text('Text einlesen'),
          ),
        ),
      ];

  List<Widget> _vorschau(ImportResult r) {
    final wert = r.treffer.fold<double>(
        0, (s, z) => s + widget.priceOf(z.card!) * z.anzahl);

    return [
      // --- Kopf: erkanntes Format, umschaltbar ---
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: kRow, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.format.label}${r.sicher ? '' : ' (vermutet)'}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                DropdownButton<ImportFormat>(
                  value: r.format,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: kRow,
                  style: const TextStyle(fontSize: 12, color: kDim),
                  items: ImportFormat.values
                      .where((f) => f != ImportFormat.unbekannt)
                      .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                      .toList(),
                  onChanged: (f) {
                    if (f != null) _auswerten(_text.text, quelle: _quelle ?? '', alsFormat: f);
                  },
                ),
              ],
            ),
            if (_quelle != null)
              Text(_quelle!, style: const TextStyle(fontSize: 11, color: kDim)),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // --- Zahlen ---
      Text.rich(TextSpan(children: [
        TextSpan(
          text: '${r.kartenAnzahl}',
          style: const TextStyle(color: kGold, fontWeight: FontWeight.bold, fontSize: 19),
        ),
        TextSpan(
          text: ' Karten · ${r.verschiedene} verschiedene',
          style: const TextStyle(fontSize: 13, color: kDim),
        ),
      ])),
      if (r.kartenAnzahl > 0)
        Text('geschätzter Wert ${formatEuro(wert)}',
            style: const TextStyle(fontSize: 11.5, color: kDim)),
      const SizedBox(height: 10),

      // --- Korrekturen und Fehler ---
      if (r.korrigiert.isNotEmpty)
        _ausklappbar(
          '${r.korrigiert.length} über eine Korrektur zugeordnet',
          kGold,
          _korrekturenAufgeklappt,
          () => setState(() => _korrekturenAufgeklappt = !_korrekturenAufgeklappt),
          r.korrigiert.map((z) => '${z.roh}  →  ${z.card!.id}  (${z.hinweis})').toList(),
        ),
      if (r.fehler.isNotEmpty)
        _ausklappbar(
          '${r.fehler.length} nicht zugeordnet',
          kAccent,
          _fehlerAufgeklappt,
          () => setState(() => _fehlerAufgeklappt = !_fehlerAufgeklappt),
          r.fehler.map((z) => 'Zeile ${z.zeile}: ${z.roh}').toList(),
        ),

      for (final w in r.warnungen) ...[
        const SizedBox(height: 8),
        _hinweisKasten(w, const Color(0x22FFB703), const Color(0x55FFB703)),
      ],

      if (r.leer) ...[
        const SizedBox(height: 14),
        _hinweisKasten(
          'Aus dieser Quelle lässt sich keine einzige Karte übernehmen.',
          const Color(0x33FF5252),
          const Color(0x66FF5252),
        ),
      ] else ...[
        const SizedBox(height: 16),
        const Text('Wohin', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ..._zielWahl(r),
        const SizedBox(height: 14),
        const Text('Einfügen', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ..._modusWahl(r),
      ],

      const SizedBox(height: 18),
      Row(
        children: [
          TextButton(
            onPressed: () => setState(() {
              _ergebnis = null;
              _quelle = null;
            }),
            child: const Text('Zurück'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: r.leer ? null : _uebernehmen,
            child: Text(r.leer ? 'Nichts zu übernehmen' : '${r.kartenAnzahl} Karten übernehmen'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _zielWahl(ImportResult r) {
    final eintraege = <Widget>[];

    if (_ordnerInDatei(r) || r.format == ImportFormat.sicherung) {
      eintraege.add(_radio<ImportZiel>(
        'Ordner aus der Datei übernehmen',
        ImportZiel.ausDatei,
        _ziel,
        (v) => setState(() => _ziel = v),
        unterzeile: 'Fehlende Ordner werden angelegt',
      ));
    }

    eintraege.add(Row(
      children: [
        Expanded(
          child: _radio<ImportZiel>(
            'In einen Ordner',
            ImportZiel.aktiverOrdner,
            _ziel,
            (v) => setState(() => _ziel = v),
          ),
        ),
        if (_ziel == ImportZiel.aktiverOrdner)
          DropdownButton<String>(
            value: widget.folders.any((f) => f.id == _ordnerId)
                ? _ordnerId
                : widget.folders.first.id,
            isDense: true,
            dropdownColor: kRow,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 12.5, color: kGold),
            items: widget.folders
                .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                .toList(),
            onChanged: (v) => setState(() => _ordnerId = v ?? _ordnerId),
          ),
      ],
    ));

    eintraege.add(_radio<ImportZiel>(
      'In einen neuen Ordner',
      ImportZiel.neuerOrdner,
      _ziel,
      (v) => setState(() => _ziel = v),
    ));
    if (_ziel == ImportZiel.neuerOrdner) {
      eintraege.add(Padding(
        padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
        child: TextField(
          controller: _ordnerName,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: _vorschlagName(),
            hintStyle: const TextStyle(fontSize: 13, color: kDim),
            filled: true,
            fillColor: kRow,
            border: const OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
      ));
    }

    return eintraege;
  }

  List<Widget> _modusWahl(ImportResult r) => [
        _radio<ImportMode>(
          'Dazuzählen',
          ImportMode.dazu,
          _modus,
          (v) => setState(() => _modus = v),
          unterzeile: 'Alles kommt obendrauf',
        ),
        _radio<ImportMode>(
          'Auf Anzahl auffüllen',
          ImportMode.auffuellen,
          _modus,
          (v) => setState(() => _modus = v),
          unterzeile: 'Nur ergänzen, was noch fehlt',
        ),
        _radio<ImportMode>(
          'Ersetzen',
          ImportMode.ersetzen,
          _modus,
          (v) => setState(() => _modus = v),
          unterzeile: r.format == ImportFormat.sicherung
              ? 'Vollständig wiederherstellen — der bisherige Stand wird überschrieben'
              : 'Zielordner leeren und neu befüllen',
        ),
      ];

  void _uebernehmen() {
    final name = _ordnerName.text.trim().isEmpty ? _vorschlagName() : _ordnerName.text.trim();
    Navigator.of(context).pop(ImportPlan(
      result: _ergebnis!,
      modus: _modus,
      ziel: _ziel,
      ordnerId: _ordnerId,
      neuerName: name,
    ));
  }

  String _vorschlagName() {
    final quelle = _quelle;
    if (quelle != null && quelle.contains('.')) {
      return quelle.substring(0, quelle.lastIndexOf('.'));
    }
    final jetzt = DateTime.now();
    return 'Import ${jetzt.day.toString().padLeft(2, '0')}.'
        '${jetzt.month.toString().padLeft(2, '0')}.${jetzt.year}';
  }

  // ------------------------------------------------------------------ Bausteine

  Widget _radio<T>(
    String text,
    T wert,
    T aktuell,
    void Function(T) onTap, {
    String? unterzeile,
  }) {
    return InkWell(
      onTap: () => onTap(wert),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              wert == aktuell ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: wert == aktuell ? kGold : kDim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: const TextStyle(fontSize: 13)),
                  if (unterzeile != null)
                    Text(unterzeile, style: const TextStyle(fontSize: 11, color: kDim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ausklappbar(
    String titel,
    Color farbe,
    bool offen,
    VoidCallback umschalten,
    List<String> zeilen,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: umschalten,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(offen ? Icons.expand_less : Icons.expand_more, size: 18, color: farbe),
                const SizedBox(width: 6),
                Text(titel, style: TextStyle(fontSize: 12.5, color: farbe)),
              ],
            ),
          ),
        ),
        if (offen)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kRow, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              child: Text(
                zeilen.join('\n'),
                style: const TextStyle(fontSize: 11.5, color: kDim, height: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _hinweisKasten(String text, Color fuellung, Color rand) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: fuellung,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: rand),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11.5, height: 1.35)),
      );

  static String _zeit(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}., '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} Uhr';
}
