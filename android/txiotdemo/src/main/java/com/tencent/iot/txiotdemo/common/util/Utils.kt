package com.tencent.iot.txiotdemo.common.util

import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.os.Build
import android.os.LocaleList
import android.provider.Settings
import android.text.TextUtils
import com.tencent.iot.txiotdemo.common.log.L
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.Locale

object Utils {

    private fun isDigitsOnly(src: String): Boolean {
        val flag = src.toIntOrNull()
        return flag != null
    }

    fun getFirstSeriesNumFromStr(src: String): Int {
        if (TextUtils.isEmpty(src)) {
            return 0
        }
        var start = -1
        var end = -1
        for ((i, item) in src.withIndex()) {
            if (isDigitsOnly(item.toString()) && start < 0) {
                start = i
            } else if (!isDigitsOnly(item.toString()) && start >= 0) {
                end = i
                break
            }
        }

        val retStr: String
        if (start < 0 && end < 0) {
            return 0
        } else if (start >= 0 && end < 0) {
            retStr = src.substring(start)
        } else {
            retStr = src.substring(start, end)
        }

        if (isDigitsOnly(retStr)) {
            return retStr.toInt()
        }

        return 0
    }

    fun getLang(): String {
        var local: Locale?

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            local = LocaleList.getDefault().get(0)
        } else {
            local = Locale.getDefault()
        }

        if (local == null) {
            L.d("getLang return default lang(zh-CN)")
            return "zh-CN"
        }

        var ret = local.language.toString() + "-" + local.country.toString()
        return ret
    }

    fun getUrlParamValue(url: String, name: String?): String? {
        val paramsStr = url.substring(url.indexOf("?") + 1, url.length)
        val split: MutableMap<String, String> = hashMapOf()
        val params = paramsStr.split("&")
        for (paramKV in params) {
            val kv = paramKV.split("=")
            if (kv.size == 2) {
                split[kv[0]] = kv[1]
            }
        }
        return split[name]
    }

    interface SecondsCountDownCallback {
        fun currentSeconds(seconds: Int)
        fun countDownFinished()
    }

    fun startCountBySeconds(max: Int, secondsCountDownCallback: SecondsCountDownCallback) {
        startCountBySeconds(max, 1, secondsCountDownCallback)
    }

    private fun startCountBySeconds(
        max: Int,
        step: Int,
        secondsCountDownCallback: SecondsCountDownCallback
    ) {
        if (max <= 0) return
        Thread { runCountdown(max, step, secondsCountDownCallback) }.start()
    }

    private fun runCountdown(max: Int, step: Int, callback: SecondsCountDownCallback) {
        var countDown = 0
        callback.currentSeconds(max - countDown)
        while (countDown < max) {
            countDown += step
            Thread.sleep(step.toLong() * 1000)
            callback.currentSeconds(max - countDown)
        }
        callback.countDownFinished()
    }

    fun getStringValueFromXml(context: Context, xmlName: String, keyName: String): String? {
        val dataSp = context.getSharedPreferences(xmlName, Context.MODE_PRIVATE)
        return dataSp.getString(keyName, null)
    }

    fun setXmlStringValue(context: Context, xmlName: String, keyName: String, value: String) {
        val dataSp = context.getSharedPreferences(xmlName, Context.MODE_PRIVATE)
        val editor = dataSp.edit()
        if (!TextUtils.isEmpty(value)) {
            editor.putString(keyName, value)
        } else {
            editor.remove(keyName)
        }
        editor.commit()
    }

    fun clearXmlStringValue(context: Context, xmlName: String, keyName: String) {
        setXmlStringValue(context, xmlName, keyName, "")
    }

    fun copy(context: Context, data: String?) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clipData = ClipData.newPlainText(null, data)
        clipboard.setPrimaryClip(clipData)
    }

    fun isChineseSystem(context: Context): Boolean {
        return context.resources.configuration.locale.language == "zh"
    }

    fun getAndroidID(context: Context): String {
        val id = Settings.System.getString(context.contentResolver, Settings.System.ANDROID_ID)
        return if (TextUtils.isEmpty(id)) ""
        else id
    }

    fun bmpToByteArray(bitmap: Bitmap?): ByteArray? {

        var reslut: ByteArray? = null
        var baos: ByteArrayOutputStream? = null
        try {
            if (bitmap != null) {
                baos = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 100, baos)
                baos.flush()
                baos.close()
                reslut = baos.toByteArray()
            } else {
                return null
            }
        } catch (e: IOException) {
            e.printStackTrace()
        } finally {
            try {
                if (baos != null) {
                    baos.close()
                }
            } catch (e: IOException) {
                e.printStackTrace()
            }
        }
        return reslut
    }

    fun getBitmap(context: Context, vectorDrawableId: Int): Bitmap? {
        var bitmap: Bitmap? = null
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.LOLLIPOP) {
            val vectorDrawable = context.getDrawable(vectorDrawableId)
            bitmap = Bitmap.createBitmap(
                vectorDrawable!!.intrinsicWidth,
                vectorDrawable.intrinsicHeight, Bitmap.Config.ARGB_8888
            )
            val canvas = Canvas(bitmap)
            vectorDrawable.setBounds(0, 0, canvas.width, canvas.height)
            vectorDrawable.draw(canvas)
        } else {
            bitmap = BitmapFactory.decodeResource(context.resources, vectorDrawableId)
        }
        return bitmap
    }

    fun clearMsgNotify(context: Context, noticeId: Int) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(noticeId)
    }

    fun bytesToHexString(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (i in bytes.indices) {
            val hex = Integer.toHexString(0xFF and bytes[i].toInt())
            if (hex.length == 1) {
                sb.append('0')
            }
            sb.append(hex)
        }
        return sb.toString()
    }

    fun dp2px(context: Context, dp: Int): Int {
        return (context.resources.displayMetrics.density * dp + 0.5).toInt()
    }

    fun saveImageToGallery(context: Context, bitmap: Bitmap): Boolean {
        val fileName = "snapshot_${System.currentTimeMillis()}.jpg"
        val contentValues = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(
                android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                "${android.os.Environment.DIRECTORY_PICTURES}/IoTCamera"
            )
            put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(
            android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            contentValues
        )
            ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            }
            contentValues.clear()
            contentValues.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
            L.e("Screenshot saved to gallery: $uri")
            true
        } catch (e: Exception) {
            L.e("Screenshot save failed: ${e.message}")
            resolver.delete(uri, null, null)
            false
        }
    }

    fun saveVideoToGallery(context: Context, filePath: String) {
        val file = java.io.File(filePath)
        if (!file.exists()) {
            L.e("Video file not found: $filePath")
            return
        }
        val fileName = "record_${System.currentTimeMillis()}.mp4"
        val contentValues = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Video.Media.DISPLAY_NAME, fileName)
            put(android.provider.MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(
                android.provider.MediaStore.Video.Media.RELATIVE_PATH,
                "${android.os.Environment.DIRECTORY_MOVIES}/IoTCamera"
            )
            put(android.provider.MediaStore.Video.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(
            android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            contentValues
        )
        if (uri == null) {
            L.e("Video insert into media store failed")
            return
        }
        try {
            resolver.openOutputStream(uri)?.use { out ->
                java.io.FileInputStream(file).use { it.copyTo(out) }
            }
            contentValues.clear()
            contentValues.put(android.provider.MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
            L.e("Video saved to gallery: $uri")
        } catch (e: Exception) {
            L.e("Video save failed: ${e.message}")
            resolver.delete(uri, null, null)
        }
    }
}
