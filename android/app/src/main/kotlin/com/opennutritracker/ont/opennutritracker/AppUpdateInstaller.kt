package com.opennutritracker.ont.opennutritracker

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object AppUpdateInstaller {
    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val certificates = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else info.signatures
        return certificates?.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }
            ?.toSet() ?: emptySet()
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

    @Suppress("DEPRECATION")
    suspend fun install(activity: Activity, call: MethodCall): String {
        val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
        val code = requireNotNull(call.argument<Number>("versionCode")).toLong()
        val expectedHash = requireNotNull(call.argument<String>("sha256"))
        withContext(Dispatchers.IO) {
            val directory = File(activity.cacheDir, "app-updates").canonicalFile
            require(file.parentFile == directory && file.extension == "apk" && file.isFile)
            require(file.length() in 1..(160L * 1024 * 1024))
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            require(hex(digest.digest()) == expectedHash)
            val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
                else PackageManager.GET_SIGNATURES
            val manager = activity.packageManager
            val archive = requireNotNull(manager.getPackageArchiveInfo(file.path, flags))
            val installed = manager.getPackageInfo(activity.packageName, flags)
            require(archive.packageName == activity.packageName)
            require(version(archive) == code && code > version(installed))
            val expectedSigners = signers(installed)
            require(expectedSigners.isNotEmpty() && signers(archive) == expectedSigners)
        }
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + activity.packageName)))
            return "permission_required"
        }
        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".updates", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        return "opened"
    }
}
