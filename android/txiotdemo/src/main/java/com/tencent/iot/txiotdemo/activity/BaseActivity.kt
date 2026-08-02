package com.tencent.iot.txiotdemo.activity

import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Bundle
import android.text.TextUtils
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.viewbinding.ViewBinding
import com.tencent.iot.txiotdemo.common.log.L

abstract class BaseActivity<VB : ViewBinding> : AppCompatActivity() {

    val TAG: String by lazy {
        this.packageName.let {
            it.substring(it.lastIndexOf("."), it.lastIndex)
        }
    }

    protected val binding by lazy { getViewBinding() }

    abstract fun getViewBinding(): VB

    open fun performInitView() {}

    abstract fun initView()

    abstract fun setListener()

    open fun startHere() {
        performInitView()
        initView()
        setListener()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        onBeforeSetContentView()
        super.setContentView(binding.root)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        startHere()
    }

    open fun onBeforeSetContentView() {}

    override fun onResume() {
        super.onResume()
    }

    protected fun checkPermissions(permissions: Array<String>): Boolean {
        return permissions.all { p ->
            val granted =
                ActivityCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED
            L.e(if (granted) "$p granted" else "$p denied")
            granted
        }
    }

    protected fun requestPermission(permissions: Array<String>) {
        ActivityCompat.requestPermissions(this, permissions, 102)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        handleRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 102) {
            handleBasePermissionResult(permissions, grantResults)
        }
    }

    private fun handleBasePermissionResult(permissions: Array<String>, grantResults: IntArray) {
        for (i in permissions.indices) {
            if (grantResults[i] == PackageManager.PERMISSION_DENIED) {
                permissionDenied(permissions[i])
                return
            }
        }
        permissionAllGranted()
    }

    open fun handleRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
    }

    open fun jumpActivity(clazz: Class<*>) {
        jumpActivity(clazz, false)
    }

    open fun jumpActivity(clazz: Class<*>, finish: Boolean) {
        startActivity(Intent(this, clazz))
        if (finish) finish()
    }

    open fun permissionAllGranted() {}

    open fun permissionDenied(permission: String) {}

    fun show(text: String?) {
        if (TextUtils.isEmpty(text)) return
        runOnUiThread {
            Toast.makeText(this, text, Toast.LENGTH_SHORT).show()
        }
    }

    fun dp2px(dp: Int): Int {
        return (resources.displayMetrics.density * dp + 0.5).toInt()
    }

    protected fun setImmersiveStatusBar() {
        window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            window.decorView.systemUiVisibility = window.decorView.systemUiVisibility or
                    View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            window.statusBarColor = android.graphics.Color.TRANSPARENT
        }
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.action == MotionEvent.ACTION_DOWN) {
            clearEditTextFocusIfNeeded(ev)
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun clearEditTextFocusIfNeeded(ev: MotionEvent) {
        val focused = currentFocus
        if (focused is EditText && isTouchOutsideView(ev, focused)) {
            hideSoftInput(focused)
            focused.clearFocus()
        }
    }

    private fun isTouchOutsideView(ev: MotionEvent, view: View): Boolean {
        val rect = Rect()
        view.getGlobalVisibleRect(rect)
        return !rect.contains(ev.rawX.toInt(), ev.rawY.toInt())
    }

    private fun hideSoftInput(view: View) {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager ?: return
        imm.hideSoftInputFromWindow(view.windowToken, 0)
    }
}
