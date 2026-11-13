package de.feyzaras.onepiece_scanner

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Empfaengt das Ergebnis einer Installationssitzung und reicht es an Dart weiter.
 *
 * Im Manifest mit exported="false" eingetragen: Nur das System darf diesen Empfaenger
 * ueber den PendingIntent der eigenen Sitzung ansprechen, keine fremde App.
 */
class InstallStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        InstallChannel.onStatus(context, intent)
    }
}
