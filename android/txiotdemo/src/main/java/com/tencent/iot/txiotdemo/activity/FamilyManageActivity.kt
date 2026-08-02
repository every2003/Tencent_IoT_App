package com.tencent.iot.txiotdemo.activity

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2.OnPageChangeCallback
import com.google.android.material.tabs.TabLayout
import com.google.android.material.tabs.TabLayout.OnTabSelectedListener
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.CommonBottomSheet
import com.tencent.iot.txiotdemo.common.PopupMenuHelper
import com.tencent.iot.txiotdemo.databinding.IotActivityFamilyManageBinding
import com.tencent.liteav.iot.TXIoTDeviceManager
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTCallback
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceId
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTErrorCode
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTFamilyInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTFamilyRole
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTPageResult
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTRoomInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTUserInfo
import com.tencent.liteav.iot.TXIoTFamilyManager
import org.json.JSONObject

class FamilyManageActivity : BaseActivity<IotActivityFamilyManageBinding>() {

    companion object {
        const val EXTRA_FAMILY_ID = "extra_family_id"
        const val EXTRA_FAMILY_NAME = "extra_family_name"
        const val EXTRA_RESULT_FAMILY_ID = "extra_result_family_id"
        const val EXTRA_RESULT_FAMILY_NAME = "extra_result_family_name"
        const val EXTRA_FAMILY_LIST_CHANGED = "extra_family_list_changed"

        private const val DANGER_TEXT_COLOR = "#FF4444"

        const val TAB_INDEX_MEMBERS = 0

        const val TAB_INDEX_ROOMS = 1

        const val TAB_INDEX_DEVICE_SHARE = 2

        const val TAB_INDEX_SHARED_TO_ME = 3
    }

    private var currentFamilyId: String = ""
    private var currentFamilyName: String = ""

    private val deviceList = mutableListOf<TXIoTDeviceInfo>()

    private var familyDataChanged = false
    private var familyListChanged = false

    override fun getViewBinding(): IotActivityFamilyManageBinding =
        IotActivityFamilyManageBinding.inflate(layoutInflater)

    override fun initView() {
        setImmersiveStatusBar()
        currentFamilyId = intent.getStringExtra(EXTRA_FAMILY_ID).orEmpty()
        currentFamilyName = intent.getStringExtra(EXTRA_FAMILY_NAME).orEmpty()
        binding.iotTvFamilyName.text =
            currentFamilyName.ifEmpty { getString(R.string.iot_family_default_name) }
        setupTabsAndPager()
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finishWithResult()
            }
        })
    }

    override fun setListener() {
        binding.iotBtnBack.setOnClickListener { finishWithResult() }
        binding.iotBtnFamilyMore.setOnClickListener { anchor -> showFamilyMorePopup(anchor) }
    }

    private fun finishWithResult() {
        val changed = familyDataChanged || familyListChanged
        val data = Intent().apply {
            if (!familyListChanged) {
                putExtra(EXTRA_RESULT_FAMILY_ID, currentFamilyId)
                putExtra(EXTRA_RESULT_FAMILY_NAME, currentFamilyName)
            }
            putExtra(EXTRA_FAMILY_LIST_CHANGED, familyListChanged)
        }
        setResult(if (changed) RESULT_OK else RESULT_CANCELED, data)
        finish()
    }

    private val pageViews = arrayOfNulls<View>(4)

    private fun setupTabsAndPager() {
        val getOrInflatePage: (Int) -> View = { index -> ensurePage(index) }
        binding.iotViewPager.adapter = ManagePagerAdapter(getOrInflatePage)
        binding.iotTabLayout.addOnTabSelectedListener(object : OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab) {
                binding.iotViewPager.currentItem = tab.position
            }

            override fun onTabUnselected(tab: TabLayout.Tab) {}
            override fun onTabReselected(tab: TabLayout.Tab) {}
        })
        binding.iotViewPager.registerOnPageChangeCallback(object : OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                binding.iotTabLayout.getTabAt(position)?.select()
                loadManagePage(position, getOrInflatePage(position))
            }
        })
    }

    private fun ensurePage(index: Int): View {
        pageViews[index]?.let { return it }
        val layoutRes = when (index) {
            TAB_INDEX_MEMBERS -> R.layout.iot_page_manage_members
            TAB_INDEX_ROOMS -> R.layout.iot_page_manage_rooms
            TAB_INDEX_DEVICE_SHARE -> R.layout.iot_page_manage_device_share
            else -> R.layout.iot_page_manage_shared_to_me
        }
        val view = LayoutInflater.from(this).inflate(layoutRes, null, false)
        pageViews[index] = view
        return view
    }

    private fun loadManagePage(position: Int, pageView: View) {
        when (position) {
            TAB_INDEX_MEMBERS -> loadMembersIntoPage(pageView)
            TAB_INDEX_ROOMS -> loadRoomsIntoPage(pageView)
            TAB_INDEX_DEVICE_SHARE -> loadDeviceShareIntoPage(pageView)
            TAB_INDEX_SHARED_TO_ME -> loadSharedToMeIntoPage(pageView)
        }
    }

    private fun refreshPage(index: Int) {
        pageViews[index]?.let { loadManagePage(index, it) }
    }

    private class ManagePagerAdapter(
        private val getPage: (Int) -> View
    ) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

        override fun getItemCount() = 4
        override fun getItemViewType(position: Int) = position

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            val view = getPage(viewType)
            (view.parent as? ViewGroup)?.removeView(view)
            view.layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            return object : RecyclerView.ViewHolder(view) {}
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {}
    }

    private fun showFamilyMorePopup(anchor: View) {
        PopupMenuHelper.show(
            this, anchor, listOf(
                PopupMenuHelper.Item(
                    "✏️",
                    getString(R.string.iot_family_menu_rename)
                ) { showRenameFamilyDialog() },
                PopupMenuHelper.Item(
                    "➕",
                    getString(R.string.iot_family_menu_create)
                ) { showCreateFamilyDialog() },
                PopupMenuHelper.Item(
                    "🚪",
                    getString(R.string.iot_family_menu_leave)
                ) { confirmLeaveFamily() },
                PopupMenuHelper.Item(
                    "🗑️",
                    getString(R.string.iot_family_menu_delete)
                ) { confirmDeleteFamily() },
            )
        )
    }

    private fun showRenameFamilyDialog() {
        showInputBottomSheet(
            title = getString(R.string.iot_family_rename_title),
            hint = getString(R.string.iot_family_rename_hint),
            defaultText = currentFamilyName
        ) { newName -> updateFamilyName(newName) }
    }

    private fun updateFamilyName(newName: String) {
        val newInfo = TXIoTFamilyInfo().apply {
            familyId = currentFamilyId
            name = newName
        }
        val familyManager = getFamilyManager() ?: return
        familyManager.updateFamilyInfo(newInfo, uiCallback<Void>(R.string.iot_family_rename_failed) {
            currentFamilyName = newName
            binding.iotTvFamilyName.text = newName
            familyDataChanged = true
            show(getString(R.string.iot_family_rename_success))
        })
    }

    private fun showCreateFamilyDialog() {
        showInputBottomSheet(
            title = getString(R.string.iot_family_create_title),
            hint = getString(R.string.iot_family_create_hint),
            confirmText = getString(R.string.iot_btn_create)
        ) { name -> createFamily(name) }
    }

    private fun createFamily(name: String) {
        val familyManager = getFamilyManager() ?: return
        familyManager.createFamily(
            name,
            uiCallback<TXIoTFamilyInfo>(R.string.iot_family_create_failed) { result ->
                currentFamilyId = result.familyId ?: ""
                currentFamilyName = result.name ?: ""
                binding.iotTvFamilyName.text =
                    currentFamilyName.ifEmpty { getString(R.string.iot_family_default_name) }
                familyDataChanged = true
                show(getString(R.string.iot_family_create_success, result.name))
            })
    }

    private fun confirmDeleteFamily() {
        showConfirmBottomSheet(
            title = getString(R.string.iot_family_delete_title),
            message = getString(R.string.iot_family_delete_message, currentFamilyName)
        ) { deleteCurrentFamily() }
    }

    private fun deleteCurrentFamily() {
        if (currentFamilyId.isEmpty()) return
        val familyManager = getFamilyManager() ?: return
        familyManager.deleteFamily(
            currentFamilyId,
            uiCallback<Void>(R.string.iot_family_delete_failed) {
                show(getString(R.string.iot_family_delete_success))
                familyListChanged = true
                finishWithResult()
            })
    }

    private fun loadMembersIntoPage(pageView: View) {
        pageView.findViewById<Button>(R.id.iot_btnCreateInvite)
            .setOnClickListener { showInviteMemberDialog() }
        pageView.findViewById<Button>(R.id.iot_btnJoinFamily)
            .setOnClickListener { showJoinFamilyDialog() }
        val llMemberList = pageView.findViewById<LinearLayout>(R.id.iot_llMemberList)
        llMemberList.removeAllViews()
        val familyManager = getFamilyManager() ?: return
        familyManager.getMemberList(
            currentFamilyId,
            uiCallback<List<TXIoTUserInfo>>(R.string.iot_member_get_list_failed) { result ->
                result.forEachIndexed { index, user ->
                    llMemberList.addView(
                        createMemberItemView(
                            llMemberList,
                            user,
                            index == result.lastIndex
                        )
                    )
                }
            })
    }

    private fun createMemberItemView(
        parent: ViewGroup,
        user: TXIoTUserInfo,
        isLast: Boolean
    ): View {
        val item = LayoutInflater.from(this).inflate(R.layout.iot_item_manage_member, parent, false)
        val displayName = user.nickName ?: user.userId
        item.findViewById<TextView>(R.id.iot_tvMemberName).text = user.userId
        item.findViewById<TextView>(R.id.iot_tvMemberId).text =
            getString(R.string.iot_family_member_id_label, displayName)

        val currentUserId = TXIoTEngine.getInstance(this).loginUserInfo?.userId.orEmpty()
        val isSelf = user.userId == currentUserId

        val tvAvatar = item.findViewById<TextView>(R.id.iot_tvMemberAvatar)
        val flAvatarBg = item.findViewById<View>(R.id.iot_flAvatarBg)
        tvAvatar.text = displayName.take(1).uppercase()

        val btnDelete = item.findViewById<TextView>(R.id.iot_btnDeleteMember)
        val btnLeave = item.findViewById<TextView>(R.id.iot_btnLeaveFamily)
        val tvSelf = item.findViewById<TextView>(R.id.iot_tvMemberSelf)

        if (isSelf) {
            btnDelete.visibility = View.GONE
            btnLeave.visibility = View.VISIBLE
            btnLeave.setOnClickListener { confirmLeaveFamily() }
            tvSelf.visibility = View.VISIBLE
            flAvatarBg.setBackgroundResource(R.drawable.iot_bg_avatar_warning)
            tvAvatar.setTextColor(Color.parseColor("#FA8C16"))
        } else {
            btnDelete.visibility = View.VISIBLE
            btnLeave.visibility = View.GONE
            btnDelete.setOnClickListener { showMemberOptionsDialog(user) }
            tvSelf.visibility = View.GONE
            flAvatarBg.setBackgroundResource(R.drawable.iot_bg_menu_icon)
            tvAvatar.setTextColor(Color.parseColor("#006EFF"))
        }

        if (user.role == TXIoTFamilyRole.ADMIN) {
            item.findViewById<TextView>(R.id.iot_tvMemberRole).visibility = View.VISIBLE
        }

        return item
    }

    private fun showInviteMemberDialog() {
        val familyManager = getFamilyManager() ?: return
        familyManager.createFamilyInviteToken(
            currentFamilyId,
            uiCallback<String>(R.string.iot_member_invite_token_failed) { token ->
                showCopyableTokenDialog(
                    title = getString(R.string.iot_member_invite_token_title),
                    content = token,
                    clipLabel = "invite_token",
                    copiedToast = getString(R.string.iot_family_invite_code_copied),
                    copyBtnText = getString(R.string.iot_btn_copy)
                )
            })
    }

    private fun showJoinFamilyDialog() {
        showInputBottomSheet(
            title = getString(R.string.iot_member_join_family_title),
            hint = getString(R.string.iot_member_join_family_hint),
            confirmText = getString(R.string.iot_btn_confirm)
        ) { token -> joinFamilyByToken(token) }
    }

    private fun joinFamilyByToken(token: String) {
        val familyManager = getFamilyManager() ?: return
        familyManager.joinFamilyAsMember(
            token,
            uiCallback<Void>(R.string.iot_member_join_family_failed) {
                show(getString(R.string.iot_member_join_family_success))
                familyListChanged = true
                finishWithResult()
            })
    }

    private fun showMemberOptionsDialog(user: TXIoTUserInfo) {
        showConfirmBottomSheet(
            title = getString(R.string.iot_member_remove_title),
            message = getString(R.string.iot_member_remove_message, user.nickName ?: user.userId),
            confirmText = getString(R.string.iot_member_remove_btn)
        ) { deleteMember(user.userId) }
    }

    private fun deleteMember(userId: String) {
        val familyManager = getFamilyManager() ?: return
        familyManager.removeMemberFromFamily(
            currentFamilyId, userId,
            voidCallback(getString(R.string.iot_member_remove_success), R.string.iot_member_remove_failed) {
                familyDataChanged = true
                refreshPage(TAB_INDEX_MEMBERS)
            }
        )
    }

    private fun confirmLeaveFamily() {
        val currentUserId = TXIoTEngine.getInstance(this).loginUserInfo?.userId.orEmpty()
        showConfirmBottomSheet(
            title = getString(R.string.iot_family_leave_title),
            message = getString(R.string.iot_family_leave_message),
            confirmText = getString(R.string.iot_btn_confirm)
        ) { leaveFamily(currentUserId) }
    }

    private fun leaveFamily(userId: String) {
        val familyManager = getFamilyManager() ?: return
        familyManager.removeMemberFromFamily(
            currentFamilyId, userId,
            voidCallback(getString(R.string.iot_family_leave_success), R.string.iot_family_leave_failed) {
                familyListChanged = true
                finishWithResult()
            }
        )
    }

    private fun loadRoomsIntoPage(pageView: View) {
        pageView.findViewById<Button>(R.id.iot_btnCreateRoom)
            .setOnClickListener { showCreateRoomDialog() }
        val llRoomList = pageView.findViewById<LinearLayout>(R.id.iot_llRoomList)
        val llRoomEmpty = pageView.findViewById<LinearLayout>(R.id.iot_llRoomEmpty)
        llRoomList.removeAllViews()
        val familyManager = getFamilyManager() ?: return
        familyManager.getRoomList(
            currentFamilyId,
            uiCallback<List<TXIoTRoomInfo>>(R.string.iot_room_get_list_failed) { result ->
                if (result.isEmpty()) {
                    llRoomEmpty.visibility = View.VISIBLE
                    llRoomList.visibility = View.GONE
                } else {
                    llRoomEmpty.visibility = View.GONE
                    llRoomList.visibility = View.VISIBLE
                    result.forEachIndexed { index, room ->
                        llRoomList.addView(
                            createRoomItemView(
                                llRoomList,
                                room,
                                index == result.lastIndex
                            )
                        )
                    }
                }
            })
    }

    private fun createRoomItemView(parent: ViewGroup, room: TXIoTRoomInfo, isLast: Boolean): View {
        val item = LayoutInflater.from(this).inflate(R.layout.iot_item_manage_room, parent, false)
        item.findViewById<TextView>(R.id.iot_tvRoomName).text =
            room.name ?: getString(R.string.iot_room_options_default_title)
        item.findViewById<TextView>(R.id.iot_tvRoomDeviceCount).text =
            getString(R.string.iot_family_room_device_count, room.deviceCount)
        item.findViewById<ImageButton>(R.id.iot_btnRoomMore).setOnClickListener { anchor ->
            showRoomMorePopup(anchor, room)
        }
        return item
    }

    private fun showRoomMorePopup(anchor: View, room: TXIoTRoomInfo) {
        PopupMenuHelper.show(
            this, anchor, listOf(
                PopupMenuHelper.Item(
                    "✏️",
                    getString(R.string.iot_room_menu_rename)
                ) { showRenameRoomDialog(room) },
                PopupMenuHelper.Item(
                    "📱",
                    getString(R.string.iot_room_menu_bind_device)
                ) { showBindDeviceToRoomDialog(room) },
                PopupMenuHelper.Item(
                    "📤",
                    getString(R.string.iot_room_menu_unbind_device)
                ) { showUnbindDeviceFromRoomDialog(room) },
                PopupMenuHelper.Item(
                    "🗑️",
                    getString(R.string.iot_room_menu_delete)
                ) { confirmDeleteRoom(room.roomId, room.name ?: "") },
            )
        )
    }

    private fun showCreateRoomDialog() {
        showInputBottomSheet(
            title = getString(R.string.iot_room_create_title),
            hint = getString(R.string.iot_room_create_hint),
            confirmText = getString(R.string.iot_btn_create)
        ) { name -> createRoom(name) }
    }

    private fun createRoom(roomName: String) {
        val familyManager = getFamilyManager() ?: return
        familyManager.createRoom(
            currentFamilyId,
            roomName,
            uiCallback<TXIoTRoomInfo>(R.string.iot_room_create_failed) { result ->
                show(getString(R.string.iot_room_create_success, result.name ?: roomName))
                familyDataChanged = true
                refreshPage(TAB_INDEX_ROOMS)
            })
    }

    private fun showUnbindDeviceFromRoomDialog(room: TXIoTRoomInfo) {
        if (deviceList.isEmpty()) {
            show(getString(R.string.iot_room_no_device))
            return
        }
        showMenuBottomSheet(
            title = getString(R.string.iot_room_unbind_device_title),
            subtitle = room.name ?: getString(R.string.iot_room_options_default_title),
            items = deviceList.map { device -> MenuItem("📱", deviceDisplayName(device)) }
        ) { index ->
            val deviceId = deviceList.getOrNull(index)?.deviceId ?: return@showMenuBottomSheet
            unbindDeviceFromRoom(deviceId)
        }
    }

    private fun showBindDeviceToRoomDialog(room: TXIoTRoomInfo) {
        if (deviceList.isEmpty()) {
            show(getString(R.string.iot_room_no_device))
            return
        }
        showMenuBottomSheet(
            title = getString(R.string.iot_room_bind_device_title),
            subtitle = room.name ?: getString(R.string.iot_room_options_default_title),
            items = deviceList.map { device -> MenuItem("📱", deviceDisplayName(device)) }
        ) { index ->
            val deviceId = deviceList.getOrNull(index)?.deviceId ?: return@showMenuBottomSheet
            bindDeviceToRoom(deviceId, room.roomId)
        }
    }

    private fun bindDeviceToRoom(deviceId: TXIoTDeviceId, roomId: String) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.addDeviceToRoom(
            deviceId, currentFamilyId, roomId,
            voidCallback(
                getString(R.string.iot_room_bind_device_success),
                R.string.iot_room_bind_device_failed
            ) { refreshPage(TAB_INDEX_ROOMS) }
        )
    }

    private fun unbindDeviceFromRoom(deviceId: TXIoTDeviceId) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.removeDeviceFromRoom(
            deviceId, currentFamilyId,
            voidCallback(
                getString(R.string.iot_room_unbind_device_success),
                R.string.iot_room_unbind_device_failed
            ) { refreshPage(TAB_INDEX_ROOMS) }
        )
    }

    private fun showRenameRoomDialog(room: TXIoTRoomInfo) {
        showInputBottomSheet(
            title = getString(R.string.iot_room_rename_title),
            hint = getString(R.string.iot_room_rename_hint),
            defaultText = room.name ?: ""
        ) { newName -> renameRoom(room.roomId, newName) }
    }

    private fun confirmDeleteRoom(roomId: String, roomName: String) {
        showConfirmBottomSheet(
            title = getString(R.string.iot_room_delete_title),
            message = getString(R.string.iot_room_delete_message, roomName)
        ) { deleteRoom(roomId) }
    }

    private fun renameRoom(roomId: String, newName: String) {
        val familyManager = getFamilyManager() ?: return
        familyManager.setRoomName(
            currentFamilyId, roomId, newName,
            voidCallback(
                getString(R.string.iot_room_rename_success, newName),
                R.string.iot_room_rename_failed
            ) { familyDataChanged = true; refreshPage(TAB_INDEX_ROOMS) }
        )
    }

    private fun deleteRoom(roomId: String) {
        val familyManager = getFamilyManager() ?: return
        familyManager.deleteRoom(
            currentFamilyId, roomId,
            voidCallback(getString(R.string.iot_room_delete_success), R.string.iot_room_delete_failed) {
                familyDataChanged = true
                refreshPage(TAB_INDEX_ROOMS)
            }
        )
    }

    private fun loadDeviceShareIntoPage(pageView: View) {
        val llDeviceList = pageView.findViewById<LinearLayout>(R.id.iot_llDeviceList)
        val llDeviceEmpty = pageView.findViewById<LinearLayout>(R.id.iot_llDeviceEmpty)
        llDeviceList.removeAllViews()
        loadOwnDevices {
            if (deviceList.isEmpty()) {
                llDeviceEmpty.visibility = View.VISIBLE
                llDeviceList.visibility = View.GONE
            } else {
                llDeviceEmpty.visibility = View.GONE
                llDeviceList.visibility = View.VISIBLE
                deviceList.forEach { device ->
                    llDeviceList.addView(createDeviceItemView(llDeviceList, device))
                }
            }
        }
    }

    private fun createDeviceItemView(parent: ViewGroup, device: TXIoTDeviceInfo): View {
        val item = LayoutInflater.from(this).inflate(R.layout.iot_item_manage_device, parent, false)
        item.findViewById<TextView>(R.id.iot_tvDeviceName).text = deviceDisplayName(device)
        val tvSharedCount = item.findViewById<TextView>(R.id.iot_tvSharedCount)
        val btnMore = item.findViewById<ImageButton>(R.id.iot_btnDeviceMore)
        val deviceId = device.deviceId
        btnMore.setOnClickListener { anchor ->
            showDeviceMorePopup(anchor, device, deviceId)
        }

        if (deviceId != null) {
            val deviceManager = getDeviceManager()
            deviceManager?.getDeviceSharedUsers(
                deviceId,
                silentCallback<List<TXIoTUserInfo>>(
                    onOk = { users ->
                        tvSharedCount.visibility = View.VISIBLE
                        tvSharedCount.text =
                            getString(R.string.iot_family_shared_user_count, users.size)
                    }
                )
            )
        }
        return item
    }

    private fun showDeviceMorePopup(
        anchor: View,
        device: TXIoTDeviceInfo,
        deviceId: TXIoTDeviceId?
    ) {
        PopupMenuHelper.show(
            this, anchor, listOf(
                PopupMenuHelper.Item("📲", getString(R.string.iot_family_create_share)) {
                    if (deviceId != null) createDeviceSharingToken(deviceId)
                },
                PopupMenuHelper.Item("👥", getString(R.string.iot_family_shared_users)) {
                    showSharedUsersSheet(device)
                },
            )
        )
    }

    private fun showSharedUsersSheet(device: TXIoTDeviceInfo) {
        val deviceId = device.deviceId ?: return
        val deviceManager = getDeviceManager() ?: return
        deviceManager.getDeviceSharedUsers(
            deviceId,
            uiCallback<List<TXIoTUserInfo>>(R.string.iot_share_users_failed) { users ->
                if (users.isEmpty()) {
                    show(getString(R.string.iot_share_users_empty))
                    return@uiCallback
                }
                val sheet = CommonBottomSheet(this)
                sheet.setTitle(getString(R.string.iot_share_users_title))
                sheet.setHint(deviceDisplayName(device))
                sheet.hideConfirm()
                sheet.setDividerVisible(true)

                val listContainer = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(0, 0, 0, 8)
                }
                users.forEach { user ->
                    listContainer.addView(
                        createSharedUserCardView(listContainer, deviceId, user, sheet)
                    )
                }
                sheet.setContent(listContainer)
                sheet.show()
            })
    }

    private fun createSharedUserCardView(
        parent: ViewGroup,
        deviceId: TXIoTDeviceId,
        user: TXIoTUserInfo,
        sheet: CommonBottomSheet
    ): View {
        val item = LayoutInflater.from(this).inflate(R.layout.iot_item_family_menu, parent, false)
        item.findViewById<TextView>(R.id.iot_tvItemIcon).text = "👤"
        item.findViewById<TextView>(R.id.iot_tvItemName).text = user.userId
        item.findViewById<TextView>(R.id.iot_tvItemCheck).visibility = View.GONE
        item.findViewById<TextView>(R.id.iot_tvItemArrow).visibility = View.GONE
        val tvSub = item.findViewById<TextView>(R.id.iot_tvItemSub)
        tvSub.visibility = View.VISIBLE
        tvSub.text = user.nickName ?: getString(R.string.iot_family_default_user)

        val btnRemove = TextView(this).apply {
            text = getString(R.string.iot_family_remove_btn_short)
            setBackgroundResource(R.drawable.iot_bg_btn_danger_outline_small)
            setTextColor(Color.parseColor(DANGER_TEXT_COLOR))
            textSize = 13f
            setPadding(dip(12), dip(6), dip(12), dip(6))
        }
        (item as ViewGroup).addView(btnRemove)
        btnRemove.setOnClickListener {
            sheet.dismiss()
            confirmRemoveDeviceSharedUser(deviceId, user)
        }
        return item
    }

    private fun loadSharedToMeIntoPage(pageView: View) {
        val llSharedToMeList = pageView.findViewById<LinearLayout>(R.id.iot_llSharedToMeList)
        val llSharedToMeEmpty = pageView.findViewById<LinearLayout>(R.id.iot_llSharedToMeEmpty)
        pageView.findViewById<Button>(R.id.iot_btnBindShare).setOnClickListener {
            showBindSharedDeviceDialog()
        }
        llSharedToMeList.removeAllViews()
        val deviceManager = getDeviceManager() ?: return
        deviceManager.getDeviceListSharedWithMe(
            "", silentCallback<TXIoTPageResult<TXIoTDeviceInfo>>(
                onOk = { pageResult ->
                    renderSharedToMe(
                        llSharedToMeList,
                        llSharedToMeEmpty,
                        pageResult.dataList ?: emptyList()
                    )
                },
                onErr = { _, _ ->
                    llSharedToMeEmpty.visibility = View.VISIBLE
                    llSharedToMeList.visibility = View.GONE
                }
            ))
    }

    private fun renderSharedToMe(
        listContainer: LinearLayout,
        emptyView: LinearLayout,
        devices: List<TXIoTDeviceInfo>
    ) {
        if (devices.isEmpty()) {
            emptyView.visibility = View.VISIBLE
            listContainer.visibility = View.GONE
            return
        }
        emptyView.visibility = View.GONE
        listContainer.visibility = View.VISIBLE
        devices.forEachIndexed { index, device ->
            listContainer.addView(
                createSharedToMeItemView(
                    listContainer,
                    device,
                    index == devices.lastIndex
                )
            )
        }
    }

    private fun createSharedToMeItemView(
        parent: ViewGroup,
        device: TXIoTDeviceInfo,
        isLast: Boolean
    ): View {
        val item = LayoutInflater.from(this).inflate(R.layout.iot_item_shared_to_me, parent, false)
        item.findViewById<TextView>(R.id.iot_tvDeviceName).text = deviceDisplayName(device)
        item.findViewById<TextView>(R.id.iot_tvProductId).text =
            getString(R.string.iot_family_product_id_label, device.deviceId?.productId ?: "")
        val deviceId = device.deviceId
        item.findViewById<TextView>(R.id.iot_btnUnbind).setOnClickListener {
            if (deviceId != null) confirmUnbindSharedDevice(deviceId) {
                refreshPage(TAB_INDEX_SHARED_TO_ME)
            }
        }
        return item
    }

    private fun createDeviceSharingToken(deviceId: TXIoTDeviceId) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.createDeviceSharingToken(
            currentFamilyId,
            deviceId,
            uiCallback<String>(R.string.iot_share_token_failed) { token ->
                showCopyableTokenDialog(
                    title = getString(R.string.iot_family_share_token_title),
                    content = buildShareTokenJson(deviceId, token),
                    clipLabel = "share_token",
                    copiedToast = getString(R.string.iot_family_share_token_copied),
                    copyBtnText = getString(R.string.iot_family_copy_share_token)
                )
            })
    }

    private fun buildShareTokenJson(deviceId: TXIoTDeviceId, token: String): String =
        JSONObject().apply {
            put("productId", deviceId.productId ?: "")
            put("deviceName", deviceId.deviceName ?: "")
            put("token", token)
        }.toString(2)

    private fun showBindSharedDeviceDialog() {
        showInputBottomSheet(
            title = getString(R.string.iot_share_bind_title),
            hint = getString(R.string.iot_share_bind_hint),
            confirmText = getString(R.string.iot_btn_confirm)
        ) { input -> handleBindSharedDeviceInput(input) }
    }

    private fun handleBindSharedDeviceInput(input: String) {
        val payload = parseSharedTokenJson(input) ?: run {
            show(getString(R.string.iot_family_share_code_format_error))
            return
        }
        val sharedDeviceId = TXIoTDeviceId().apply {
            productId = payload.productId
            deviceName = payload.deviceName
        }
        bindSharedDevice(sharedDeviceId, payload.token)
    }

    private data class SharedTokenPayload(
        val productId: String,
        val deviceName: String,
        val token: String
    )

    private fun parseSharedTokenJson(input: String): SharedTokenPayload? {
        val json = try {
            JSONObject(input.trim())
        } catch (e: Exception) {
            return null
        }
        val productId = json.optString("productId").takeIf { it.isNotEmpty() }
        val deviceName = json.optString("deviceName").takeIf { it.isNotEmpty() }
        val token = json.optString("token").takeIf { it.isNotEmpty() }
        if (productId == null || deviceName == null || token == null) {
            show(getString(R.string.iot_family_share_code_incomplete))
            return null
        }
        return SharedTokenPayload(productId, deviceName, token)
    }

    private fun bindSharedDevice(deviceId: TXIoTDeviceId, token: String) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.bindDeviceSharedWithMe(
            deviceId,
            token,
            uiCallback<Void>(R.string.iot_share_bind_failed) {
                show(getString(R.string.iot_share_bind_success))
                refreshPage(TAB_INDEX_SHARED_TO_ME)
            })
    }

    private fun confirmRemoveDeviceSharedUser(deviceId: TXIoTDeviceId, user: TXIoTUserInfo) {
        showConfirmBottomSheet(
            title = getString(R.string.iot_share_remove_user_title),
            message = getString(R.string.iot_share_remove_user_message, user.userId)
        ) { removeDeviceSharedUser(deviceId, user.userId) }
    }

    private fun removeDeviceSharedUser(deviceId: TXIoTDeviceId, userId: String) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.removeDeviceSharedUser(
            deviceId, userId,
            voidCallback(
                getString(R.string.iot_share_remove_user_success),
                R.string.iot_share_remove_user_failed
            ) { refreshPage(TAB_INDEX_DEVICE_SHARE) }
        )
    }

    private fun confirmUnbindSharedDevice(deviceId: TXIoTDeviceId, afterSuccess: () -> Unit = {}) {
        showConfirmBottomSheet(
            title = getString(R.string.iot_share_unbind_title),
            message = getString(R.string.iot_share_unbind_message)
        ) { unbindSharedDevice(deviceId, afterSuccess) }
    }

    private fun unbindSharedDevice(deviceId: TXIoTDeviceId, afterSuccess: () -> Unit = {}) {
        val deviceManager = getDeviceManager() ?: return
        deviceManager.unbindDeviceSharedWithMe(
            deviceId,
            voidCallback(
                getString(R.string.iot_share_unbind_success),
                R.string.iot_share_unbind_failed,
                afterSuccess
            )
        )
    }

    private fun loadOwnDevices(onLoaded: () -> Unit = {}) {
        val deviceManager = getDeviceManager() ?: run { onLoaded(); return }
        deviceManager.getDeviceList(
            currentFamilyId, "",
            silentCallback<TXIoTPageResult<TXIoTDeviceInfo>>(
                onOk = { pageResult ->
                    deviceList.clear()
                    deviceList.addAll(pageResult.dataList ?: emptyList())
                    onLoaded()
                },
                onErr = { _, _ -> onLoaded() }
            )
        )
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

    private fun getFamilyManager(): TXIoTFamilyManager? =
        TXIoTEngine.getInstance(this).familyManager

    private fun getDeviceManager(): TXIoTDeviceManager? =
        TXIoTEngine.getInstance(this).deviceManager

    private fun deviceDisplayName(device: TXIoTDeviceInfo): String =
        device.aliasName?.takeIf { it.isNotBlank() }
            ?: device.deviceId?.deviceName
            ?: device.deviceId?.productId
            ?: getString(R.string.iot_family_unnamed)

    private fun dip(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private data class MenuItem(
        val icon: String,
        val label: String,
        val sublabel: String? = null,
        val isDanger: Boolean = false
    )

    private fun showMenuBottomSheet(
        title: String,
        subtitle: String? = null,
        items: List<MenuItem>,
        onItemClick: (index: Int) -> Unit
    ) {
        val sheet = CommonBottomSheet(this)
        sheet.setTitle(title)
        if (!subtitle.isNullOrEmpty()) {
            sheet.setHint(subtitle)
        }
        sheet.hideConfirm()
        sheet.setDividerVisible(items.isNotEmpty())

        val menuContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, 8)
        }
        items.forEachIndexed { index, menuItem ->
            menuContainer.addView(createMenuItemView(menuContainer, menuItem) {
                sheet.dismiss()
                onItemClick(index)
            })
        }
        sheet.setContent(menuContainer)
        sheet.show()
    }

    private fun createMenuItemView(
        parent: ViewGroup,
        menuItem: MenuItem,
        onClick: () -> Unit
    ): View {
        val item = LayoutInflater.from(this).inflate(R.layout.iot_item_family_menu, parent, false)
        item.findViewById<TextView>(R.id.iot_tvItemIcon).text = menuItem.icon
        val tvName = item.findViewById<TextView>(R.id.iot_tvItemName)
        tvName.text = menuItem.label
        item.findViewById<TextView>(R.id.iot_tvItemCheck).visibility = View.GONE
        if (menuItem.isDanger) {
            tvName.setTextColor(Color.parseColor(DANGER_TEXT_COLOR))
            item.findViewById<FrameLayout>(R.id.iot_flIconBg)
                .setBackgroundResource(R.drawable.iot_bg_menu_icon_danger)
        }

        val tvSub = item.findViewById<TextView>(R.id.iot_tvItemSub)
        if (menuItem.sublabel != null) {
            tvSub.visibility = View.VISIBLE
            tvSub.text = menuItem.sublabel
        }
        item.findViewById<TextView>(R.id.iot_tvItemArrow).visibility = View.VISIBLE
        item.setOnClickListener { onClick() }
        return item
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
            gravity = Gravity.CENTER
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

    private fun showConfirmBottomSheet(
        title: String,
        message: String,
        confirmText: String = "",
        onConfirm: () -> Unit
    ) {
        val sheet = CommonBottomSheet(this)
        sheet.setTitle(title)
        sheet.setHint(null)
        sheet.setDividerVisible(false)

        val msgTv = TextView(this).apply {
            text = message
            textSize = 14f
            setTextColor(Color.parseColor("#9DA3B0"))
            gravity = Gravity.CENTER
            setLineSpacing(5f, 1f)
            setPadding(16, 8, 16, 16)
        }
        sheet.setContent(msgTv)
        sheet.setConfirmDismiss(
            confirmText.ifEmpty { getString(R.string.iot_btn_delete) },
            onConfirm
        )
        sheet.setConfirmDanger(true)
        sheet.show()
    }

    private fun showCopyableTokenDialog(
        title: String,
        content: String,
        clipLabel: String,
        copiedToast: String,
        copyBtnText: String
    ) {
        val sheet = CommonBottomSheet(this)
        sheet.setTitle(title)
        sheet.setHint(null)
        sheet.setDividerVisible(false)

        val editText = EditText(this).apply {
            setText(content)
            isFocusable = false
            isFocusableInTouchMode = false
            setTextIsSelectable(true)
            setBackgroundResource(R.drawable.iot_bg_dialog_input)
            setPadding(36, 0, 36, 0)
            setTextColor(Color.parseColor("#15161A"))
            textSize = 15f
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, dip(54))
        }
        sheet.setContent(editText)

        sheet.setConfirmDismiss(copyBtnText) {
            copyToClipboard(clipLabel, content)
            show(copiedToast)
        }

        sheet.show()
    }

    private fun copyToClipboard(label: String, text: String) {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
    }
}
