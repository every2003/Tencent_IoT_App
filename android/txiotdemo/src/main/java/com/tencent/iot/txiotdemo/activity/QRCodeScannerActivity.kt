package com.tencent.iot.txiotdemo.activity

import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.zxing.Result
import com.tencent.iot.txiotdemo.databinding.IotActivityQrcodeScannerBinding
import me.dm7.barcodescanner.zxing.ZXingScannerView

class QRCodeScannerActivity : BaseActivity<IotActivityQrcodeScannerBinding>(),
    ZXingScannerView.ResultHandler {

    companion object {
        private const val TAG = "QRCodeScannerActivity"
        private const val REQUEST_CAMERA_PERMISSION = 1001
    }

    override fun getViewBinding(): IotActivityQrcodeScannerBinding =
        IotActivityQrcodeScannerBinding.inflate(layoutInflater)

    override fun initView() {
        setImmersiveStatusBar()
    }

    override fun setListener() {
        binding.iotBtnBack.setOnClickListener { finish() }
    }

    override fun onResume() {
        super.onResume()
        if (hasCameraPermission()) {
            startScanner()
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_CAMERA_PERMISSION
            )
        }
    }

    override fun onPause() {
        super.onPause()
        binding.iotScannerView.stopCamera()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CAMERA_PERMISSION) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startScanner()
        } else {
            Log.e(TAG, "Camera permission denied")
            finish()
        }
    }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED

    private fun startScanner() {
        binding.iotScannerView.setResultHandler(this)
        binding.iotScannerView.startCamera()
    }

    override fun handleResult(rawResult: Result?) {
        val rawValue = rawResult?.text
        if (rawValue.isNullOrEmpty()) {
            binding.iotScannerView.resumeCameraPreview(this)
            return
        }
        Log.d(TAG, "QR code detected: $rawValue")
        setResult(RESULT_OK, intent.putExtra("QR_CODE_RESULT", rawValue))
        finish()
    }
}
