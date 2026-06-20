package com.bizsooq.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.bizsooq.app/direct_share"
    private val deepLinkMethodChannelName = "com.bizsooq.app/deep_links"
    private val deepLinkEventChannelName = "com.bizsooq.app/deep_link_events"
    private var linkEventSink: EventChannel.EventSink? = null
    private var pendingInitialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "shareImageToPackage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val filePath = call.argument<String>("filePath")
                val packageName = call.argument<String>("packageName")
                val text = call.argument<String>("text") ?: ""
                if (filePath.isNullOrBlank() || packageName.isNullOrBlank()) {
                    result.error("invalid_args", "Missing share file or package.", null)
                    return@setMethodCallHandler
                }

                shareImageToPackage(filePath, packageName, text, result)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deepLinkMethodChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialLink") {
                    result.success(pendingInitialLink)
                    pendingInitialLink = null
                } else {
                    result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, deepLinkEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    linkEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    linkEventSink = null
                }
            })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingInitialLink = linkFromIntent(intent)
        keepSystemBarsVisible()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = linkFromIntent(intent)
        if (link != null) {
            linkEventSink?.success(link) ?: run { pendingInitialLink = link }
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        keepSystemBarsVisible()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) keepSystemBarsVisible()
    }

    private fun keepSystemBarsVisible() {
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.show(
                WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars()
            )
            window.insetsController?.setSystemBarsAppearance(
                0,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
            )
        }
    }

    private fun shareImageToPackage(
        filePath: String,
        packageName: String,
        text: String,
        result: MethodChannel.Result,
    ) {
        val file = File(filePath)
        if (!file.exists()) {
            result.error("file_missing", "Share image was not found.", null)
            return
        }
        if (!isPackageInstalled(packageName)) {
            result.error("not_installed", "Target app is not installed.", null)
            return
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageNameValue.share_file_provider",
            file,
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            setPackage(packageName)
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("not_installed", "Target app is not installed.", null)
        } catch (error: Exception) {
            result.error("share_failed", error.message ?: "Unable to share.", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private val packageNameValue: String
        get() = applicationContext.packageName

    private fun linkFromIntent(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) {
            return null
        }
        return intent.data?.toString()
    }
}
