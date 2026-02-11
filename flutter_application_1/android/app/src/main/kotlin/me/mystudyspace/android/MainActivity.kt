package me.mystudyspace.android

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "me.mystudyspace.android/share_intent"
        private const val EVENT_CHANNEL =
            "me.mystudyspace.android/share_intent_events"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var initialPayload: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    if (initialPayload == null) {
                        initialPayload = buildSharePayload(intent)
                    }
                    result.success(initialPayload)
                }

                "clearInitialShare" -> {
                    initialPayload = null
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        initialPayload = buildSharePayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val payload = buildSharePayload(intent) ?: return
        initialPayload = payload
        eventSink?.success(payload)
    }

    private fun buildSharePayload(incomingIntent: Intent?): String? {
        if (incomingIntent == null) return null

        val action = incomingIntent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }

        val filesJson = JSONArray()
        when (action) {
            Intent.ACTION_SEND -> {
                val stream = getSingleStreamUri(incomingIntent)
                if (stream != null) {
                    copyUriToCache(stream, 0)?.let { filesJson.put(it) }
                }
            }

            Intent.ACTION_SEND_MULTIPLE -> {
                val streams = getMultipleStreamUris(incomingIntent) ?: arrayListOf()
                for (i in streams.indices) {
                    copyUriToCache(streams[i], i)?.let { filesJson.put(it) }
                }
            }
        }

        val sharedText = incomingIntent.getStringExtra(Intent.EXTRA_TEXT)
        if (filesJson.length() == 0 && sharedText.isNullOrBlank()) {
            return null
        }

        val payload = JSONObject()
        payload.put("action", action)
        payload.put("mimeType", incomingIntent.type ?: "")
        payload.put("text", sharedText ?: JSONObject.NULL)
        payload.put("files", filesJson)
        payload.put("receivedAt", System.currentTimeMillis())

        return payload.toString()
    }

    @Suppress("DEPRECATION")
    private fun getSingleStreamUri(incomingIntent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            incomingIntent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            incomingIntent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    @Suppress("DEPRECATION")
    private fun getMultipleStreamUris(incomingIntent: Intent): ArrayList<Uri>? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            incomingIntent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            incomingIntent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun copyUriToCache(uri: Uri, index: Int): JSONObject? {
        return try {
            val resolver = applicationContext.contentResolver
            val displayName = queryDisplayName(uri) ?: "shared_file_$index"
            val mimeType = resolver.getType(uri)
            val extension = extensionFrom(displayName, mimeType)
            val targetName = "incoming_${System.currentTimeMillis()}_${index}$extension"
            val targetFile = File(cacheDir, targetName)

            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return null

            val fileJson = JSONObject()
            fileJson.put("path", targetFile.absolutePath)
            fileJson.put("name", displayName)
            fileJson.put("mimeType", mimeType ?: "")
            fileJson.put("sizeBytes", targetFile.length())
            fileJson
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) {
                    cursor.getString(index)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun extensionFrom(displayName: String, mimeType: String?): String {
        val dotIndex = displayName.lastIndexOf('.')
        if (dotIndex > 0 && dotIndex < displayName.length - 1) {
            return displayName.substring(dotIndex).lowercase(Locale.US)
        }

        return when (mimeType?.lowercase(Locale.US)) {
            "application/pdf" -> ".pdf"
            "application/msword" -> ".doc"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> ".docx"
            "application/vnd.ms-powerpoint" -> ".ppt"
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> ".pptx"
            "image/png" -> ".png"
            "image/jpeg" -> ".jpg"
            "image/webp" -> ".webp"
            "image/gif" -> ".gif"
            else -> ".bin"
        }
    }
}
