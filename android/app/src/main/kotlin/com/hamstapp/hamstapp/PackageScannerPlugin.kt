package com.hamstapp.hamstapp

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import jcifs.CIFSContext
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbException
import jcifs.smb.SmbFile
import org.apache.commons.net.ftp.FTPClient
import org.apache.commons.net.ftp.FTPFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Properties
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Native bridge that scans installed packages on a background thread.
 *
 * Only lightweight metadata is returned in the bulk scan so that a device with
 * 1000+ installed packages finishes well within the 30s budget. Icons are
 * fetched lazily (only for rows that are actually rendered) and cached.
 */
class PackageScannerPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newFixedThreadPool(4)
    private val iconCache = ConcurrentHashMap<String, ByteArray>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> {
                val includeSystem = call.argument<Boolean>("includeSystem") ?: true
                executor.execute {
                    try {
                        val apps = scanApps(includeSystem)
                        mainHandler.post { result.success(apps) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("SCAN_FAILED", t.message, null) }
                    }
                }
            }
            "getAppIcon" -> {
                val pkg = call.argument<String>("packageName")
                val size = call.argument<Int>("size") ?: 144
                if (pkg == null) {
                    result.error("BAD_ARGS", "packageName is required", null)
                    return
                }
                val cacheKey = "$pkg@$size"
                iconCache[cacheKey]?.let {
                    result.success(it)
                    return
                }
                executor.execute {
                    try {
                        val bytes = loadIcon(pkg, size)
                        if (bytes != null) iconCache[cacheKey] = bytes
                        mainHandler.post { result.success(bytes) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("ICON_FAILED", t.message, null) }
                    }
                }
            }
            "launchApp" -> {
                val pkg = call.argument<String>("packageName")
                mainHandler.post { result.success(pkg != null && launchApp(pkg)) }
            }
            "openAppInfo" -> {
                val pkg = call.argument<String>("packageName")
                mainHandler.post { result.success(pkg != null && openAppInfo(pkg)) }
            }
            "uninstallApp" -> {
                val pkg = call.argument<String>("packageName")
                mainHandler.post { result.success(pkg != null && requestUninstall(pkg)) }
            }
            "getDeviceInfo" -> {
                executor.execute {
                    val info = mapOf(
                        "model" to android.os.Build.MODEL,
                        "manufacturer" to android.os.Build.MANUFACTURER,
                        "androidVersion" to android.os.Build.VERSION.RELEASE,
                        "sdkInt" to android.os.Build.VERSION.SDK_INT
                    )
                    mainHandler.post { result.success(info) }
                }
            }
            "remoteTest" -> {
                val config = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                executor.execute {
                    try {
                        val list = listRemoteApks(config)
                        mainHandler.post {
                            result.success(mapOf("ok" to true, "count" to list.size))
                        }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.success(mapOf("ok" to false, "error" to describe(t)))
                        }
                    }
                }
            }
            "remoteList" -> {
                val config = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                executor.execute {
                    try {
                        val list = listRemoteApks(config)
                        mainHandler.post { result.success(list) }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("REMOTE_FAILED", describe(t), null)
                        }
                    }
                }
            }
            "remoteDownload" -> {
                val config = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                executor.execute {
                    try {
                        val local = downloadRemoteFile(config)
                        mainHandler.post { result.success(local) }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("DOWNLOAD_FAILED", describe(t), null)
                        }
                    }
                }
            }
            "installApk" -> {
                val path = call.argument<String>("path")
                mainHandler.post { result.success(path != null && installApk(path)) }
            }
            else -> result.notImplemented()
        }
    }

    private fun scanApps(includeSystem: Boolean): List<Map<String, Any?>> {
        val pm = context.packageManager
        val packages: List<PackageInfo> = pm.getInstalledPackages(0)
        val out = ArrayList<Map<String, Any?>>(packages.size)
        for (info in packages) {
            val app = info.applicationInfo ?: continue
            val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (!includeSystem && isSystem) continue

            val label = runCatching { app.loadLabel(pm).toString() }.getOrDefault(info.packageName)
            val sourceDir = app.sourceDir
            val sizeBytes = if (sourceDir != null) File(sourceDir).length() else 0L

            out.add(
                mapOf(
                    "packageName" to info.packageName,
                    "appName" to label,
                    "versionName" to (info.versionName ?: ""),
                    "versionCode" to (if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()),
                    "firstInstallTime" to info.firstInstallTime,
                    "lastUpdateTime" to info.lastUpdateTime,
                    "isSystem" to isSystem,
                    "enabled" to app.enabled,
                    "apkPath" to (sourceDir ?: ""),
                    "sizeBytes" to sizeBytes,
                    "targetSdk" to app.targetSdkVersion,
                    "minSdk" to app.minSdkVersion,
                    "uid" to app.uid
                )
            )
        }
        return out
    }

    private fun loadIcon(packageName: String, sizePx: Int): ByteArray? {
        val pm = context.packageManager
        val drawable: Drawable = runCatching {
            pm.getApplicationIcon(packageName)
        }.getOrNull() ?: return null
        val bitmap = drawableToBitmap(drawable, sizePx)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        bitmap.recycle()
        return stream.toByteArray()
    }

    private fun drawableToBitmap(drawable: Drawable, sizePx: Int): Bitmap {
        val size = if (sizePx <= 0) 144 else sizePx
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            val src = drawable.bitmap
            if (src.width <= size && src.height <= size) return src
            return Bitmap.createScaledBitmap(src, size, size, true)
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return bitmap
    }

    private fun launchApp(packageName: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    private fun openAppInfo(packageName: String): Boolean {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    private fun requestUninstall(packageName: String): Boolean {
        val intent = Intent(Intent.ACTION_DELETE).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    // ---------------------------------------------------------------- remote

    private fun strArg(m: Map<*, *>, key: String, def: String = ""): String {
        val v = m[key]
        return if (v is String && v.isNotEmpty()) v else def
    }

    private fun intArg(m: Map<*, *>, key: String, def: Int): Int {
        val v = m[key]
        return if (v is Number) v.toInt() else def
    }

    private fun boolArg(m: Map<*, *>, key: String): Boolean =
        m[key] as? Boolean ?: false

    /**
     * Full cause chain plus any SMB NT status, joined with " | ".
     *
     * jcifs wraps the useful details: the outer message is often a generic
     * "Session setup failed" while the real NT status (LOGON_FAILURE, bad
     * password, ...) lives on a nested SmbException. Surfacing it makes the
     * error actionable.
     */
    private fun describe(t: Throwable): String {
        val parts = ArrayList<String>()
        var cur: Throwable? = t
        val seen = HashSet<Throwable>()
        while (cur != null && seen.add(cur)) {
            val m = cur.message
            if (!m.isNullOrBlank() && !parts.contains(m)) parts.add(m)
            if (cur is SmbException) {
                val code = runCatching { cur.ntStatus }.getOrDefault(0)
                if (code != 0) {
                    val hex = "0x" + Integer.toHexString(code).uppercase()
                    val hint = ntStatusHint(code)
                    val extra = if (hint.isEmpty()) hex else "$hex $hint"
                    if (!parts.contains(extra)) parts.add(extra)
                }
            }
            cur = cur.cause?.takeIf { it !== cur }
        }
        return if (parts.isEmpty()) t.javaClass.simpleName else parts.joinToString(" | ")
    }

    /** Friendly text for the SMB NT status codes users hit most often. */
    private fun ntStatusHint(code: Int): String =
        when (code.toLong() and 0xFFFFFFFFL) {
            0xC000006DL -> "账号或密码错误"
            0xC000006AL -> "密码错误"
            0xC0000064L -> "用户名不存在"
            0xC000006EL -> "账户限制"
            0xC000006FL, 0xC0000070L, 0xC0000072L -> "账户被禁用或锁定"
            0xC000015BL -> "登录类型不被允许"
            0xC0000071L -> "密码已过期"
            else -> ""
        }

    /** How many directory levels deep the APK scan will descend. */
    private val maxScanDepth = 6

    /**
     * Real APK files only: skip hidden/dot entries (`.thumbnails`, macOS `._`
     * resource forks, ...) and anything that is not an `.apk`.
     */
    private fun isApkName(name: String): Boolean =
        !name.startsWith(".") && name.lowercase().endsWith(".apk")

    private fun apkEntry(
        name: String,
        rel: String,
        path: String,
        size: Long,
        modified: Long
    ): Map<String, Any?> = mapOf(
        "name" to name,
        "rel" to rel,
        "path" to path,
        "size" to size,
        "modified" to modified
    )

    /** Lists `.apk` files from an FTP or SMB (Samba) source, recursively. */
    private fun listRemoteApks(config: Map<*, *>): List<Map<String, Any?>> {
        val protocol = strArg(config, "protocol", "ftp").lowercase()
        return if (protocol == "smb" || protocol == "samba") {
            listSmb(config)
        } else {
            listFtp(config)
        }
    }

    private fun listFtp(config: Map<*, *>): List<Map<String, Any?>> {
        val host = strArg(config, "host")
        require(host.isNotEmpty()) { "主机不能为空" }
        val port = intArg(config, "port", 21).let { if (it <= 0) 21 else it }
        val anonymous = boolArg(config, "anonymous")
        val user = if (anonymous) "anonymous" else strArg(config, "username")
        val pass = if (anonymous) "anonymous@" else strArg(config, "password")
        val dirInput = strArg(config, "path", "/").ifEmpty { "/" }
        val root = if (dirInput.endsWith("/")) dirInput else "$dirInput/"

        val ftp = FTPClient()
        ftp.connectTimeout = 10000
        ftp.defaultTimeout = 20000
        try {
            ftp.connect(host, port)
            if (!ftp.login(user, pass)) {
                throw IllegalStateException("FTP 登录失败，请检查账号或匿名设置")
            }
            ftp.enterLocalPassiveMode()
            ftp.setFileType(FTPClient.BINARY_FILE_TYPE)
            val out = ArrayList<Map<String, Any?>>()
            val visited = HashSet<String>()
            fun walk(current: String, rel: String, depth: Int) {
                if (depth > maxScanDepth || !visited.add(current)) return
                val files = runCatching { ftp.listFiles(current) }.getOrNull() ?: return
                for (f in files) {
                    if (f == null) continue
                    val name = f.name ?: continue
                    if (name == "." || name == ".." || name.startsWith(".")) continue
                    val full = current + name
                    val childRel = if (rel.isEmpty()) name else "$rel/$name"
                    if (f.isDirectory) {
                        walk("$full/", childRel, depth + 1)
                    } else if (name.lowercase().endsWith(".apk")) {
                        out.add(
                            apkEntry(
                                name, childRel, full, f.size,
                                f.timestamp?.timeInMillis ?: 0L
                            )
                        )
                    }
                }
            }
            walk(root, "", 0)
            out.sortBy { it["rel"] as String }
            return out
        } finally {
            runCatching { ftp.logout() }
            runCatching { ftp.disconnect() }
        }
    }

    /**
     * Builds a jcifs context (with timeouts/protocol/dialect tuned for NAS).
     * Returns the base context (to close) and the credential-bound context.
     */
    private fun buildSmbContext(config: Map<*, *>): Pair<BaseContext, CIFSContext> {
        val port = intArg(config, "port", 445).let { if (it <= 0) 445 else it }
        val anonymous = boolArg(config, "anonymous")
        val user = strArg(config, "username")
        val pass = strArg(config, "password")
        val domain = strArg(config, "domain")

        val props = Properties()
        // Resolve hostnames with DNS only: WINS/NetBIOS broadcast lookups are
        // what usually makes SMB "hang" then fail on Android.
        props.setProperty("jcifs.resolveOrder", "DNS")
        // Support old SMB1-only NAS through SMB 3.1.1.
        props.setProperty("jcifs.smb.client.minVersion", "SMB1")
        props.setProperty("jcifs.smb.client.maxVersion", "SMB311")
        // Bound the connection so a wrong host/port fails fast instead of hanging.
        props.setProperty("jcifs.smb.client.connTimeout", "15000")
        props.setProperty("jcifs.smb.client.responseTimeout", "30000")
        props.setProperty("jcifs.smb.client.soTimeout", "35000")
        props.setProperty("jcifs.smb.client.dfs.disabled", "true")
        // NTLMv2 only, matching what modern Samba/Windows/NAS expect.
        props.setProperty("jcifs.smb.lmCompatibility", "3")
        props.setProperty("jcifs.smb.client.useUnicode", "true")
        if (port != 445) props.setProperty("jcifs.smb.client.port", port.toString())

        val base = BaseContext(PropertyConfiguration(props))
        val ctx = if (anonymous) {
            base.withAnonymousCredentials()
        } else {
            // A blank domain is fine for Samba local users; Windows local
            // accounts / domains need it ("WORKGROUP", "NAS\user", ...).
            base.withCredentials(NtlmPasswordAuthenticator(domain, user, pass))
        }
        return base to ctx
    }

    private fun listSmb(config: Map<*, *>): List<Map<String, Any?>> {
        val host = strArg(config, "host")
        require(host.isNotEmpty()) { "主机不能为空" }
        val port = intArg(config, "port", 445).let { if (it <= 0) 445 else it }
        val path = strArg(config, "path").trim('/')
        require(path.isNotEmpty()) { "请填写共享路径，例如 share/apks" }
        val portPart = if (port != 445) ":$port" else ""

        val (base, ctx) = buildSmbContext(config)
        try {
            val root = SmbFile("smb://$host$portPart/$path/", ctx)
            val out = ArrayList<Map<String, Any?>>()
            fun walk(dir: SmbFile, rel: String, depth: Int) {
                if (depth > maxScanDepth) return
                val children = dir.listFiles() ?: return
                for (c in children) {
                    if (c == null) continue
                    val name = c.name?.trimEnd('/') ?: continue
                    if (name.isEmpty() || name == "." || name == ".." ||
                        name.startsWith(".")
                    ) {
                        continue
                    }
                    val childRel = if (rel.isEmpty()) name else "$rel/$name"
                    if (c.isDirectory) {
                        walk(c, childRel, depth + 1)
                    } else if (name.lowercase().endsWith(".apk")) {
                        out.add(
                            apkEntry(
                                name, childRel, "$path/$childRel",
                                c.length(), c.lastModified()
                            )
                        )
                    }
                }
            }
            walk(root, "", 0)
            out.sortBy { it["rel"] as String }
            return out
        } finally {
            runCatching { base.close() }
        }
    }

    // ------------------------------------------------------------ download/install

    /**
     * Downloads one remote file into the app cache and returns its local path.
     * `remotePath` is the per-file path produced by the listing.
     */
    private fun downloadRemoteFile(config: Map<*, *>): String {
        val remotePath = strArg(config, "remotePath")
        require(remotePath.isNotEmpty()) { "缺少远程文件路径" }
        val protocol = strArg(config, "protocol", "ftp").lowercase()

        val name = strArg(config, "name").ifEmpty { remotePath.substringAfterLast('/') }
        val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_").ifEmpty { "download.apk" }
        val dir = File(context.cacheDir, "apk_downloads")
        if (!dir.exists()) dir.mkdirs()
        val target = File(dir, safe)

        if (protocol == "smb" || protocol == "samba") {
            downloadSmb(config, remotePath, target)
        } else {
            downloadFtp(config, remotePath, target)
        }
        return target.absolutePath
    }

    private fun downloadFtp(config: Map<*, *>, remotePath: String, target: File) {
        val host = strArg(config, "host")
        val port = intArg(config, "port", 21).let { if (it <= 0) 21 else it }
        val anonymous = boolArg(config, "anonymous")
        val user = if (anonymous) "anonymous" else strArg(config, "username")
        val pass = if (anonymous) "anonymous@" else strArg(config, "password")

        val ftp = FTPClient()
        ftp.connectTimeout = 10000
        ftp.defaultTimeout = 20000
        try {
            ftp.connect(host, port)
            if (!ftp.login(user, pass)) throw IllegalStateException("FTP 登录失败")
            ftp.enterLocalPassiveMode()
            ftp.setFileType(FTPClient.BINARY_FILE_TYPE)
            val ok = target.outputStream().use { ftp.retrieveFile(remotePath, it) }
            if (!ok) throw IllegalStateException("下载失败：$remotePath")
        } finally {
            runCatching { ftp.logout() }
            runCatching { ftp.disconnect() }
        }
    }

    private fun downloadSmb(config: Map<*, *>, remotePath: String, target: File) {
        val host = strArg(config, "host")
        val port = intArg(config, "port", 445).let { if (it <= 0) 445 else it }
        val portPart = if (port != 445) ":$port" else ""
        val (base, ctx) = buildSmbContext(config)
        try {
            val remote = SmbFile("smb://$host$portPart/$remotePath", ctx)
            remote.openInputStream().use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
        } finally {
            runCatching { base.close() }
        }
    }

    /** Opens the system package installer for a downloaded APK (FileProvider). */
    private fun installApk(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (t: Throwable) {
            false
        }
    }
}
