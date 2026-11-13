package de.feyzaras.onepiece_scanner

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference

/**
 * Installiert ein heruntergeladenes Update der App.
 *
 * Bewusst ueber eine PackageInstaller-Sitzung und nicht ueber ACTION_VIEW:
 *
 * 1. Es braucht keinen FileProvider. Die APK wird direkt in die Sitzung geschrieben.
 * 2. Vor allem: Die App erfaehrt, WARUM eine Installation scheitert. Bei ACTION_VIEW
 *    zeigt Android nur "App nicht installiert" - und die naheliegende Reaktion darauf
 *    ist Deinstallieren und neu probieren. Genau das wuerde die Sammlung loeschen.
 *    Mit dem Statuscode kann die App stattdessen ausdruecklich davor warnen.
 */
object InstallChannel {
    private const val CHANNEL = "de.feyzaras.onepiece_scanner/install"
    const val ACTION_STATUS = "de.feyzaras.onepiece_scanner.INSTALL_STATUS"

    private var channel: MethodChannel? = null
    private var activityRef: WeakReference<Activity>? = null
    private val main = Handler(Looper.getMainLooper())

    fun register(activity: Activity, messenger: BinaryMessenger) {
        activityRef = WeakReference(activity)
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            val context = activityRef?.get() ?: activity
            when (call.method) {
                "canRequestPackageInstalls" -> result.success(canInstall(context))
                "openInstallSettings" -> {
                    openSettings(context)
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "Pfad zur APK fehlt", null)
                    } else {
                        install(context.applicationContext, path, result)
                    }
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("ARG", "Adresse fehlt", null)
                    } else {
                        try {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN", e.message ?: "Adresse liess sich nicht oeffnen", null)
                        }
                    }
                }
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                else -> result.notImplemented()
            }
        }
    }

    /** Darf diese App Pakete installieren? Ab Android 8 pro App einzeln freizugeben. */
    private fun canInstall(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openSettings(context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}")
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * Schreibt die APK in eine Installationssitzung und gibt sie frei.
     *
     * Laeuft in einem eigenen Thread: Das Kopieren von rund 37 MB wuerde sonst die
     * Oberflaeche einfrieren. Das Ergebnis der eigentlichen Installation kommt spaeter
     * ueber InstallStatusReceiver zurueck.
     */
    private fun install(context: Context, path: String, result: MethodChannel.Result) {
        Thread {
            try {
                val file = File(path)
                if (!file.exists()) throw IllegalStateException("APK nicht gefunden: $path")

                val installer = context.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                )
                params.setAppPackageName(context.packageName)
                params.setSize(file.length())

                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("base.apk", 0, file.length()).use { output ->
                            input.copyTo(output)
                            session.fsync(output)
                        }
                    }

                    // Explizites Ziel, sonst lehnt Android 14 einen veraenderlichen
                    // PendingIntent ab. FLAG_MUTABLE ist noetig, weil das System den
                    // Status als Extra eintraegt.
                    val intent = Intent(context, InstallStatusReceiver::class.java)
                        .setAction(ACTION_STATUS)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                    val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
                    session.commit(pending.intentSender)
                }
                main.post { result.success(true) }
            } catch (e: Exception) {
                main.post {
                    result.error("INSTALL", e.message ?: e.javaClass.simpleName, null)
                }
            }
        }.start()
    }

    /** Vom InstallStatusReceiver aufgerufen. */
    fun onStatus(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            // Android will den Nutzer fragen - das ist der Installationsdialog.
            val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            if (confirm != null) {
                val activity = activityRef?.get()
                if (activity != null && !activity.isFinishing) {
                    activity.startActivity(confirm)
                } else {
                    context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }

        main.post {
            channel?.invokeMethod(
                "onInstallStatus",
                mapOf("status" to status, "message" to message)
            )
        }
    }
}
