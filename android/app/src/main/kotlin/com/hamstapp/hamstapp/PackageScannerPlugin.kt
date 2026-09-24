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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import jcifs.CIFSContext
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtlmPasswordAuthenticator
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
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "error" to (t.message ?: t.toString())
                                )
                            )
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
                            result.error("REMOTE_FAILED", t.message ?: t.toString(), null)
                        }
                    }
                }
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

    /** Lists `.apk` files from an FTP or SMB (Samba) source. */
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
        val dir = strArg(config, "path", "/").ifEmpty { "/" }

        val ftp = FTPClient()
        ftp.connectTimeout = 10000
        ftp.defaultTimeout = 15000
        try {
            ftp.connect(host, port)
            if (!ftp.login(user, pass)) {
                throw IllegalStateException("FTP 登录失败，请检查账号或匿名设置")
            }
            ftp.enterLocalPassiveMode()
            ftp.setFileType(FTPClient.BINARY_FILE_TYPE)
            val files = ftp.listFiles(dir) ?: emptyArray<FTPFile>()
            val out = ArrayList<Map<String, Any?>>()
            for (f in files) {
                if (f == null || f.isDirectory) continue
                val name = f.name ?: continue
                if (!name.lowercase().endsWith(".apk")) continue
                out.add(
                    mapOf(
                        "name" to name,
                        "size" to f.size,
                        "path" to (dir.trimEnd('/') + "/" + name),
                        "modified" to (f.timestamp?.timeInMillis ?: 0L)
                    )
                )
            }
            out.sortBy { it["name"] as String }
            return out
        } finally {
            runCatching { ftp.logout() }
            runCatching { ftp.disconnect() }
        }
    }

    private fun listSmb(config: Map<*, *>): List<Map<String, Any?>> {
        val host = strArg(config, "host")
        require(host.isNotEmpty()) { "主机不能为空" }
        val port = intArg(config, "port", 445).let { if (it <= 0) 445 else it }
        val anonymous = boolArg(config, "anonymous")
        val user = strArg(config, "username")
        val pass = strArg(config, "password")
        val path = strArg(config, "path").trim('/')
        require(path.isNotEmpty()) { "请填写共享路径，例如 share/apks" }

        val props = Properties()
        if (port != 445) props.setProperty("jcifs.smb.client.port", port.toString())
        val base = BaseContext(PropertyConfiguration(props))
        val ctx: CIFSContext = if (anonymous) {
            base.withAnonymousCredentials()
        } else {
            base.withCredentials(NtlmPasswordAuthenticator("", user, pass))
        }
        val dir = SmbFile("smb://$host/$path/", ctx)
        val children = dir.listFiles() ?: emptyArray<SmbFile>()
        val out = ArrayList<Map<String, Any?>>()
        for (f in children) {
            if (f == null || f.isDirectory) continue
            val name = f.name ?: continue
            if (!name.lowercase().endsWith(".apk")) continue
            out.add(
                mapOf(
                    "name" to name,
                    "size" to f.length(),
                    "path" to "$path/$name",
                    "modified" to f.lastModified()
                )
            )
        }
        out.sortBy { it["name"] as String }
        return out
    }
}
