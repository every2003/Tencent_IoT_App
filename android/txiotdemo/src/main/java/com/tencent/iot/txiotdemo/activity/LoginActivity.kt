package com.tencent.iot.txiotdemo.activity

import android.Manifest
import android.content.Context
import android.content.Intent
import android.text.TextUtils
import android.widget.Toast
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.util.LogcatHelper
import com.tencent.iot.txiotdemo.common.util.SignatureUtil
import com.tencent.iot.txiotdemo.core.call.IncomingCallManager
import com.tencent.iot.txiotdemo.databinding.IotActivityLoginBinding
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngineDef
import java.util.Random
import java.util.UUID

class LoginActivity : BaseActivity<IotActivityLoginBinding>() {

    private var permissions = arrayOf(
        Manifest.permission.WRITE_EXTERNAL_STORAGE,
        Manifest.permission.READ_EXTERNAL_STORAGE,
        Manifest.permission.RECORD_AUDIO,
        Manifest.permission.CAMERA
    )
    private var userId = ""
    private var isLoggingIn = false
    private var debugTapCount = 0

    companion object {

        fun navigateToLogin(context: Context, expiredMsg: String? = null) {
            if (expiredMsg != null) {
                Toast.makeText(context, expiredMsg, Toast.LENGTH_LONG).show()
            }
            val intent = Intent(context, LoginActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            context.startActivity(intent)
        }
    }

    val loginListener = object : TXIoTEngine.TXIoTEngineListener() {
        override fun onLoginSuccess() {
            runOnUiThread {
                showLoginLoading(false)
            }
            IncomingCallManager.start(applicationContext)
            jumpActivity(DeviceListActivity::class.java, true)
            TXIoTEngine.getInstance(this@LoginActivity).removeListener(this)
        }

        override fun onLoginFailure(errCode: TXIoTEngineDef.TXIoTErrorCode?, errMsg: String?) {
            TXIoTEngine.getInstance(this@LoginActivity).removeListener(this)
            runOnUiThread {
                showLoginLoading(false)
                Toast.makeText(this@LoginActivity, errMsg, Toast.LENGTH_LONG).show()
            }
        }
    }

    override fun getViewBinding(): IotActivityLoginBinding =
        IotActivityLoginBinding.inflate(layoutInflater)

    override fun onBeforeSetContentView() {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
    }

    override fun initView() {
        if (!checkPermissions(permissions)) {
            requestPermission(permissions)
        }
        LogcatHelper.getInstance(this).start()

        ViewCompat.setOnApplyWindowInsetsListener(binding.iotLoginHeader) { v, insets ->
            val top = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top
            v.updatePadding(top = top)
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.iotLoginContent) { v, insets ->
            val bottom = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
            v.updatePadding(bottom = bottom)
            insets
        }
        checkLoginState()
    }

    override fun setListener() {
        with(binding) {
            iotBtnLogin.setOnClickListener {
                login()
            }
            iotTvSmartCameraTitle.setOnClickListener {
                debugTapCount++
                if (debugTapCount >= 5) {
                    debugTapCount = 0
                    startActivity(Intent(this@LoginActivity, DebugSettingsActivity::class.java))
                }
            }
        }
    }

    private fun login() {
        if (isLoggingIn) return

        userId = binding.iotEtUserid.text.toString().trim()
        val appKey = binding.iotEtAppKey.text.toString().trim()
        val appSecret = binding.iotEtAppSecret.text.toString().trim()

        if (TextUtils.isEmpty(userId)) {
            Toast.makeText(this, getString(R.string.iot_login_input_userid), Toast.LENGTH_LONG).show()
            return
        }
        if (TextUtils.isEmpty(appKey)) {
            Toast.makeText(this, getString(R.string.iot_login_input_appkey), Toast.LENGTH_LONG).show()
            return
        }
        if (TextUtils.isEmpty(appSecret)) {
            Toast.makeText(this, getString(R.string.iot_login_input_appsecret), Toast.LENGTH_LONG)
                .show()
            return
        }

        showLoginLoading(true)

        val signature = TXIoTEngine.TXIoTUserSignature()
        signature.requestId = UUID.randomUUID().toString()
        signature.timestamp = System.currentTimeMillis() / 1000
        signature.nonce = Random().nextInt(1000000)

        val param = HashMap<String, Any>()
        param["RequestId"] = signature.requestId
        param["AppKey"] = appKey
        param["Timestamp"] = signature.timestamp
        param["Nonce"] = signature.nonce
        param["OpenID"] = userId
        signature.signature = SignatureUtil.signature(SignatureUtil.format(param), appSecret)
        TXIoTEngine.getInstance(this).addListener(loginListener)
        TXIoTEngine.getInstance(this).login(appKey, userId, signature)
    }

    private fun showLoginLoading(loading: Boolean) {
        isLoggingIn = loading
        if (loading) {
            binding.iotBtnLogin.text = ""
            binding.iotPbLogin.visibility = android.view.View.VISIBLE
        } else {
            binding.iotBtnLogin.text = getString(R.string.iot_login_btn_text)
            binding.iotPbLogin.visibility = android.view.View.GONE
        }
    }

    override fun onDestroy() {
        LogcatHelper.getInstance(this).stop()
        super.onDestroy()
    }

    override fun permissionAllGranted() {
    }

    private fun checkLoginState() {
        val userInfo = TXIoTEngine.getInstance(this).loginUserInfo
        if (userInfo != null && !TextUtils.isEmpty(userInfo.userId)) {
            IncomingCallManager.start(applicationContext)
            jumpActivity(DeviceListActivity::class.java, true)
        }
    }
}
