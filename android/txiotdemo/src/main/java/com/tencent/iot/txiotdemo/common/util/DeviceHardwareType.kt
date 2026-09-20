package com.tencent.iot.txiotdemo.common.util

import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo

enum class DeviceHardwareType {
    CAMERA,
    CEILING_LAMP
}

object DeviceHardwareRegistry {

    private val ceilingLampProductIds = setOf(
        "988BYEG00X"
    )

    fun hardwareTypeFor(productId: String?): DeviceHardwareType =
        if (productId != null && ceilingLampProductIds.contains(productId)) {
            DeviceHardwareType.CEILING_LAMP
        } else {
            DeviceHardwareType.CAMERA
        }
}

val TXIoTDeviceInfo.hardwareType: DeviceHardwareType
    get() = DeviceHardwareRegistry.hardwareTypeFor(deviceId?.productId)

val TXIoTDeviceInfo.isCeilingLamp: Boolean
    get() = hardwareType == DeviceHardwareType.CEILING_LAMP
