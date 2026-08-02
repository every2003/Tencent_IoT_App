package com.tencent.iot.txiotdemo.common.util

import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceId
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceStatus
import org.json.JSONObject

object DeviceJsonUtils {

    fun toJson(device: TXIoTDeviceInfo): String {
        val json = JSONObject()
        device.deviceId?.let { did ->
            val didJson = JSONObject()
            did.productId?.let { didJson.put("productId", it) }
            did.deviceName?.let { didJson.put("deviceName", it) }
            json.put("deviceId", didJson)
        }
        device.aliasName?.let { json.put("aliasName", it) }
        device.familyId?.let { json.put("familyId", it) }
        device.roomId?.let { json.put("roomId", it) }
        device.iconUrl?.let { json.put("iconUrl", it) }
        json.put("createTime", device.createTime)
        json.put("updateTime", device.updateTime)
        device.status?.let { st ->
            val stJson = JSONObject()
            stJson.put("isOnline", st.isOnline)
            stJson.put("onlineDuration", st.onlineDuration)
            stJson.put("bringOnlineTime", st.bringOnlineTime)
            json.put("status", stJson)
        }
        return json.toString()
    }

    fun fromJson(json: String): TXIoTDeviceInfo? {
        return try {
            val obj = JSONObject(json)
            TXIoTDeviceInfo().apply {
                obj.optJSONObject("deviceId")?.let { did ->
                    deviceId = TXIoTDeviceId().apply {
                        productId = did.optStringOrNull("productId")
                        deviceName = did.optStringOrNull("deviceName")
                    }
                }
                aliasName = obj.optStringOrNull("aliasName")
                familyId = obj.optStringOrNull("familyId")
                roomId = obj.optStringOrNull("roomId")
                iconUrl = obj.optStringOrNull("iconUrl")
                createTime = obj.optLong("createTime")
                updateTime = obj.optLong("updateTime")
                obj.optJSONObject("status")?.let { st ->
                    status = TXIoTDeviceStatus().apply {
                        isOnline = st.optBoolean("isOnline")
                        onlineDuration = st.optLong("onlineDuration")
                        bringOnlineTime = st.optLong("bringOnlineTime")
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) optString(key) else null
}
