package com.tencent.iot.txiotdemo.activity

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.util.DeviceJsonUtils
import com.tencent.iot.txiotdemo.databinding.IotActivityLampDetailBinding
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngine.TXIoTEngineListener
import com.tencent.liteav.iot.TXIoTEngine.TXIoTPushMessage
import com.tencent.liteav.iot.TXIoTEngine.TXIoTPushMessageSubType
import com.tencent.liteav.iot.TXIoTEngine.TXIoTPushMessageType
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTCallback
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceId
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTErrorCode
import org.json.JSONObject

class LampDetailActivity : BaseActivity<IotActivityLampDetailBinding>() {

    companion object {
        private const val EXTRA_DEVICE_INFO = "deviceInfo"

        fun start(context: Context, device: TXIoTDeviceInfo) {
            val intent = Intent(context, LampDetailActivity::class.java).apply {
                putExtra(EXTRA_DEVICE_INFO, DeviceJsonUtils.toJson(device))
            }
            context.startActivity(intent)
        }
    }

    private var deviceInfo: TXIoTDeviceInfo? = null

    private var powerOn = false
    private var brightness = 80
    private var colorTemp = 4000
    private var lightMode = 0
    private var isOnline = false
    private var suppressSeekCallback = false

    private val iotEngineListener = object : TXIoTEngineListener() {
        override fun onReceivePushMessage(pushMessage: TXIoTPushMessage) {
            runOnUiThread { handlePushMessage(pushMessage) }
        }
    }

    private data class ModeViews(
        val chip: LinearLayout,
        val icon: ImageView,
        val label: TextView
    )

    private val modeViews: List<ModeViews> by lazy {
        with(binding) {
            listOf(
                ModeViews(iotChipMode0, iotIvMode0, iotTvMode0),
                ModeViews(iotChipMode1, iotIvMode1, iotTvMode1),
                ModeViews(iotChipMode2, iotIvMode2, iotTvMode2),
                ModeViews(iotChipMode3, iotIvMode3, iotTvMode3)
            )
        }
    }

    override fun getViewBinding(): IotActivityLampDetailBinding =
        IotActivityLampDetailBinding.inflate(layoutInflater)

    override fun onCreate(savedInstanceState: Bundle?) {
        deviceInfo = intent.getStringExtra(EXTRA_DEVICE_INFO)?.let { DeviceJsonUtils.fromJson(it) }
        super.onCreate(savedInstanceState)
        deviceInfo?.deviceId ?: finish()
    }

    override fun initView() {
        setImmersiveStatusBar()
        isOnline = deviceInfo?.status?.isOnline == true
        binding.iotTvLampName.text = displayNameOf(deviceInfo)
        refreshPowerViews()
        updateBrightnessViews(brightness)
        updateColorTempViews(colorTemp)
        refreshModeViews()
        updateOnlineViews()
        loadProperties()
    }

    override fun setListener() {
        binding.iotBtnBack.setOnClickListener { finish() }
        binding.iotSwipeRefresh.setOnRefreshListener { loadProperties(showLoader = false) }
        binding.iotSwitchPower.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked == powerOn) return@setOnCheckedChangeListener
            powerOn = isChecked
            refreshPowerViews()
            controlProperty("power_switch", if (isChecked) 1 else 0)
        }
        binding.iotSeekBrightness.setOnSeekBarChangeListener(seekListener { value ->
            updateBrightnessViews(value)
            controlProperty("brightness", value)
        })
        binding.iotSeekColorTemp.setOnSeekBarChangeListener(seekListener { value ->
            updateColorTempViews(value)
            controlProperty("color_temp", value)
        })
        modeViews.forEachIndexed { mode, views ->
            views.chip.setOnClickListener { selectMode(mode) }
        }
    }

    override fun onStart() {
        super.onStart()
        TXIoTEngine.getInstance(this).addListener(iotEngineListener)
    }

    override fun onStop() {
        TXIoTEngine.getInstance(this).removeListener(iotEngineListener)
        super.onStop()
    }

    private fun seekListener(onStop: (Int) -> Unit) = object : SeekBar.OnSeekBarChangeListener {
        override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
            if (!fromUser) return
            if (seekBar == binding.iotSeekBrightness) updateBrightnessViews(progress + 1)
            if (seekBar == binding.iotSeekColorTemp) updateColorTempViews(2700 + progress * 100)
        }

        override fun onStartTrackingTouch(seekBar: SeekBar) {}

        override fun onStopTrackingTouch(seekBar: SeekBar) {
            if (suppressSeekCallback) return
            if (seekBar == binding.iotSeekBrightness) onStop(seekBar.progress + 1)
            if (seekBar == binding.iotSeekColorTemp) onStop(2700 + seekBar.progress * 100)
        }
    }

    private fun selectMode(mode: Int) {
        if (lightMode == mode) return
        lightMode = mode
        refreshModeViews()
        controlProperty("light_mode", mode)
    }

    private fun refreshPowerViews() {
        binding.iotTvPowerState.setText(
            if (powerOn) R.string.iot_lamp_state_on else R.string.iot_lamp_state_off
        )
        binding.iotPowerIconBg.setBackgroundResource(
            if (powerOn) R.drawable.iot_bg_lamp_power_on else R.drawable.iot_bg_lamp_power_off
        )
        binding.iotPowerIcon.setColorFilter(
            if (powerOn) Color.WHITE else Color.parseColor("#9DA3B0")
        )
        if (binding.iotSwitchPower.isChecked != powerOn) {
            binding.iotSwitchPower.isChecked = powerOn
        }
    }

    private fun updateBrightnessViews(value: Int) {
        brightness = value.coerceIn(1, 100)
        binding.iotTvBrightnessValue.text = "$brightness%"
        if (binding.iotSeekBrightness.progress != brightness - 1) {
            binding.iotSeekBrightness.progress = brightness - 1
        }
    }

    private fun updateColorTempViews(value: Int) {
        colorTemp = value.coerceIn(2700, 6500)
        binding.iotTvColorTempValue.text = "${colorTemp}K"
        val progress = (colorTemp - 2700) / 100
        if (binding.iotSeekColorTemp.progress != progress) {
            binding.iotSeekColorTemp.progress = progress
        }
    }

    private fun refreshModeViews() {
        modeViews.forEachIndexed { mode, views ->
            val selected = mode == lightMode
            views.chip.setBackgroundResource(
                if (selected) R.drawable.iot_bg_lamp_mode_selected
                else R.drawable.iot_bg_lamp_mode_unselected
            )
            val color = if (selected) Color.WHITE else Color.parseColor("#15161A")
            views.icon.setColorFilter(color)
            views.label.setTextColor(color)
        }
    }

    private fun updateOnlineViews() {
        binding.iotTvDeviceStatus.setText(
            if (isOnline) R.string.iot_device_status_online else R.string.iot_device_status_offline
        )
        binding.iotIndicatorStatus.setBackgroundResource(
            if (isOnline) R.drawable.iot_bg_status_online else R.drawable.iot_bg_status_offline
        )
        setControlsEnabled(isOnline)
    }

    private fun setControlsEnabled(enabled: Boolean) {
        with(binding) {
            iotSwitchPower.isEnabled = enabled
            iotSeekBrightness.isEnabled = enabled
            iotSeekColorTemp.isEnabled = enabled
            listOf(iotCardPower, iotCardBrightness, iotCardColorTemp, iotCardScene).forEach {
                it.alpha = if (enabled) 1f else 0.6f
            }
        }
        modeViews.forEach { it.chip.isEnabled = enabled }
    }

    private fun handlePushMessage(pushMessage: TXIoTPushMessage) {
        if (pushMessage.type != TXIoTPushMessageType.STATUS_CHANGE) return
        val did = pushMessage.deviceId ?: return
        val current = deviceInfo?.deviceId ?: return
        if (did.productId != current.productId || did.deviceName != current.deviceName) return
        isOnline = pushMessage.subType == TXIoTPushMessageSubType.ONLINE
        updateOnlineViews()
    }

    private fun loadProperties(showLoader: Boolean = true) {
        val deviceId = deviceInfo?.deviceId ?: return
        val deviceManager = TXIoTEngine.getInstance(this).deviceManager ?: run {
            show(getString(R.string.iot_lamp_get_properties_failed, ""))
            binding.iotSwipeRefresh.isRefreshing = false
            return
        }
        if (showLoader) binding.iotLoading.visibility = android.view.View.VISIBLE
        suppressSeekCallback = true
        deviceManager.getProperties(deviceId, object : TXIoTCallback<String> {
            override fun onSuccess(result: String) {
                runOnUiThread {
                    binding.iotLoading.visibility = android.view.View.GONE
                    binding.iotSwipeRefresh.isRefreshing = false
                    applyProperties(result)
                    suppressSeekCallback = false
                }
            }

            override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
                runOnUiThread {
                    binding.iotLoading.visibility = android.view.View.GONE
                    binding.iotSwipeRefresh.isRefreshing = false
                    suppressSeekCallback = false
                    show(getString(R.string.iot_lamp_get_properties_failed, errorMessage))
                }
            }
        })
    }

    private fun applyProperties(json: String) {
        val props = parseProperties(json) ?: return
        props.optIntOrNull("power_switch")?.let { powerOn = it != 0 }
        props.optIntOrNull("brightness")?.let { updateBrightnessViews(it) }
        props.optIntOrNull("color_temp")?.let { updateColorTempViews(it) }
        props.optIntOrNull("light_mode")?.let { lightMode = it.coerceIn(0, 3) }
        refreshPowerViews()
        refreshModeViews()
    }

    private fun parseProperties(json: String): JSONObject? {
        val root = try {
            JSONObject(json)
        } catch (e: Exception) {
            return null
        }
        return root.optJSONObject("properties") ?: root.optJSONObject("data") ?: root
    }

    private fun controlProperty(propertyId: String, value: Int) {
        val deviceId = deviceInfo?.deviceId ?: return
        val deviceManager = TXIoTEngine.getInstance(this).deviceManager ?: run {
            show(getString(R.string.iot_lamp_get_properties_failed, ""))
            return
        }
        val json = JSONObject().put(propertyId, value).toString()
        deviceManager.sendCommand(deviceId, json, object : TXIoTCallback<String> {
            override fun onSuccess(result: String) {}

            override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
                runOnUiThread {
                    show(getString(R.string.iot_lamp_command_send_failed, errorMessage))
                }
            }
        })
    }

    private fun displayNameOf(device: TXIoTDeviceInfo?): String {
        device ?: return ""
        val alias = device.aliasName.orEmpty()
        val deviceName = device.deviceId?.deviceName.orEmpty()
        if (alias.isNotEmpty() && alias != deviceName) return alias
        return deviceName.ifEmpty { device.deviceId?.productId.orEmpty() }
    }

    private fun JSONObject.optIntOrNull(key: String): Int? {
        if (!has(key) || isNull(key)) return null
        return when (val raw = opt(key)) {
            is Boolean -> if (raw) 1 else 0
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull()
            else -> null
        }
    }
}
