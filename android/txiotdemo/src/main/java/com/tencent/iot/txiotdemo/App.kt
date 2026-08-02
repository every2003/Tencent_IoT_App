package com.tencent.iot.txiotdemo

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate
import com.tencent.iot.txiotdemo.common.log.L
import com.tencent.iot.txiotdemo.core.call.IncomingCallManager

class App : Application() {

    override fun onCreate() {
        super.onCreate()
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_NO)
        L.isLog = true
        IncomingCallManager.init(this)
    }
}
