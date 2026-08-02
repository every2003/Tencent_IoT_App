package com.tencent.iot.txiotdemo.activity

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.recyclerview.widget.LinearLayoutManager
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.CommonBottomSheet
import com.tencent.iot.txiotdemo.common.PopupMenuHelper
import com.tencent.iot.txiotdemo.common.log.L
import com.tencent.iot.txiotdemo.common.util.DeviceJsonUtils
import com.tencent.iot.txiotdemo.core.adapter.DeviceAdapter
import com.tencent.iot.txiotdemo.databinding.IotActivityDeviceListBinding
import com.tencent.iot.txiotdemo.databinding.IotDialogChannelSelectionBinding
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTCallMediaType
import com.tencent.liteav.iot.TXIoTDeviceManager
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngine.TXIoTEngineListener
import com.tencent.liteav.iot.TXIoTEngine.TXIoTPushMessage
import com.tencent.liteav.iot.TXIoTEngine.TXIoTPushMessageType
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTCallback
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceId
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTErrorCode
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTFamilyInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTPageResult
import com.tencent.liteav.iot.TXIoTFamilyManager

class DeviceListActivity : BaseActivity<IotActivityDeviceListBinding>() {

    private val deviceList = mutableListOf<TXIoTDeviceInfo>()
    private lateinit var adapter: DeviceAdapter
    private val sharedDeviceKeys = mutableSetOf<String>()

    private val addDeviceLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result -> handleAddDeviceResult(result) }

    private fun handleAddDeviceResult(result: androidx.activity.result.ActivityResult) {
        if (result.resultCode != RESULT_OK) return
        val boundFamilyId =
            result.data?.getStringExtra(AddDeviceActivity.EXTRA_BOUND_FAMILY_ID).orEmpty()
        val boundFamilyName =
            result.data?.getStringExtra(AddDeviceActivity.EXTRA_BOUND_FAMILY_NAME).orEmpty()
        if (boundFamilyId.isNotEmpty() && boundFamilyId != currentFamilyId) {
            currentFamilyId = boundFamilyId
            currentFamilyName = boundFamilyName
            updateFamilyBar()
        }
        binding.iotSwipeRefreshLayout.isRefreshing = true
        refreshHandler.postDelayed({ initDeviceList() }, 800)
    }

    private val familyManageLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode != RESULT_OK) return@registerForActivityResult
        val data = result.data ?: return@registerForActivityResult
        if (data.getBooleanExtra(FamilyManageActivity.EXTRA_FAMILY_LIST_CHANGED, false)) {
            loadFamilyList()
        } else {
            currentFamilyId = data.getStringExtra(FamilyManageActivity.EXTRA_RESULT_FAMILY_ID)
                ?: currentFamilyId
            currentFamilyName = data.getStringExtra(FamilyManageActivity.EXTRA_RESULT_FAMILY_NAME)
                ?: currentFamilyName
            updateFamilyBar()
            initDeviceList()
        }
    }

    private fun openFamilyManage() {
        val intent = Intent(this, FamilyManageActivity::class.java).apply {
            putExtra(FamilyManageActivity.EXTRA_FAMILY_ID, currentFamilyId)
            putExtra(FamilyManageActivity.EXTRA_FAMILY_NAME, currentFamilyName)
        }
        familyManageLauncher.launch(intent)
    }

    private val refreshHandler = Handler(Looper.getMainLooper())

    private var currentFamilyId: String = ""
    private var currentFamilyName: String = ""

    private val familyList = mutableListOf<TXIoTFamilyInfo>()

    private val iotEngineListener = object : TXIoTEngineListener() {
        override fun onLoginSuccess() {
            runOnUiThread { show(getString(R.string.iot_login_success)) }
        }

        override fun onLoginFailure(errCode: TXIoTErrorCode, errMsg: String) {
            runOnUiThread { show(getString(R.string.iot_login_failure, errMsg)) }
        }

        override fun onLogout() {}

        override fun onUserSignatureExpired() {
            runOnUiThread {
                LoginActivity.navigateToLogin(
                    this@DeviceListActivity,
                    getString(R.string.iot_login_expired)
                )
            }
        }

        override fun onReceivePushMessage(pushMessage: TXIoTPushMessage) {
            runOnUiThread { handlePushMessage(pushMessage) }
        }
    }

    private fun handlePushMessage(pushMessage: TXIoTPushMessage) {
        if (pushMessage.type == TXIoTPushMessageType.STATUS_CHANGE) {
            L.e("[Push] Device status changed: deviceId=${pushMessage.deviceId}")
            initDeviceList()
            return
        }
        L.e("[Push] Received push message: type=${pushMessage.type}, deviceId=${pushMessage.deviceId}")
    }

    override fun getViewBinding(): IotActivityDeviceListBinding =
        IotActivityDeviceListBinding.inflate(layoutInflater)

    override fun initView() {
        setImmersiveStatusBar()
        setupRecyclerView()
        setupSwipeRefresh()
        updateEmptyState()
        loadFamilyList()
    }

    override fun setListener() {
        with(binding) {
            iotBtnAddDevice.setOnClickListener { showAddDevicePage() }
            iotBtnAddDeviceEmpty.setOnClickListener { showAddDevicePage() }
            iotBtnUserProfile.setOnClickListener { jumpActivity(PersonalInfoActivity::class.java) }
            iotBtnMessage.setOnClickListener { jumpActivity(MessageActivity::class.java) }
            iotSwipeRefreshLayout.setOnRefreshListener { initDeviceList() }
            iotLlFamilyNameClick.setOnClickListener { showFamilySwitchDialog() }
            iotTvFamilyManage.setOnClickListener { openFamilyManage() }
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

    override fun onDestroy() {
        refreshHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private inline fun <T> uiCallback(
        errorRes: Int,
        crossinline onOk: (T) -> Unit
    ): TXIoTCallback<T> = object : TXIoTCallback<T> {
        override fun onSuccess(result: T) {
            runOnUiThread { onOk(result) }
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
            runOnUiThread { show(getString(errorRes, errorMessage)) }
        }
    }

    private inline fun <T> silentCallback(
        crossinline onOk: (T) -> Unit,
        crossinline onErr: (TXIoTErrorCode, String) -> Unit = { _, _ -> }
    ): TXIoTCallback<T> = object : TXIoTCallback<T> {
        override fun onSuccess(result: T) {
            runOnUiThread { onOk(result) }
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
            runOnUiThread { onErr(errorCode, errorMessage) }
        }
    }

    private fun voidCallback(
        successText: String?,
        errorRes: Int,
        afterSuccess: () -> Unit = {}
    ): TXIoTCallback<Void> = uiCallback(errorRes) {
        if (!successText.isNullOrEmpty()) show(successText)
        afterSuccess()
    }

    private fun updateFamilyBar() {
        binding.iotTvFamilyName.text =
            currentFamilyName.ifEmpty { getString(R.string.iot_family_default_name) }
    }

    private fun loadFamilyList() {
        val familyManager = getFamilyManager() ?: return
        familyManager.getFamilyList(
            silentCallback<List<TXIoTFamilyInfo>>(
                onOk = { result ->
                    familyList.clear()
                    familyList.addAll(result)
                    if (result.isNotEmpty()) selectFamily(result[0]) else createDefaultFamily()
                },
                onErr = { _, msg -> L.e(getString(R.string.iot_family_get_list_failed, msg)) }
            ))
    }

    private fun selectFamily(family: TXIoTFamilyInfo) {
        currentFamilyId = family.familyId ?: ""
        currentFamilyName = family.name ?: ""
        updateFamilyBar()
        initDeviceList()
    }

    private fun createDefaultFamily() {
        val familyManager = getFamilyManager() ?: return
        familyManager.createFamily(
            getString(R.string.iot_family_default_name),
            uiCallback<TXIoTFamilyInfo>(R.string.iot_family_create_failed) { result ->
                familyList.add(result)
                selectFamily(result)
            }
        )
    }

    private fun showFamilySwitchDialog() {
        if (familyList.isEmpty()) return

        val sheet = CommonBottomSheet(this)
        sheet.setTitle(getString(R.string.iot_family_select_title))
        sheet.setHint(getString(R.string.iot_family_current_label, currentFamilyName))
        sheet.setDividerVisible(familyList.isNotEmpty())
        sheet.hideConfirm()

        val menuContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, 8)
        }
        familyList.forEach { family ->
            menuContainer.addView(
                createFamilySwitchItem(menuContainer, family) {
                    sheet.dismiss()
                    selectFamily(family)
                }
            )
        }
        sheet.setContent(menuContainer)
        sheet.show()
    }

    private fun createFamilySwitchItem(
        parent: ViewGroup,
        family: TXIoTFamilyInfo,
        onClick: () -> Unit
    ): View {
        val item = LayoutInflater.from(this).inflate(R.layout.iot_item_family_menu, parent, false)
        item.findViewById<TextView>(R.id.iot_tvItemIcon).text = "\uD83C\uDFE0"
        item.findViewById<TextView>(R.id.iot_tvItemName).text =
            family.name ?: getString(R.string.iot_family_unnamed)
        item.findViewById<TextView>(R.id.iot_tvItemCheck).visibility =
            if (family.familyId == currentFamilyId) View.VISIBLE else View.GONE
        item.setOnClickListener { onClick() }
        return item
    }

    private fun initDeviceList() {
        if (currentFamilyId.isEmpty()) return
        loadOwnDevices()
    }

    private fun loadOwnDevices() {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.getDeviceList(
            currentFamilyId, "",
            silentCallback<TXIoTPageResult<TXIoTDeviceInfo>>(
                onOk = { pageResult ->
                    val own = pageResult.dataList ?: emptyList()
                    loadSharedDevices(own)
                },
                onErr = { _, msg -> onLoadDevicesFailed(msg) }
            )
        )
    }

    private fun loadSharedDevices(own: List<TXIoTDeviceInfo>) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.getDeviceListSharedWithMe(
            "",
            silentCallback<TXIoTPageResult<TXIoTDeviceInfo>>(
                onOk = { sharedPageResult ->
                    applyDeviceList(own, sharedPageResult.dataList ?: emptyList())
                },
                onErr = { _, _ -> applyDeviceList(own, emptyList()) }
            )
        )
    }

    private fun applyDeviceList(own: List<TXIoTDeviceInfo>, shared: List<TXIoTDeviceInfo>) {
        sharedDeviceKeys.clear()
        deviceList.clear()
        deviceList.addAll(own)
        shared.forEach { device ->
            val key = "${device.deviceId?.productId}_${device.deviceId?.deviceName}"
            sharedDeviceKeys.add(key)
            deviceList.add(device)
        }
        refreshDeviceList()
        if (deviceList.isNotEmpty()) fetchDeviceStatus(deviceList)
    }

    private fun onLoadDevicesFailed(errorMessage: String) {
        binding.iotSwipeRefreshLayout.isRefreshing = false
        Toast.makeText(
            this,
            getString(R.string.iot_refresh_failed, errorMessage),
            Toast.LENGTH_SHORT
        ).show()
    }

    private fun fetchDeviceStatus(devices: List<TXIoTDeviceInfo>) {
        val statusMap = devices
            .filter { it.deviceId != null }
            .associate { device ->
                val pid = device.deviceId?.productId
                val dn = device.deviceId?.deviceName
                "${pid}_${dn}" to (device.status?.isOnline == true)
            }
        adapter.updateStatus(statusMap)
    }

    private fun unbindDevice(deviceId: TXIoTDeviceId) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.unbindDevice(
            currentFamilyId,
            deviceId,
            uiCallback<Void>(R.string.iot_device_unbind_failed) {
                Toast.makeText(this, getString(R.string.iot_device_unbind_success), Toast.LENGTH_SHORT)
                    .show()
                initDeviceList()
            })
    }

    private fun shareDevice(device: TXIoTDeviceInfo) {
        val deviceId = device.deviceId ?: return
        val familyId = device.familyId ?: currentFamilyId
        val deviceManager = getDeviceManager() ?: return
        deviceManager.createDeviceSharingToken(
            familyId,
            deviceId,
            uiCallback<String>(R.string.iot_detail_share_token_failed) { token ->
                showSharingTokenSheet(deviceId, token)
            }
        )
    }

    private fun showSharingTokenSheet(deviceId: TXIoTDeviceId, token: String) {
        val shareJson = org.json.JSONObject().apply {
            put("productId", deviceId.productId ?: "")
            put("deviceName", deviceId.deviceName ?: "")
            put("token", token)
        }.toString(2)

        val editText = EditText(this).apply {
            setText(shareJson)
            isFocusable = false
            isFocusableInTouchMode = false
            setTextIsSelectable(true)
            setBackgroundResource(R.drawable.iot_bg_dialog_input)
            setPadding(36, 24, 36, 24)
            gravity = android.view.Gravity.TOP
            setTextColor(Color.parseColor("#15161A"))
            textSize = 15f
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, dip(140))
        }

        val sheet = CommonBottomSheet(this).apply {
            setTitle(getString(R.string.iot_detail_share_token_title))
            setHint(null)
            setDividerVisible(false)
            setContent(editText)
            setConfirmDismiss(getString(R.string.iot_detail_copy_share_token)) {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("share_token", shareJson))
                show(getString(R.string.iot_detail_share_token_copied))
            }
        }
        sheet.show()
    }

    private fun getFamilyManager(): TXIoTFamilyManager? =
        TXIoTEngine.getInstance(this).familyManager

    private fun getDeviceManager(): TXIoTDeviceManager? =
        TXIoTEngine.getInstance(this).deviceManager

    private fun setupRecyclerView() {
        adapter = DeviceAdapter(deviceList)
        binding.iotRvDeviceList.apply {
            layoutManager = LinearLayoutManager(this@DeviceListActivity)
            adapter = this@DeviceListActivity.adapter
        }
        adapter.setOnItemClickListener { _, device ->
            showChannelGridDialog(device)
        }
        adapter.setOnMenuClickListener { position, device, rootView ->
            showDeviceMenu(position, device, rootView)
        }
    }

    private fun setupSwipeRefresh() {
        binding.iotSwipeRefreshLayout.setColorSchemeResources(
            android.R.color.holo_blue_bright,
            android.R.color.holo_green_light,
            android.R.color.holo_orange_light,
            android.R.color.holo_red_light
        )
    }

    private fun updateEmptyState() {
        val isEmpty = deviceList.isEmpty()
        binding.iotEmptyState.visibility = if (isEmpty) View.VISIBLE else View.GONE
        binding.iotRvDeviceList.visibility = if (isEmpty) View.GONE else View.VISIBLE
    }

    private fun refreshDeviceList() {
        binding.iotSwipeRefreshLayout.isRefreshing = false
        adapter.notifyDataSetChanged()
        updateEmptyState()
    }

    private fun showAddDevicePage() {
        addDeviceLauncher.launch(Intent(this, AddDeviceActivity::class.java))
    }

    private fun openDeviceDetail(
        device: TXIoTDeviceInfo,
        channelType: String,
        selectedChannels: List<Int>? = null
    ) {
        startActivity(Intent(this, DeviceDetailActivity::class.java).apply {
            putExtra("deviceInfo", DeviceJsonUtils.toJson(device))
            putExtra("channelType", channelType)
            putExtra("selectedChannels", selectedChannels?.toIntArray())
        })
    }

    private fun showChannelGridDialog(device: TXIoTDeviceInfo) {
        val pid = device.deviceId?.productId.orEmpty()
        val dn = device.deviceId?.deviceName.orEmpty()

        val sheet = CommonBottomSheet(this)
        sheet.setTitle(getString(R.string.iot_channel_select_title))
        sheet.setHint(getString(R.string.iot_channel_select_device_info, pid, dn))
        sheet.setDividerVisible(false)

        val gridBinding = IotDialogChannelSelectionBinding.inflate(layoutInflater)
        sheet.setContent(gridBinding.root)

        val totalChannels = 4
        val selectedSet = mutableSetOf(0)

        val channelCircleViews = arrayOf(
            gridBinding.iotTvChannelCircle0,
            gridBinding.iotTvChannelCircle1,
            gridBinding.iotTvChannelCircle2,
            gridBinding.iotTvChannelCircle3
        )

        fun refreshChannel(index: Int) {
            val selected = index in selectedSet
            val circle = channelCircleViews[index]
            if (selected) {
                circle.setBackgroundResource(R.drawable.iot_bg_channel_circle_selected)
                circle.setTextColor(Color.WHITE)
            } else {
                circle.setBackgroundResource(R.drawable.iot_bg_channel_circle_unselected)
                circle.setTextColor(Color.parseColor("#15161A"))
            }
        }

        val channelItemViews = arrayOf(
            gridBinding.iotChannelItem0,
            gridBinding.iotChannelItem1,
            gridBinding.iotChannelItem2,
            gridBinding.iotChannelItem3
        )
        for (i in 0 until totalChannels) {
            channelItemViews[i].setOnClickListener {
                if (i in selectedSet) selectedSet.remove(i) else selectedSet.add(i)
                refreshChannel(i)
            }
        }

        refreshChannel(0)

        sheet.setConfirm(getString(R.string.iot_btn_confirm)) {
            if (selectedSet.isEmpty()) {
                Toast.makeText(
                    this,
                    getString(R.string.iot_channel_select_at_least_one),
                    Toast.LENGTH_SHORT
                ).show()
                return@setConfirm
            }
            sheet.dismiss()
            val sortedChannels = selectedSet.sorted()
            val channelType = if (sortedChannels.size == 1) "single" else "multi"
            openDeviceDetail(device, channelType, sortedChannels)
        }

        sheet.show()
    }

    private fun showDeviceMenu(position: Int, device: TXIoTDeviceInfo, rootView: View) {
        val deviceId = device.deviceId ?: return
        val pid = deviceId.productId.orEmpty()
        val dn = deviceId.deviceName.orEmpty()
        PopupMenuHelper.show(
            this, rootView, listOf(
                PopupMenuHelper.Item("📹", getString(R.string.iot_video_call)) {
                    IoTCallActivity.start(this, pid, dn, device.aliasName, TXIoTCallMediaType.VIDEO)
                },
                PopupMenuHelper.Item("📞", getString(R.string.iot_audio_call)) {
                    IoTCallActivity.start(this, pid, dn, device.aliasName, TXIoTCallMediaType.AUDIO)
                },
                PopupMenuHelper.Item(
                    "✏️",
                    getString(R.string.iot_device_modify_alias_title)
                ) { showModifyAliasDialog(position, device, deviceId) },
                PopupMenuHelper.Item("🔗", getString(R.string.iot_share_device)) { shareDevice(device) },
                PopupMenuHelper.Item(
                    "🗑️",
                    getString(R.string.iot_unbind_device),
                    destructive = true
                ) {
                    unbindDevice(deviceId)
                },
            )
        )
    }

    private fun showModifyAliasDialog(
        position: Int,
        device: TXIoTDeviceInfo,
        deviceId: TXIoTDeviceId
    ) {
        showInputBottomSheet(
            title = getString(R.string.iot_device_modify_alias_title),
            hint = getString(R.string.iot_device_modify_alias_hint),
            defaultText = device.aliasName.orEmpty()
        ) { newAlias -> modifyDeviceAliasName(position, deviceId, newAlias) }
    }

    private fun modifyDeviceAliasName(position: Int, deviceId: TXIoTDeviceId, newAlias: String) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.modifyAliasName(
            deviceId,
            newAlias,
            uiCallback<Void>(R.string.iot_device_modify_alias_failed) {
                onModifyAliasSuccess(position, newAlias)
            }
        )
    }

    private fun onModifyAliasSuccess(position: Int, newAlias: String) {
        deviceList.getOrNull(position)?.aliasName = newAlias
        adapter.notifyItemChanged(position)
        show(getString(R.string.iot_device_modify_alias_success))
    }

    private fun showInputBottomSheet(
        title: String,
        hint: String,
        defaultText: String = "",
        confirmText: String = "",
        extraBtnText: String? = null,
        onExtra: ((text: String) -> Unit)? = null,
        onConfirm: (text: String) -> Unit
    ) {
        val sheet = CommonBottomSheet(this)
        sheet.setTitle(title)
        sheet.setHint(null)
        sheet.setDividerVisible(false)

        val editText = createSheetEditText(hint, defaultText)
        sheet.setContent(editText)

        sheet.setConfirm(confirmText.ifEmpty { getString(R.string.iot_btn_confirm) }) {
            validateInput(editText)?.let { sheet.dismiss(); onConfirm(it) }
        }

        if (extraBtnText != null) {
            attachExtraButton(sheet, extraBtnText, editText, onExtra)
        }

        sheet.show()
    }

    private fun dip(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun createSheetEditText(hint: String, defaultText: String): EditText =
        EditText(this).apply {
            this.hint = hint
            setBackgroundResource(R.drawable.iot_bg_dialog_input)
            setPadding(36, 0, 36, 0)
            setTextColor(Color.parseColor("#15161A"))
            setHintTextColor(Color.parseColor("#B0B7C3"))
            textSize = 15f
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            maxLines = 1
            imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_DONE
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, dip(54))
            if (defaultText.isNotEmpty()) {
                setText(defaultText); selectAll()
            }
        }

    private fun attachExtraButton(
        sheet: CommonBottomSheet,
        extraBtnText: String,
        editText: EditText,
        onExtra: ((text: String) -> Unit)?
    ) {
        val extraBtn = TextView(this).apply {
            text = extraBtnText
            gravity = android.view.Gravity.CENTER
            setBackgroundResource(R.drawable.iot_bg_outline_button)
            setTextColor(0xFF006EFF.toInt())
            textSize = 16f
            setTypeface(null, android.graphics.Typeface.BOLD)
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, dip(52))
        }
        sheet.getButtonsContainer().addView(extraBtn, 1)
        extraBtn.setOnClickListener { onExtraButtonClick(editText, sheet, onExtra) }
    }

    private fun onExtraButtonClick(
        editText: EditText,
        sheet: CommonBottomSheet,
        onExtra: ((text: String) -> Unit)?
    ) {
        validateInput(editText)?.let {
            sheet.dismiss()
            onExtra?.invoke(it)
        }
    }

    private fun validateInput(input: EditText): String? {
        val text = input.text.toString().trim()
        if (text.isEmpty()) {
            input.error = getString(R.string.iot_input_empty_error)
            return null
        }
        return text
    }
}
