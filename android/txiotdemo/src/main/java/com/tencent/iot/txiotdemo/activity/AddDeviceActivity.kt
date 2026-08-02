package com.tencent.iot.txiotdemo.activity

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.text.TextUtils
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.CommonBottomSheet
import com.tencent.iot.txiotdemo.common.log.L
import com.tencent.iot.txiotdemo.core.entity.DeviceInfo
import com.tencent.iot.txiotdemo.databinding.IotActivityAddDeviceBinding
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTCallback
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTErrorCode
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTFamilyInfo
import org.json.JSONObject

class AddDeviceActivity : BaseActivity<IotActivityAddDeviceBinding>() {

    companion object {
        private const val REQUEST_CAMERA_PERMISSION = 102
        private const val REQUEST_SCAN_QR_CODE = 101

        const val EXTRA_BOUND_FAMILY_ID = "extra_bound_family_id"
        const val EXTRA_BOUND_FAMILY_NAME = "extra_bound_family_name"
    }

    private var deviceInfo: DeviceInfo? = null

    private val familyList = mutableListOf<TXIoTFamilyInfo>()
    private var currentFamilyId: String = ""
    private var currentFamilyName: String = ""

    override fun getViewBinding(): IotActivityAddDeviceBinding =
        IotActivityAddDeviceBinding.inflate(layoutInflater)

    override fun initView() {
        initDefaultValues()
        loadFamilyList()
    }

    override fun setListener() {
        with(binding) {
            iotBtnBack.setOnClickListener {
                finish()
            }
            iotScanArea.setOnClickListener {
                startQRCodeScan()
            }
            iotLlFamilySelector.setOnClickListener {
                showFamilySelectDialog()
            }

            iotBtnAddDevice.setOnClickListener {
                if (deviceInfo == null && TextUtils.isEmpty(binding.iotEtSignName.text)) {
                    Toast.makeText(
                        this@AddDeviceActivity,
                        getString(R.string.iot_add_device_scan_qr_first),
                        Toast.LENGTH_SHORT
                    ).show()
                    return@setOnClickListener
                }
                if (currentFamilyId.isEmpty()) {
                    Toast.makeText(
                        this@AddDeviceActivity,
                        getString(R.string.iot_add_device_select_family_first),
                        Toast.LENGTH_SHORT
                    )
                        .show()
                    return@setOnClickListener
                }
                addDevice()
            }
        }
    }

    private fun loadFamilyList() {
        val engine = TXIoTEngine.getInstance(this)
        val familyManager = engine.familyManager
        if (familyManager == null) {
            show(getString(R.string.iot_add_device_get_family_mgr_failed))
            return
        }
        familyManager.getFamilyList(loadFamilyListCallback)
    }

    private val loadFamilyListCallback = object : TXIoTCallback<List<TXIoTFamilyInfo>> {
        override fun onSuccess(result: List<TXIoTFamilyInfo>) {
            runOnUiThread { onFamilyListLoaded(result) }
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
            runOnUiThread {
                L.e("Failed to get family list: $errorMessage")
                show(getString(R.string.iot_family_get_list_failed, errorMessage))
            }
        }
    }

    private fun onFamilyListLoaded(result: List<TXIoTFamilyInfo>) {
        familyList.clear()
        familyList.addAll(result)
        if (result.isNotEmpty()) selectFamily(result[0])
        else binding.iotTvFamilyName.text = getString(R.string.iot_add_device_no_family_hint)
    }

    private fun selectFamily(family: TXIoTFamilyInfo) {
        currentFamilyId = family.familyId ?: ""
        currentFamilyName = family.name ?: getString(R.string.iot_family_unnamed)
        binding.iotTvFamilyName.text = currentFamilyName
        binding.iotTvFamilyName.setTextColor(0xFF15161A.toInt())
    }

    private fun showFamilySelectDialog() {
        if (familyList.isEmpty()) {
            Toast.makeText(
                this,
                getString(R.string.iot_add_device_no_family_hint),
                Toast.LENGTH_SHORT
            )
                .show()
            return
        }
        val sheet = CommonBottomSheet(this)
        sheet.setTitle(getString(R.string.iot_family_select_title))
        sheet.setHint(getString(R.string.iot_family_current_label, currentFamilyName))
        sheet.setDividerVisible(familyList.isNotEmpty())
        sheet.hideConfirm()

        val menuContainer = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(0, 0, 0, 8)
        }
        familyList.forEach { family ->
            val item = LayoutInflater.from(this)
                .inflate(R.layout.iot_item_family_menu, menuContainer, false)
            item.findViewById<TextView>(R.id.iot_tvItemIcon).text = "\uD83C\uDFE0"
            item.findViewById<TextView>(R.id.iot_tvItemName).text =
                family.name ?: getString(R.string.iot_family_unnamed)
            item.findViewById<TextView>(R.id.iot_tvItemCheck).visibility =
                if (family.familyId == currentFamilyId) View.VISIBLE else View.GONE
            item.setOnClickListener {
                sheet.dismiss()
                selectFamily(family)
            }
            menuContainer.addView(item)
        }
        sheet.setContent(menuContainer)
        sheet.show()
    }

    private fun initDefaultValues() {
        setImmersiveStatusBar()
    }

    private fun startQRCodeScan() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_CAMERA_PERMISSION
            )
        } else {
            launchQRCodeScanner()
        }
    }

    private fun launchQRCodeScanner() {
        val intent = Intent(this, QRCodeScannerActivity::class.java)
        startActivityForResult(intent, REQUEST_SCAN_QR_CODE)
    }

    private fun addDevice() {
        val signature = binding.iotEtSignName.text.toString()
        if (signature.isEmpty()) {
            L.e("signature is empty"); return
        }
        if (currentFamilyId.isEmpty()) {
            show(getString(R.string.iot_add_device_select_family_first)); return
        }
        showLoading(getString(R.string.iot_add_device_loading))
        val engine = TXIoTEngine.getInstance(this)
        val deviceManager = engine.deviceManager
        if (deviceManager == null) {
            hideLoading()
            show(getString(R.string.iot_add_device_get_dev_mgr_failed))
            return
        }
        deviceManager.bindDevice(currentFamilyId, signature, bindDeviceCallback)
    }

    private val bindDeviceCallback = object : TXIoTCallback<TXIoTDeviceInfo> {
        override fun onSuccess(result: TXIoTDeviceInfo) {
            runOnUiThread { onBindDeviceSuccess(result) }
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
            runOnUiThread {
                hideLoading()
                L.e(errorMessage)
                show(errorMessage)
            }
        }
    }

    private fun onBindDeviceSuccess(result: TXIoTDeviceInfo) {
        hideLoading()
        L.e("Bind success: $result")
        show(getString(R.string.iot_add_device_bind_success, currentFamilyName))
        val data = Intent().apply {
            putExtra(EXTRA_BOUND_FAMILY_ID, currentFamilyId)
            putExtra(EXTRA_BOUND_FAMILY_NAME, currentFamilyName)
        }
        setResult(RESULT_OK, data)
        finish()
    }

    override fun handleRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {

        when (requestCode) {
            REQUEST_CAMERA_PERMISSION -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    launchQRCodeScanner()
                } else {
                    Toast.makeText(
                        this,
                        getString(R.string.iot_add_device_camera_perm_required),
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQUEST_SCAN_QR_CODE -> {
                if (resultCode == RESULT_OK) {
                    handleQRCodeResult(data)
                }
            }
        }
    }

    private fun handleQRCodeResult(data: Intent?) {
        val qrCodeResult = data?.getStringExtra("QR_CODE_RESULT") ?: ""
        if (qrCodeResult.isNotEmpty()) {
            parseQRCodeContent(qrCodeResult)
            Toast.makeText(
                this,
                getString(R.string.iot_add_device_qr_scan_success),
                Toast.LENGTH_SHORT
            )
                .show()
        } else {
            Toast.makeText(
                this,
                getString(R.string.iot_add_device_qr_scan_failed),
                Toast.LENGTH_SHORT
            )
                .show()
        }
    }

    private fun parseQRCodeContent(qrContent: String) {
        Log.d("TAG", "parseQRCodeContent: $qrContent")
        try {
            deviceInfo = DeviceInfo()
            val jsonObject = JSONObject(qrContent)

            if (jsonObject.has("DeviceName")) {
                deviceInfo?.deviceName = jsonObject.getString("DeviceName")
            }

            if (jsonObject.has("ProductId")) {
                deviceInfo?.productId = jsonObject.getString("ProductId")
            }
            if (jsonObject.has("ProductId")) {
                deviceInfo?.signature = jsonObject.getString("Signature")
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        binding.iotEtSignName.setText(deviceInfo?.signature)
    }

    private fun showLoading(message: String) {
        binding.iotBtnAddDevice.isEnabled = false
        binding.iotBtnAddDevice.text = getString(R.string.iot_add_device_btn_adding)
    }

    private fun hideLoading() {
        binding.iotBtnAddDevice.isEnabled = true
        binding.iotBtnAddDevice.text = getString(R.string.iot_add_device_btn_add)
    }

    override fun onBackPressed() {
        if (hasUnsavedInput()) {
            showUnsavedChangesDialog()
        } else {
            super.onBackPressed()
        }
    }

    private fun hasUnsavedInput(): Boolean {
        with(binding) {
            return iotEtSignName.text.isNotEmpty()
        }
    }

    private fun showUnsavedChangesDialog() {
        super.onBackPressed()
    }
}
