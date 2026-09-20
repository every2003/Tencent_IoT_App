package com.tencent.iot.txiotdemo.common.util

import android.content.Context

object DebugSettingsStore {

    private const val PREF_NAME = "debug_settings"
    private const val KEY_AUDIO_CODEC = "audio_codec"
    private const val KEY_SERVER_ENV = "server_env"

    enum class AudioCodec(val value: String) {
        DEFAULT("default"),
        G722("g722");

        companion object {
            fun from(value: String?): AudioCodec {
                return values().firstOrNull { it.value == value } ?: DEFAULT
            }
        }
    }

    enum class ServerEnv(val value: String) {
        PROD("prod"),
        TEST("test");

        companion object {
            fun from(value: String?): ServerEnv {
                return values().firstOrNull { it.value == value } ?: PROD
            }
        }
    }

    data class DebugSettings(
        val audioCodec: AudioCodec,
        val serverEnv: ServerEnv
    )

    fun getSettings(context: Context): DebugSettings {
        val sp = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val codec = AudioCodec.from(sp.getString(KEY_AUDIO_CODEC, AudioCodec.DEFAULT.value))
        val env = ServerEnv.from(sp.getString(KEY_SERVER_ENV, ServerEnv.PROD.value))
        return DebugSettings(codec, env)
    }

    fun saveSettings(context: Context, settings: DebugSettings) {
        val sp = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        sp.edit()
            .putString(KEY_AUDIO_CODEC, settings.audioCodec.value)
            .putString(KEY_SERVER_ENV, settings.serverEnv.value)
            .apply()
    }

    fun getAudioCodec(context: Context): AudioCodec {
        return getSettings(context).audioCodec
    }

    fun setAudioCodec(context: Context, audioCodec: AudioCodec) {
        val current = getSettings(context)
        saveSettings(context, current.copy(audioCodec = audioCodec))
    }

    fun getServerEnv(context: Context): ServerEnv {
        return getSettings(context).serverEnv
    }

    fun setServerEnv(context: Context, serverEnv: ServerEnv) {
        val current = getSettings(context)
        saveSettings(context, current.copy(serverEnv = serverEnv))
    }
}
