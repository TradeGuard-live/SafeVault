package com.vault.vault

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.UUID

/**
 * MainActivity for Vault:
 * - FlutterFragmentActivity for BiometricPrompt compatibility.
 * - FLAG_SECURE window protection.
 * - Native Storage Access Framework (SAF) integration (ACTION_OPEN_DOCUMENT, ACTION_CREATE_DOCUMENT).
 * - Android Sharesheet incoming receiver (ACTION_SEND, ACTION_SEND_MULTIPLE).
 * - Outgoing share handler using FileProvider and Intent.createChooser().
 */
class MainActivity : FlutterFragmentActivity() {
    private val PRIVACY_CHANNEL = "com.vault.security/privacy"
    private val SAF_AND_SHARE_CHANNEL = "com.vault.native/saf_and_sharing"

    private val REQUEST_CODE_OPEN_DOC = 2001
    private val REQUEST_CODE_CREATE_DOC = 2002

    private var safOpenResult: MethodChannel.Result? = null
    private var safCreateResult: MethodChannel.Result? = null
    private var pendingCreateBytes: ByteArray? = null

    private var safChannel: MethodChannel? = null
    private val pendingIncomingShares = mutableListOf<Map<String, Any>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Privacy first: Hide preview in recent tasks and block screenshots by default
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        // Clean up any stale temporary export and staging files from previous sessions
        cleanupStaleCache()

        // Process any incoming share intent that launched the activity
        intent?.let { processIncomingIntent(it, isNew = false) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        processIncomingIntent(intent, isNew = true)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Privacy Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIVACY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureFlag" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    runOnUiThread {
                        if (enabled) {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE
                            )
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(true)
                }
                "isSecureFlagEnabled" -> {
                    val flags = window.attributes.flags
                    val isSecure = (flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                    result.success(isSecure)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Native SAF & Sharing Channel
        safChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_AND_SHARE_CHANNEL)
        safChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openDocument" -> handleOpenDocument(call, result)
                "createDocument" -> handleCreateDocument(call, result)
                "shareFiles" -> handleShareFiles(call, result)
                "shareText" -> handleShareText(call, result)
                "getPendingIncomingShare" -> {
                    val copy = ArrayList(pendingIncomingShares)
                    result.success(copy)
                }
                "clearPendingIncomingShare" -> {
                    clearIncomingStaging()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // =========================================================================
    // STORAGE ACCESS FRAMEWORK (SAF)
    // =========================================================================

    private fun handleOpenDocument(call: MethodCall, result: MethodChannel.Result) {
        if (safOpenResult != null) {
            result.error("BUSY", "Another file picker operation is in progress.", null)
            return
        }

        val allowMultiple = call.argument<Boolean>("allowMultiple") ?: true
        val mimeTypesList = call.argument<List<String>>("mimeTypes") ?: listOf("application/pdf", "image/jpeg", "image/jpg", "image/png")

        safOpenResult = result

        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                type = if (mimeTypesList.size == 1) mimeTypesList[0] else "*/*"
                if (mimeTypesList.isNotEmpty()) {
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypesList.toTypedArray())
                }
            }
            startActivityForResult(intent, REQUEST_CODE_OPEN_DOC)
        } catch (e: Exception) {
            safOpenResult = null
            result.error("SAF_LAUNCH_ERROR", "Failed to launch native file picker: ${e.message}", null)
        }
    }

    private fun handleCreateDocument(call: MethodCall, result: MethodChannel.Result) {
        if (safCreateResult != null) {
            result.error("BUSY", "Another save operation is in progress.", null)
            return
        }

        val defaultFileName = call.argument<String>("defaultFileName") ?: "extracted_text.txt"
        val mimeType = call.argument<String>("mimeType") ?: "text/plain"
        val bytes = call.argument<ByteArray>("contentBytes")

        if (bytes == null) {
            result.error("INVALID_ARGS", "contentBytes must not be null", null)
            return
        }

        safCreateResult = result
        pendingCreateBytes = bytes

        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, defaultFileName)
            }
            startActivityForResult(intent, REQUEST_CODE_CREATE_DOC)
        } catch (e: Exception) {
            safCreateResult = null
            pendingCreateBytes = null
            result.error("SAF_CREATE_ERROR", "Failed to launch file creator: ${e.message}", null)
        }
    }

    // =========================================================================
    // OUTGOING SHARING
    // =========================================================================

    private fun handleShareFiles(call: MethodCall, result: MethodChannel.Result) {
        val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()
        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: emptyList()
        val title = call.argument<String>("title") ?: "Share via Vault"

        if (filePaths.isEmpty()) {
            result.error("INVALID_ARGS", "filePaths must not be empty", null)
            return
        }

        try {
            val uris = ArrayList<Uri>()
            for (path in filePaths) {
                val file = File(path)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "Shared file does not exist: $path", null)
                    return
                }
                val uri = FileProvider.getUriForFile(this, "com.vault.vault.fileprovider", file)
                uris.add(uri)
            }

            val intent = if (uris.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    type = if (mimeTypes.isNotEmpty()) mimeTypes[0] else "*/*"
                    putExtra(Intent.EXTRA_STREAM, uris[0])
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = if (mimeTypes.isNotEmpty() && mimeTypes.all { it == mimeTypes[0] }) mimeTypes[0] else "*/*"
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }

            val chooser = Intent.createChooser(intent, title).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(chooser)
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_ERROR", "Failed to share files: ${e.message}", null)
        }
    }

    private fun handleShareText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        val title = call.argument<String>("title") ?: "Share Text"

        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            val chooser = Intent.createChooser(intent, title)
            startActivity(chooser)
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_TEXT_ERROR", "Failed to share text: ${e.message}", null)
        }
    }

    // =========================================================================
    // INCOMING SHARE HANDLING
    // =========================================================================

    private fun processIncomingIntent(intent: Intent, isNew: Boolean) {
        val action = intent.action ?: return

        if (Intent.ACTION_SEND != action && Intent.ACTION_SEND_MULTIPLE != action) {
            return
        }

        val incomingUris = mutableListOf<Uri>()

        if (Intent.ACTION_SEND == action) {
            val uri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }

            if (uri != null) {
                incomingUris.add(uri)
            } else if (intent.data != null) {
                incomingUris.add(intent.data!!)
            } else if (intent.clipData != null && intent.clipData!!.itemCount > 0) {
                for (i in 0 until intent.clipData!!.itemCount) {
                    val itemUri = intent.clipData!!.getItemAt(i).uri
                    if (itemUri != null && !incomingUris.contains(itemUri)) {
                        incomingUris.add(itemUri)
                    }
                }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action) {
            val uris = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }

            if (uris != null) {
                incomingUris.addAll(uris)
            }
            if (intent.clipData != null) {
                for (i in 0 until intent.clipData!!.itemCount) {
                    val itemUri = intent.clipData!!.getItemAt(i).uri
                    if (itemUri != null && !incomingUris.contains(itemUri)) {
                        incomingUris.add(itemUri)
                    }
                }
            }
        }

        if (incomingUris.isEmpty()) return

        // Stage files to secure temporary cache
        val staged = stageUrisToCache(incomingUris, prefix = "incoming_share")
        if (staged.isNotEmpty()) {
            pendingIncomingShares.addAll(staged)
            if (isNew) {
                // Notify Flutter that a new incoming share has arrived
                safChannel?.invokeMethod("onIncomingShareReceived", staged)
            }
        }
    }

    private fun stageUrisToCache(uris: List<Uri>, prefix: String): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val stagingDir = File(cacheDir, "staging").apply { if (!exists()) mkdirs() }

        for (uri in uris) {
            try {
                var displayName = "shared_document_${UUID.randomUUID().toString().take(8)}"
                var fileSize = -1L
                var mimeType = contentResolver.getType(uri) ?: intent?.type ?: "application/octet-stream"

                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (cursor.moveToFirst()) {
                        if (nameIndex != -1) {
                            val name = cursor.getString(nameIndex)
                            if (!name.isNullOrBlank()) displayName = name
                        }
                        if (sizeIndex != -1) {
                            fileSize = cursor.getLong(sizeIndex)
                        }
                    }
                }

                // If MIME type is generic, infer from file extension
                if (mimeType == "application/octet-stream" || mimeType == "*/*") {
                    val ext = displayName.substringAfterLast('.', "").lowercase()
                    mimeType = when (ext) {
                        "pdf" -> "application/pdf"
                        "jpg", "jpeg" -> "image/jpeg"
                        "png" -> "image/png"
                        else -> mimeType
                    }
                }

                // Supported document formats check
                val isSupported = mimeType.contains("pdf") ||
                        mimeType.startsWith("image/") ||
                        displayName.endsWith(".pdf", ignoreCase = true) ||
                        displayName.endsWith(".jpg", ignoreCase = true) ||
                        displayName.endsWith(".jpeg", ignoreCase = true) ||
                        displayName.endsWith(".png", ignoreCase = true)

                if (!isSupported) continue

                // Determine file extension
                val extension = if (displayName.contains('.')) {
                    displayName.substringAfterLast('.')
                } else if (mimeType.contains("pdf")) {
                    "pdf"
                } else if (mimeType.contains("png")) {
                    "png"
                } else {
                    "jpg"
                }

                val safeFileName = "${prefix}_${UUID.randomUUID()}.$extension"
                val targetFile = File(stagingDir, safeFileName)

                // Stream content safely with 8KB buffer
                contentResolver.openInputStream(uri)?.use { inputStream ->
                    FileOutputStream(targetFile).use { outputStream ->
                        val buffer = ByteArray(8192)
                        var read: Int
                        while (inputStream.read(buffer).also { read = it } != -1) {
                            outputStream.write(buffer, 0, read)
                        }
                        outputStream.flush()
                    }
                }

                if (targetFile.exists() && targetFile.length() > 0) {
                    val finalSize = if (fileSize > 0) fileSize else targetFile.length()
                    result.add(
                        mapOf(
                            "path" to targetFile.absolutePath,
                            "name" to displayName,
                            "size" to finalSize,
                            "mimeType" to mimeType
                        )
                    )
                }
            } catch (e: Exception) {
                // Skip unreadable URI, continue with others
            }
        }
        return result
    }

    private fun clearIncomingStaging() {
        pendingIncomingShares.clear()
        try {
            val stagingDir = File(cacheDir, "staging")
            if (stagingDir.exists()) {
                stagingDir.listFiles()?.forEach { it.delete() }
            }
        } catch (ignored: Exception) {}
    }

    private fun cleanupStaleCache() {
        try {
            // Clean up temporary shared export files from previous app runs
            val exportDir = File(cacheDir, "shared_exports")
            if (exportDir.exists()) {
                exportDir.listFiles()?.forEach { it.delete() }
            }
            // Clean up staging directory
            val stagingDir = File(cacheDir, "staging")
            if (stagingDir.exists()) {
                stagingDir.listFiles()?.forEach { it.delete() }
            }
        } catch (ignored: Exception) {}
    }

    // =========================================================================
    // ON ACTIVITY RESULT
    // =========================================================================

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQUEST_CODE_OPEN_DOC -> {
                val currentResult = safOpenResult
                safOpenResult = null

                if (currentResult == null) return

                if (resultCode != Activity.RESULT_OK || data == null) {
                    // User cancelled or back was pressed
                    currentResult.success(emptyList<Map<String, Any>>())
                    return
                }

                try {
                    val selectedUris = mutableListOf<Uri>()
                    data.data?.let { selectedUris.add(it) }

                    data.clipData?.let { clipData ->
                        for (i in 0 until clipData.itemCount) {
                            val uri = clipData.getItemAt(i).uri
                            if (uri != null && !selectedUris.contains(uri)) {
                                selectedUris.add(uri)
                            }
                        }
                    }

                    if (selectedUris.isEmpty()) {
                        currentResult.success(emptyList<Map<String, Any>>())
                        return
                    }

                    val stagedFiles = stageUrisToCache(selectedUris, prefix = "saf_import")
                    currentResult.success(stagedFiles)
                } catch (e: Exception) {
                    currentResult.error("SAF_READ_ERROR", "Failed to read selected files: ${e.message}", null)
                }
            }

            REQUEST_CODE_CREATE_DOC -> {
                val currentResult = safCreateResult
                val bytesToWrite = pendingCreateBytes
                safCreateResult = null
                pendingCreateBytes = null

                if (currentResult == null) return

                if (resultCode != Activity.RESULT_OK || data == null || data.data == null || bytesToWrite == null) {
                    currentResult.success(false)
                    return
                }

                try {
                    val uri = data.data!!
                    contentResolver.openOutputStream(uri)?.use { outputStream ->
                        outputStream.write(bytesToWrite)
                        outputStream.flush()
                    }
                    currentResult.success(true)
                } catch (e: Exception) {
                    currentResult.error("SAF_WRITE_ERROR", "Failed to write file to storage: ${e.message}", null)
                }
            }
        }
    }
}
