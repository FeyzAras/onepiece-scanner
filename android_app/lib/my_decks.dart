import 'package:flutter/foundation.dart';

import 'card_matcher.dart';
import 'card_model.dart';
import 'collection_import.dart';
import 'deck_model.dart';

/// Ein selbst gebautes Deck.
///
/// [karten] sind Karten-IDs mit Anzahl - ohne den Leader. Alt-Arts duerfen mit eigener ID
/// stehen (wer sein Deck mit Alt-Arts spielt, will sie auch so sehen); die Kopiengrenze
/// zaehlt trotzdem je Kartennummer, siehe [DeckRegeln].
class MeinDeck {
  final String id;
  final String name;
  final String? leaderId;
  final Map<String, int> karten;
  final DateTime geaendert;

  const MeinDeck({
    required this.id,
    required this.name,
    this.leaderId,
    this.karten = const {},
    required this.geaendert,
  });

  int get anzahl => karten.values.fold(0, (s, n) => s + n);

  MeinDeck kopieMit({String? name, String? leaderId, bool ohneLeader = false, Map<String, int>? karten}) =>
      MeinDeck(
        id: id,
        name: name ?? this.name,
        leaderId: ohneLeader ? null : (leaderId ?? this.leaderId),
        karten: karten ?? this.karten,
        geaendert: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (leaderId != null) 'leader': leaderId,
        'cards': karten,
        'at': geaendert.millisecondsSinceEpoch,
      };

  static MeinDeck? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final karten = <String, int>{};
    final roh = j['cards'];
    if (roh is Map) {
      roh.forEach((k, v) {
        final n = v is num ? v.toInt() : null;
        if (n != null && n > 0) karten['$k'] = n;
      });
    }
    return MeinDeck(
      id: id,
      name: j['name'] is String && (j['name'] as String).isNotEmpty ? j['name'] as String : 'Deck',
      leaderId: j['leader'] is String ? j['leader'] as String : null,
      karten: karten,
      geaendert: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Alle eigenen Decks - ein gemeinsames Modell fuer Liste und Editor.
///
/// Wie bei der Wunschliste: gespeichert wird ueber [onAenderung], nur bei echten
/// Aenderungen, nie beim [laden].
class MeineDecks extends ChangeNotifier {
  MeineDecks({this.onAenderung});

  VoidCallback? onAenderung;
  List<MeinDeck> _decks = [];

  List<MeinDeck> get decks => List.unmodifiable(_decks);
  MeinDeck? deck(String id) {
    for (final d in _decks) {
      if (d.id == id) return d;
    }
    return null;
  }

  void laden(List<MeinDeck> decks) {
    _decks = [...decks];
    notifyListeners();
  }

  /// Legt ein Deck an und gibt seine ID zurueck.
  String anlegen({required String name, String? leaderId, Map<String, int> karten = const {}}) {
    var id = DateTime.now().microsecondsSinceEpoch.toString();
    while (deck(id) != null) {
      id = '${id}x';
    }
    _decks = [
      MeinDeck(id: id, name: name, leaderId: leaderId, karten: {...karten}, geaendert: DateTime.now()),
      ..._decks,
    ];
    _geaendert();
    return id;
  }

  void ersetzen(MeinDeck neu) {
    final i = _decks.indexWhere((d) => d.id == neu.id);
    if (i < 0) return;
    _decks = [..._decks]..[i] = neu;
    _geaendert();
  }

  void loeschen(String id) {
    final vorher = _decks.length;
    _decks = _decks.where((d) => d.id != id).toList();
    if (_decks.length != vorher) _geaendert();
  }

  /// Anzahl einer Karte im Deck aendern. 0 entfernt sie.
  void setzeKarte(String deckId, String cardId, int anzahl) {
    final d = deck(deckId);
    if (d == null) return;
    final karten = {...d.karten};
    if (anzahl <= 0) {
      karten.remove(cardId);
    } else {
      karten[cardId] = anzahl.clamp(1, 99);
    }
    ersetzen(d.kopieMit(karten: karten));
  }

  void _geaendert() {
    notifyListeners();
    onAenderung?.call();
  }
}

/// Ergebnis der Regelpruefung.
class DeckPruefung {
  final OpCard? leader;
  final int anzahl;

  /// Kartennummern mit mehr als 4 Exemplaren (Alt-Arts zaehlen mit) -> Anzahl.
  final Map<String, int> zuViele;

  /// Karten mit einer Farbe, die der Leader nicht hat.
  final List<OpCard> falscheFarbe;

  /// Leader oder andere Karten, die nicht ins 50er-Deck gehoeren.
  final List<OpCard> falscherTyp;

  /// IDs, die der Katalog nicht kennt.
  final List<String> unbekannt;

  /// Karten, die eine Sonderregel des Leaders verletzen (z.B. Rayleigh: keine Kosten ab 5).
  final List<OpCard> sonderregelVerstoss;

  /// Sonderregeln des Leaders, die die App erkannt und geprueft hat.
  final LeaderSonderregel? sonderregel;

  const DeckPruefung({
    required this.leader,
    required this.anzahl,
    required this.zuViele,
    required this.falscheFarbe,
    required this.falscherTyp,
    required this.unbekannt,
    this.sonderregelVerstoss = const [],
    this.sonderregel,
  });

  bool get gueltig =>
      leader != null &&
      anzahl == DeckRegeln.deckGroesse &&
      zuViele.isEmpty &&
      falscheFarbe.isEmpty &&
      falscherTyp.isEmpty &&
      sonderregelVerstoss.isEmpty;

  /// Gibt es eine Sonderregel, die die App nicht pruefen kann? Dann ist "spielbereit"
  /// nur unter Vorbehalt.
  bool get vorbehalt => sonderregel?.ungeprueft.isNotEmpty ?? false;

  /// Was fehlt oder falsch ist, in Klartext. Leer, wenn alles stimmt.
  List<String> get meldungen => [
        if (leader == null) 'Es fehlt ein Leader.',
        if (anzahl < DeckRegeln.deckGroesse) 'Noch ${DeckRegeln.deckGroesse - anzahl} Karten bis 50.',
        if (anzahl > DeckRegeln.deckGroesse) '${anzahl - DeckRegeln.deckGroesse} Karten zu viel — erlaubt sind genau 50.',
        for (final e in zuViele.entries) '${e.key}: ${e.value}× — höchstens 4 je Kartennummer, Alt-Arts zählen mit.',
        if (falscheFarbe.isNotEmpty)
          '${falscheFarbe.length} Karte(n) in einer Farbe, die der Leader nicht hat.',
        if (falscherTyp.isNotEmpty) '${falscherTyp.length} Karte(n), die nicht ins Deck dürfen (z.B. ein zweiter Leader).',
        if (sonderregelVerstoss.isNotEmpty)
          '${sonderregelVerstoss.length} Karte(n) verstoßen gegen die Regel des Leaders: ${sonderregel!.beschreibung}.',
        if (unbekannt.isNotEmpty) '${unbekannt.length} Karte(n) unbekannt: ${unbekannt.join(', ')}.',
      ];
}

/// Sonderregeln eines Leaders zum Deckbau (Comprehensive Rules 5-1-2-4).
///
/// Erkannt werden die festen Formulierungen, mit denen Bandai solche Regeln druckt -
/// immer eingeleitet mit "Under the rules of this game":
/// * "cannot include cards/Events/... with a cost of N or more" (z.B. Rayleigh, Imu)
/// * "can only include {Typ} type cards" (z.B. P-117 Nami)
///
/// Jede andere Deckbau-Regel landet in [ungeprueft] - die App sagt dann ausdruecklich,
/// dass sie sie nicht prueft, statt still "spielbereit" zu melden. Saetze mit "Under the
/// rules of this game", die gar nicht vom Deckbau handeln, werden uebergangen: Brook
/// OP15-022 ("you do not lose when your deck has 0 cards") und Enel OP15-058 ("your DON!!
/// deck consists of 6 cards") sind Spielregeln - ein Vorbehalt waere dort ein Fehlalarm.
class LeaderSonderregel {
  /// Ab diesen Kosten verboten, oder null.
  final int? kostenAb;

  /// Fuer welchen Kartentyp das Kostenlimit gilt (null = alle).
  final String? kostenTyp;

  /// Nur Karten dieses Typs (z.B. "East Blue"), oder null.
  final String? nurTyp;

  final List<String> ungeprueft;

  const LeaderSonderregel({this.kostenAb, this.kostenTyp, this.nurTyp, this.ungeprueft = const []});

  static final _abschnitt = RegExp(r'Under the rules of this game,?([^.]*)', caseSensitive: false);
  static final _kosten =
      RegExp(r'cannot include (cards|characters|events|stages) with a cost of (\d+) or more', caseSensitive: false);
  static final _typ = RegExp(r'can only include \{([^}]+)\} type cards', caseSensitive: false);

  /// Woran ein Satz als Deckbau-Regel zu erkennen ist. Bandai schreibt "include" ("cannot
  /// include", "can only include"); "contain" und "any number of" fuer den Fall, dass
  /// kuenftige Karten anders formulieren.
  static final _deckbau = RegExp(r'\binclude\b|\bcontain\b|any number of', caseSensitive: false);

  /// Null, wenn der Leader keine Sonderregel hat.
  static LeaderSonderregel? aus(OpCard? leader) {
    if (leader == null) return null;
    int? kostenAb;
    String? kostenTyp, nurTyp;
    final ungeprueft = <String>[];
    for (final m in _abschnitt.allMatches(leader.effect)) {
      final satz = m.group(0)!.trim();
      final k = _kosten.firstMatch(satz);
      final t = _typ.firstMatch(satz);
      if (k != null) {
        kostenAb = int.parse(k.group(2)!);
        final art = k.group(1)!.toLowerCase();
        kostenTyp = art == 'cards' ? null : art.substring(0, art.length - 1).toUpperCase();
      }
      if (t != null) nurTyp = t.group(1);
      if (k == null && t == null && _deckbau.hasMatch(satz)) ungeprueft.add(satz);
    }
    if (kostenAb == null && nurTyp == null && ungeprueft.isEmpty) return null;
    return LeaderSonderregel(kostenAb: kostenAb, kostenTyp: kostenTyp, nurTyp: nurTyp, ungeprueft: ungeprueft);
  }

  bool erlaubt(OpCard karte) {
    final ab = kostenAb;
    if (ab != null && (kostenTyp == null || karte.cardType == kostenTyp) && (karte.costLife ?? 0) >= ab) {
      return false;
    }
    final typ = nurTyp;
    if (typ != null && karte.types.isNotEmpty && !karte.types.contains(typ)) return false;
    return true;
  }

  String get beschreibung => [
        if (kostenAb != null)
          'keine ${switch (kostenTyp) { 'EVENT' => 'Events', 'CHARACTER' => 'Charaktere', 'STAGE' => 'Stages', _ => 'Karten' }} ab Kosten $kostenAb',
        if (nurTyp != null) 'nur {$nurTyp}-Karten',
      ].join(', ');
}

/// Die Deckbauregeln nach den offiziellen Comprehensive Rules, Version 1.2.1 (28.08.2026):
///
/// * 5-1-2: "exactly 1 Leader card, a 50-card deck, and a 10-card DON!! deck"
/// * 5-1-2-1: Das Deck besteht aus Character-, Event- und Stage-Karten.
/// * 5-1-2-2: "Only cards of a color included on the Leader card can be included in a deck.
///   Cards of a color not included on the Leader card cannot be added to the deck."
///   Daraus folgt: Eine mehrfarbige Karte braucht ALLE ihre Farben im Leader - sie ist
///   sonst zugleich eine Karte einer nicht enthaltenen Farbe.
/// * 5-1-2-3: "no more than 4 cards with the same card number" - Alt-Arts tragen dieselbe
///   Nummer und zaehlen deshalb zusammen.
///
/// * 5-1-2-4: Karteneffekte, die den Deckbau veraendern, gehen diesen Regeln vor. Geprueft
///   werden die Formulierungen, die es im Katalog gibt: "any number of this card"
///   ([beliebigViele]) und die Kosten- und Typgrenzen einzelner Leader ([LeaderSonderregel]).
///
/// Nicht geprueft: Sperrlisten - die gibt es in den Daten nicht.
class DeckRegeln {
  static const deckGroesse = 50;
  static const maxKopien = 4;
  static const erlaubteTypen = {'CHARACTER', 'EVENT', 'STAGE'};

  static DeckPruefung pruefen(MeinDeck deck, OpCard? Function(String id) karteVon) {
    final leaderKarte = deck.leaderId == null ? null : karteVon(deck.leaderId!);
    final leader = leaderKarte != null && leaderKarte.cardType == 'LEADER' ? leaderKarte : null;
    final sonder = LeaderSonderregel.aus(leader);

    final proNummer = <String, int>{};
    final ohneGrenze = <String>{};
    final falscheFarbe = <OpCard>[];
    final falscherTyp = <OpCard>[];
    final sonderVerstoss = <OpCard>[];
    final unbekannt = <String>[];

    deck.karten.forEach((id, n) {
      final karte = karteVon(id);
      if (karte == null) {
        unbekannt.add(id);
        return;
      }
      proNummer[karte.baseId] = (proNummer[karte.baseId] ?? 0) + n;
      if (beliebigViele(karte)) ohneGrenze.add(karte.baseId);
      if (!erlaubteTypen.contains(karte.cardType)) {
        falscherTyp.add(karte);
      } else if (leader != null && !farbeErlaubt(karte, leader)) {
        falscheFarbe.add(karte);
      } else if (sonder != null && !sonder.erlaubt(karte)) {
        sonderVerstoss.add(karte);
      }
    });

    return DeckPruefung(
      leader: leader,
      anzahl: deck.anzahl,
      zuViele: {
        for (final e in proNummer.entries)
          if (e.value > maxKopien && !ohneGrenze.contains(e.key)) e.key: e.value,
      },
      falscheFarbe: falscheFarbe,
      falscherTyp: falscherTyp,
      unbekannt: unbekannt,
      sonderregelVerstoss: sonderVerstoss,
      sonderregel: sonder,
    );
  }

  /// Regel 5-1-2-4: Manche Karten heben die Kopiengrenze auf - im Wortlaut
  /// "Under the rules of this game, you may have any number of this card in your deck."
  /// (Pacifista, Biscuit Warrior, Prisoner of Impel Down).
  static bool beliebigViele(OpCard karte) =>
      karte.effect.toLowerCase().contains('any number of this card in your deck');

  /// Regel 5-1-2-2: Alle Farben der Karte muessen im Leader vorkommen. Karten ohne
  /// Farbangabe (Datenluecke) gelten als erlaubt - lieber keine falsche Fehlermeldung.
  static bool farbeErlaubt(OpCard karte, OpCard leader) {
    if (karte.colors.isEmpty) return true;
    return karte.colors.every(leader.colors.contains);
  }

  /// Darf diese Karte ueberhaupt in ein Deck mit diesem Leader? Fuer den Kartensucher -
  /// beruecksichtigt auch Sonderregeln des Leaders.
  static bool passt(OpCard karte, OpCard? leader) {
    if (!erlaubteTypen.contains(karte.cardType)) return false;
    if (leader == null) return true;
    if (!farbeErlaubt(karte, leader)) return false;
    final sonder = LeaderSonderregel.aus(leader);
    return sonder == null || sonder.erlaubt(karte);
  }

  /// Hoechstzahl je Kartennummer fuer den Editor (+-Knopf).
  static int grenze(OpCard karte) => beliebigViele(karte) ? 99 : maxKopien;

  /// Wie viele Exemplare dieser Kartennummer schon im Deck sind (alle Artworks).
  static int kopienDerNummer(MeinDeck deck, String baseId, OpCard? Function(String id) karteVon) {
    var summe = 0;
    deck.karten.forEach((id, n) {
      if ((karteVon(id)?.baseId ?? id) == baseId) summe += n;
    });
    return summe;
  }
}

/// Kennzahlen fuer den Editor.
class DeckStatistik {
  /// Karten je Kosten 0..10, alles darueber zaehlt bei 10.
  final List<int> kostenKurve;
  final Map<String, int> nachTyp;
  final int counter1000;
  final int counter2000;

  const DeckStatistik({
    required this.kostenKurve,
    required this.nachTyp,
    required this.counter1000,
    required this.counter2000,
  });

  static DeckStatistik berechnen(MeinDeck deck, OpCard? Function(String id) karteVon) {
    final kurve = List<int>.filled(11, 0);
    final typ = <String, int>{};
    var c1 = 0, c2 = 0;
    deck.karten.forEach((id, n) {
      final k = karteVon(id);
      if (k == null) return;
      final kosten = (k.costLife ?? 0).clamp(0, 10);
      kurve[kosten] += n;
      typ[k.cardType] = (typ[k.cardType] ?? 0) + n;
      if (k.counter == 1000) c1 += n;
      if (k.counter == 2000) c2 += n;
    });
    return DeckStatistik(kostenKurve: kurve, nachTyp: typ, counter1000: c1, counter2000: c2);
  }
}

/// Deck <-> Text und Uebernahmen.
class DeckText {
  /// "1xLEADER" zuerst, dann die Karten - das uebliche Format von Deck-Seiten und
  /// Simulatoren. Unsere eigenen Turnierdecks sehen genauso aus.
  static String alsText(MeinDeck deck) {
    final zeilen = <String>[
      if (deck.leaderId != null) '1x${deck.leaderId}',
      for (final id in deck.karten.keys.toList()..sort()) '${deck.karten[id]}x$id',
    ];
    return zeilen.join('\n');
  }

  /// Liest eine eingefuegte Deckliste ueber den vorhandenen Import-Parser.
  ///
  /// Der Leader ist die einzige Leader-Karte der Liste. Stehen mehrere drin, wird keiner
  /// geraten - der Nutzer waehlt ihn dann selbst.
  static ({String? leaderId, Map<String, int> karten, List<String> nichtErkannt}) ausText(
    String text,
    CardMatcher matcher,
  ) {
    final r = CollectionImport.read(text, matcher: matcher, alsFormat: ImportFormat.textListe);
    final karten = <String, int>{};
    final leader = <String>{};
    for (final z in r.treffer) {
      final k = z.card!;
      if (k.cardType == 'LEADER') {
        leader.add(k.id);
      } else {
        karten[k.id] = (karten[k.id] ?? 0) + z.anzahl;
      }
    }
    return (
      leaderId: leader.length == 1 ? leader.first : null,
      karten: karten,
      nichtErkannt: r.fehler.map((z) => z.roh).toList(),
    );
  }

  /// Ein Turnierdeck als Vorlage. Die Liste enthaelt den Leader als "1x" - er wird
  /// herausgeloest. Eingetragen werden die Normalversionen.
  static ({String? leaderId, Map<String, int> karten}) ausTurnierdeck(
    Deck turnier,
    OpCard? Function(String baseId) karteZurNummer,
  ) {
    final karten = <String, int>{};
    String? leaderId;
    for (final c in turnier.cards) {
      final k = karteZurNummer(c.id);
      if (k == null) continue;
      if (k.cardType == 'LEADER') {
        leaderId ??= k.id;
        continue;
      }
      karten[k.id] = (karten[k.id] ?? 0) + c.qty;
    }
    if (leaderId == null && turnier.leaderId != null) {
      leaderId = karteZurNummer(turnier.leaderId!)?.id;
    }
    return (leaderId: leaderId, karten: karten);
  }
}

/// Was vom Deck schon in der Sammlung liegt, und was fuer die Wunschliste fehlt.
class DeckAbdeckung {
  final int vorhanden;
  final int benoetigt;

  /// Fuer die Wunschliste: Karten-ID -> wie viele fehlen.
  final Map<String, int> fehlend;

  const DeckAbdeckung({required this.vorhanden, required this.benoetigt, required this.fehlend});

  /// Besitz zaehlt je Kartennummer, egal welches Artwork - zum Spielen reicht jedes.
  static DeckAbdeckung berechnen(
    MeinDeck deck,
    OpCard? Function(String id) karteVon,
    int Function(String baseId) besitzZurNummer,
  ) {
    final bedarf = <String, int>{};
    final idZurNummer = <String, String>{};
    deck.karten.forEach((id, n) {
      final k = karteVon(id);
      final nummer = k?.baseId ?? id;
      bedarf[nummer] = (bedarf[nummer] ?? 0) + n;
      // Fuer die Wunschliste die Variante merken, die im Deck am haeufigsten steht
      final bisher = idZurNummer[nummer];
      if (bisher == null || (deck.karten[bisher] ?? 0) < n) idZurNummer[nummer] = id;
    });

    var vorhanden = 0, benoetigt = 0;
    final fehlend = <String, int>{};
    bedarf.forEach((nummer, n) {
      final hat = besitzZurNummer(nummer).clamp(0, n);
      vorhanden += hat;
      benoetigt += n;
      if (hat < n) fehlend[idZurNummer[nummer]!] = n - hat;
    });
    return DeckAbdeckung(vorhanden: vorhanden, benoetigt: benoetigt, fehlend: fehlend);
  }
}
