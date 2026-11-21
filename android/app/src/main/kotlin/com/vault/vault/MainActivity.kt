package com.vault.vault

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
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
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * MainActivity for SafeVault:
 * - FlutterFragmentActivity for BiometricPrompt compatibility.
 * - FLAG_SECURE window protection against screen recording and recent tasks preview.
 * - Hardware-backed Android Keystore integration (AES-256-GCM) with mandatory user authentication.
 * - Native Storage Access Framework (SAF) integration (ACTION_OPEN_DOCUMENT, ACTION_CREATE_DOCUMENT).
 * - Android Sharesheet incoming receiver with strict magic-byte signature validation and size limits.
 * - Outgoing share handler strictly scoped to temporary exports directory with read-only permissions.
 */
class MainActivity : FlutterFragmentActivity() {
    private val PRIVACY_CHANNEL = "com.vault.security/privacy"
    private val SAF_AND_SHARE_CHANNEL = "com.vault.native/saf_and_sharing"
    private val KEYSTORE_BIOMETRIC_CHANNEL = "com.vault.security/keystore_biometric"

    private val KEYSTORE_ALIAS = "vault_biometric_hardware_kek"
    private val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private val GCM_TAG_LENGTH = 128
    private val GCM_IV_LENGTH = 12

    private val MAX_FILE_SIZE_BYTES = 50L * 1024 * 1024 // 50 MB
    private val MAX_TOTAL_SIZE_BYTES = 150L * 1024 * 1024 // 150 MB
    private val MAX_FILE_COUNT = 10

    private val REQUEST_CODE_OPEN_DOC = 2001
    private val REQUEST_CODE_CREATE_DOC = 2002

    private var safOpenResult: MethodChannel.Result? = null
    private var safCreateResult: MethodChannel.Result? = null
    private var pendingCreateBytes: ByteArray? = null

    private var safChannel: MethodChannel? = null
    private val pendingIncomingShares = mutableListOf<Map<String, Any>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Privacy first: Hide preview in recent tasks and block screenshots
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

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 1. Privacy Channel
        MethodChannel(messenger, PRIVACY_CHANNEL).setMethodCallHandler { call, result ->
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
        safChannel = MethodChannel(messenger, SAF_AND_SHARE_CHANNEL)
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

        // 3. Android Keystore Biometric Protection Channel
        MethodChannel(messenger, KEYSTORE_BIOMETRIC_CHANNEL).setMethodCallHandler { call, result ->
            handleKeystoreBiometric(call, result)
        }
    }

    // =========================================================================
    // HARDWARE-BACKED ANDROID KEYSTORE BIOMETRIC ENCRYPTION
    // =========================================================================

    private fun handleKeystoreBiometric(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "generateBiometricKey" -> {
                try {
                    val success = generateKeystoreBiometricKey()
                    result.success(success)
                } catch (e: Exception) {
                    result.error("KEYSTORE_GEN_FAILED", "Failed to generate biometric Keystore key: ${e.message}", null)
                }
            }
            "wrapBiometricShare" -> {
                val shareBytes = call.argument<ByteArray>("shareBytes")
                if (shareBytes == null || shareBytes.isEmpty()) {
                    result.error("INVALID_ARGS", "shareBytes cannot be null or empty", null)
                    return
                }
                try {
                    val wrapped = wrapBiometricShare(shareBytes)
                    result.success(wrapped)
                } catch (e: Exception) {
                    result.error("KEYSTORE_WRAP_FAILED", "Failed to wrap biometric share: ${e.message}", null)
                }
            }
            "unwrapBiometricShare" -> {
                val wrappedBytes = call.argument<ByteArray>("wrappedBytes")
                if (wrappedBytes == null || wrappedBytes.isEmpty()) {
                    result.error("INVALID_ARGS", "wrappedBytes cannot be null or empty", null)
                    return
                }
                try {
                    val unwrapped = unwrapBiometricShare(wrappedBytes)
                    result.success(unwrapped)
                } catch (e: KeyPermanentlyInvalidatedException) {
                    result.error(
                        "KEY_PERMANENTLY_INVALIDATED",
                        "Android Keystore invalidated the biometric key because device biometrics were modified in system settings.",
                        null
                    )
                } catch (e: UserNotAuthenticatedException) {
                    result.error(
                        "USER_NOT_AUTHENTICATED",
                        "User must authenticate with hardware biometrics before accessing key.",
                        null
                    )
                } catch (e: Exception) {
                    result.error("KEYSTORE_UNWRAP_FAILED", "Failed to unwrap biometric share: ${e.message}", null)
                }
            }
            "isKeystoreKeyAvailable" -> {
                try {
                    val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
                    val available = keyStore.containsAlias(KEYSTORE_ALIAS)
                    result.success(available)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "deleteBiometricKey" -> {
                try {
                    val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
                    if (keyStore.containsAlias(KEYSTORE_ALIAS)) {
                        keyStore.deleteEntry(KEYSTORE_ALIAS)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    result.error("KEYSTORE_DELETE_FAILED", "Failed to delete Keystore key: ${e.message}", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun generateKeystoreBiometricKey(): Boolean {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        if (keyStore.containsAlias(KEYSTORE_ALIAS)) {
            keyStore.deleteEntry(KEYSTORE_ALIAS)
        }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val builder = KeyGenParameterSpec.Builder(
            KEYSTORE_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                30, // 30-second validity window after successful biometric authentication
                KeyProperties.AUTH_BIOMETRIC_STRONG
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(30)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setInvalidatedByBiometricEnrollment(true)
        }

        keyGenerator.init(builder.build())
        keyGenerator.generateKey()
        return true
    }

    private fun wrapBiometricShare(shareBytes: ByteArray): ByteArray {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val secretKey = keyStore.getKey(KEYSTORE_ALIAS, null) as? SecretKey
            ?: throw IllegalStateException("Keystore biometric key '$KEYSTORE_ALIAS' not found.")

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(shareBytes)

        val combined = ByteArray(iv.size + ciphertext.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
        return combined
    }

    private fun unwrapBiometricShare(wrappedBytes: ByteArray): ByteArray {
        if (wrappedBytes.size < (GCM_IV_LENGTH + 16)) {
            throw IllegalArgumentException("Invalid wrapped share payload length.")
        }

        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val secretKey = keyStore.getKey(KEYSTORE_ALIAS, null) as? SecretKey
            ?: throw IllegalStateException("Keystore biometric key '$KEYSTORE_ALIAS' not found.")

        val iv = ByteArray(GCM_IV_LENGTH)
        System.arraycopy(wrappedBytes, 0, iv, 0, GCM_IV_LENGTH)
        val ciphertext = ByteArray(wrappedBytes.size - GCM_IV_LENGTH)
        System.arraycopy(wrappedBytes, GCM_IV_LENGTH, ciphertext, 0, ciphertext.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
        return cipher.doFinal(ciphertext)
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
    // OUTGOING SHARING (STRICTLY SCOPED TO SHARED_EXPORTS)
    // =========================================================================

    private fun handleShareFiles(call: MethodCall, result: MethodChannel.Result) {
        val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()
        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: emptyList()
        val title = call.argument<String>("title") ?: "Share via SafeVault"

        if (filePaths.isEmpty()) {
            result.error("INVALID_ARGS", "filePaths must not be empty", null)
            return
        }

        try {
            val exportDirCanonical = File(cacheDir, "shared_exports").canonicalPath
            val uris = ArrayList<Uri>()

            for (path in filePaths) {
                val file = File(path).canonicalFile
                // Enforce that only files inside shared_exports directory can be shared
                if (!file.canonicalPath.startsWith(exportDirCanonical)) {
                    result.error(
                        "ACCESS_DENIED",
                        "Security violation: Only files inside shared_exports directory may be shared.",
                        null
                    )
                    return
                }

                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "Shared file does not exist: ${file.name}", null)
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
    // INCOMING SHARE HANDLING (HARDENED VALIDATION & SIZE LIMITS)
    // =========================================================================

    private fun processIncomingIntent(intent: Intent, isNew: Boolean) {
        val action = intent.action ?: return

        if (Intent.ACTION_SEND != action && Intent.ACTION_SEND_MULTIPLE != action) {
            return
        }

        val incomingUris = mutableListOf<Uri>()

        if (Intent.ACTION_SEND == action) {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
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
            val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
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
                safChannel?.invokeMethod("onIncomingShareReceived", staged)
            }
        }
    }

    private fun stageUrisToCache(uris: List<Uri>, prefix: String): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val stagingDir = File(cacheDir, "staging").apply { if (!exists()) mkdirs() }
        var totalBytesAccumulated = 0L

        // Limit file count to prevent resource exhaustion attacks
        val safeUris = uris.take(MAX_FILE_COUNT)

        for (uri in safeUris) {
            // Validate URI scheme
            val scheme = uri.scheme?.lowercase()
            if (scheme != "content" && scheme != "file") {
                continue
            }

            var targetFile: File? = null
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

                // Check size upfront if available
                if (fileSize > MAX_FILE_SIZE_BYTES || (totalBytesAccumulated + fileSize) > MAX_TOTAL_SIZE_BYTES) {
                    continue
                }

                // Sanitize display name (strip path traversal attempts)
                val sanitizedName = File(displayName).name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                val extension = when {
                    sanitizedName.contains('.') -> sanitizedName.substringAfterLast('.').lowercase()
                    mimeType.contains("pdf") -> "pdf"
                    mimeType.contains("png") -> "png"
                    else -> "jpg"
                }

                val safeFileName = "${prefix}_${UUID.randomUUID()}.$extension"
                targetFile = File(stagingDir, safeFileName)

                // Inspect stream: validate magic byte signatures
                contentResolver.openInputStream(uri)?.use { inputStream ->
                    val header = ByteArray(8)
                    val headerBytesRead = inputStream.read(header)
                    if (headerBytesRead < 4) {
                        return@use
                    }

                    // Magic byte signatures:
                    // PDF: %PDF- (0x25, 0x50, 0x44, 0x46)
                    // JPEG: 0xFF, 0xD8, 0xFF
                    // PNG: 0x89, 0x50, 0x4E, 0x47
                    val isPdf = header[0] == 0x25.toByte() && header[1] == 0x50.toByte() && header[2] == 0x44.toByte() && header[3] == 0x46.toByte()
                    val isJpeg = header[0] == 0xFF.toByte() && header[1] == 0xD8.toByte() && header[2] == 0xFF.toByte()
                    val isPng = header[0] == 0x89.toByte() && header[1] == 0x50.toByte() && header[2] == 0x4E.toByte() && header[3] == 0x47.toByte()

                    if (!isPdf && !isJpeg && !isPng) {
                        // File signature does not match allowed types
                        return@use
                    }

                    FileOutputStream(targetFile).use { outputStream ->
                        outputStream.write(header, 0, headerBytesRead)
                        var bytesWritten = headerBytesRead.toLong()

                        val buffer = ByteArray(8192)
                        var read: Int
                        while (inputStream.read(buffer).also { read = it } != -1) {
                            bytesWritten += read
                            if (bytesWritten > MAX_FILE_SIZE_BYTES || (totalBytesAccumulated + bytesWritten) > MAX_TOTAL_SIZE_BYTES) {
                                throw IllegalStateException("File size limit exceeded.")
                            }
                            outputStream.write(buffer, 0, read)
                        }
                        outputStream.flush()
                        totalBytesAccumulated += bytesWritten
                    }
                }

                if (targetFile.exists() && targetFile.length() > 0) {
                    val finalSize = targetFile.length()
                    result.add(
                        mapOf(
                            "path" to targetFile.absolutePath,
                            "name" to sanitizedName,
                            "size" to finalSize,
                            "mimeType" to mimeType
                        )
                    )
                } else {
                    targetFile.delete()
                }
            } catch (e: Exception) {
                // Clean up partial file on failure
                targetFile?.delete()
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
            val exportDir = File(cacheDir, "shared_exports")
            if (exportDir.exists()) {
                exportDir.listFiles()?.forEach { it.delete() }
            }
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
