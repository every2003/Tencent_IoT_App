package com.tencent.iot.txiotdemo.activity

import android.text.TextUtils
import android.util.Log
import com.bumptech.glide.Glide

import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.databinding.IotActivityPersonalInfoBinding
import com.tencent.liteav.iot.TXIoTEngine

class PersonalInfoActivity : BaseActivity<IotActivityPersonalInfoBinding>() {

    override fun getViewBinding(): IotActivityPersonalInfoBinding =
        IotActivityPersonalInfoBinding.inflate(layoutInflater)

    override fun initView() {
        setImmersiveStatusBar()
        setNavigationBarColor()
        showUserInfo()
    }

    private fun setNavigationBarColor() {
        window.decorView.systemUiVisibility = window.decorView.systemUiVisibility or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            window.navigationBarColor = android.graphics.Color.WHITE
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            window.decorView.systemUiVisibility = window.decorView.systemUiVisibility or
                    android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
    }

    override fun setListener() {
        with(binding) {
            iotBtnBack.setOnClickListener { finish() }
            iotTvUserInfoLogout.setOnClickListener { logout() }
        }
    }

    private fun showUserInfo() {
        val userInfo = TXIoTEngine.getInstance(this).loginUserInfo
        if (userInfo == null) {
            Log.e(TAG, "getLoginUserInfo returned null, user not logged in")
            show(getString(R.string.iot_personal_not_logged_in))
            return
        }

        binding.iotTvNick.text = userInfo.nickName
        binding.iotTvTitleNick.text = userInfo.nickName
        binding.iotTvUserId.text = userInfo.userId
        if (!TextUtils.isEmpty(userInfo.avatarUrl)) {
            Glide.with(this).load(userInfo.avatarUrl).into(binding.iotUserInfoPortrait)
        }
        Log.d(TAG, "User info: userId=${userInfo.userId}, nickName=${userInfo.nickName}")
    }

    private fun logout() {
        TXIoTEngine.getInstance(this).logout()
        jumpActivity(LoginActivity::class.java, true)
    }
}
