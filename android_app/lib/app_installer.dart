import 'dart:async';

import 'package:flutter/services.dart';

/// Ergebnis einer Installation, wie Android es meldet.
///
/// Die Codes stammen aus `android.content.pm.PackageInstaller`.
class InstallStatus {
  static const pendingUserAction = -1;
  static const success = 0;
  static const failure = 1;
  static const blocked = 2;
  static const aborted = 3;
  static const invalid = 4;

  /// Signatur passt nicht zur installierten App, oder die Version ist aelter.
  ///
  /// **Der gefaehrlichste Fall:** Die naheliegende Reaktion waere Deinstallieren und
  /// neu probieren - und das loescht die Sammlung. Die App muss hier ausdruecklich
  /// davor warnen.
  static const conflict = 5;
  static const storage = 6;

  /// Geraet passt nicht (Android-Version, Prozessor).
  static const incompatible = 7;

  final int code;
  final String? message;

  const InstallStatus(this.code, this.message);

  bool get erfolgreich => code == success;
  bool get abgebrochen => code == aborted;
  bool get wartetAufNutzer => code == pendingUserAction;
  bool get istKonflikt => code == conflict;
}

/// Bruecke zum Android-Teil (InstallChannel.kt).
class AppInstaller {
  static const _channel = MethodChannel('de.feyzaras.onepiece_scanner/install');

  static final StreamController<InstallStatus> _status = StreamController.broadcast();
  static bool _eingerichtet = false;

  static void _einrichten() {
    if (_eingerichtet) return;
    _eingerichtet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onInstallStatus') {
        final args = (call.arguments as Map?) ?? const {};
        final code = (args['status'] as num?)?.toInt() ?? InstallStatus.failure;
        _status.add(InstallStatus(code, args['message'] as String?));
      }
    });
  }

  /// Meldungen ueber den Fortgang der Installation.
  static Stream<InstallStatus> get status {
    _einrichten();
    return _status.stream;
  }

  /// Darf die App Updates installieren? Muss der Nutzer einmalig erlauben.
  static Future<bool> darfInstallieren() async {
    try {
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Oeffnet die Einstellung "Unbekannte Apps installieren" fuer diese App.
  static Future<void> einstellungenOeffnen() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException {
      // Ohne Einstellungsseite bleibt nur der Hinweistext im Blatt
    } on MissingPluginException {
      // dito
    }
  }

  /// Uebergibt die APK an Android. Das Ergebnis kommt ueber [status].
  ///
  /// Wirft eine [PlatformException], wenn schon das Uebergeben scheitert.
  static Future<void> installieren(String apkPfad) async {
    _einrichten();
    await _channel.invokeMethod<bool>('installApk', {'path': apkPfad});
  }

  /// Oeffnet eine Adresse im Browser - als Ausweg, wenn die Installation in der
  /// App nicht klappt.
  static Future<bool> imBrowserOeffnen(String url) async {
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<int?> androidVersion() async {
    try {
      return await _channel.invokeMethod<int>('sdkInt');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
