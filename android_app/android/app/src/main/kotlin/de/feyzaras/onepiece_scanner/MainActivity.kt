package de.feyzaras.onepiece_scanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Kanal fuer die Aktualisierung aus der App heraus
        InstallChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
