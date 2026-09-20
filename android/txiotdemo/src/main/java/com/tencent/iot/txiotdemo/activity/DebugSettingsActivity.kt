package com.tencent.iot.txiotdemo.activity

import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.util.DebugSettingsStore
import com.tencent.iot.txiotdemo.common.util.DebugSettingsStore.AudioCodec
import com.tencent.iot.txiotdemo.common.util.DebugSettingsStore.ServerEnv
import com.tencent.iot.txiotdemo.databinding.IotActivityDebugSettingsBinding

class DebugSettingsActivity : BaseActivity<IotActivityDebugSettingsBinding>() {

    private val codecOptions by lazy {
        listOf(
            getString(R.string.iot_debug_codec_default) to AudioCodec.DEFAULT.value,
            getString(R.string.iot_debug_codec_g722) to AudioCodec.G722.value
        )
    }

    private val envOptions by lazy {
        listOf(
            getString(R.string.iot_debug_env_prod) to ServerEnv.PROD.value,
            getString(R.string.iot_debug_env_test) to ServerEnv.TEST.value
        )
    }

    override fun getViewBinding(): IotActivityDebugSettingsBinding =
        IotActivityDebugSettingsBinding.inflate(layoutInflater)

    override fun initView() {
        setImmersiveStatusBar()
        binding.iotSettingCodec.apply {
            setTitle(getString(R.string.iot_debug_codec_title))
            setOptions(codecOptions)
        }
        binding.iotSettingEnv.apply {
            setTitle(getString(R.string.iot_debug_env_title))
            setOptions(envOptions)
        }
        renderSettings(DebugSettingsStore.getSettings(this))
    }

    override fun setListener() {
        binding.iotBtnBack.setOnClickListener { finish() }
        binding.iotBtnSave.setOnClickListener {
            val codecValue = binding.iotSettingCodec.getSelectedValue()
            val envValue = binding.iotSettingEnv.getSelectedValue()
            val settings = DebugSettingsStore.DebugSettings(
                audioCodec = AudioCodec.from(codecValue),
                serverEnv = ServerEnv.from(envValue)
            )
            DebugSettingsStore.saveSettings(this, settings)
            show(getString(R.string.iot_debug_settings_saved))
            finish()
        }
    }

    private fun renderSettings(settings: DebugSettingsStore.DebugSettings) {
        binding.iotSettingCodec.setSelectedValue(settings.audioCodec.value)
        binding.iotSettingEnv.setSelectedValue(settings.serverEnv.value)
    }
}
