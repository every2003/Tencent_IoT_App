package com.tencent.iot.txiotdemo.activity

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.recyclerview.widget.RecyclerView
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.activity.MessageActivity.MessageItem.PushItem
import com.tencent.iot.txiotdemo.databinding.IotActivityMessageBinding
import com.tencent.iot.txiotdemo.databinding.IotItemMessageBinding
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngine.TXIoTEngineListener
import com.tencent.liteav.iot.TXIoTEngine.TXIoTPushMessage
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MessageActivity : BaseActivity<IotActivityMessageBinding>() {

    sealed class MessageItem {
        data class PushItem(
            val title: String,
            val content: String,
            val timestamp: Long,
            var isRead: Boolean = false
        ) : MessageItem()
    }

    private val pushMessageList = mutableListOf<PushItem>()

    private var pushFragment: MessageListFragment? = null

    private val iotEngineListener = object : TXIoTEngineListener() {
        override fun onReceivePushMessage(pushMessage: TXIoTPushMessage) {
            runOnUiThread { handlePushMessage(pushMessage) }
        }
    }

    private fun handlePushMessage(pushMessage: TXIoTPushMessage) {
        val deviceId = pushMessage.deviceId
        val deviceName = deviceId?.deviceName ?: deviceId?.productId
        ?: getString(R.string.iot_message_unknown_device)
        val (title, content) = when (pushMessage.type) {
            TXIoTEngine.TXIoTPushMessageType.STATUS_CHANGE ->
                getString(R.string.iot_message_device_status_changed) to getString(
                    R.string.iot_message_device_status_content,
                    deviceName
                )

            else ->
                getString(R.string.iot_message_push_notification) to getString(
                    R.string.iot_message_push_content,
                    deviceName
                )
        }
        val item = PushItem(
            title = title,
            content = content,
            timestamp = System.currentTimeMillis(),
            isRead = false
        )
        pushMessageList.add(0, item)
        pushFragment?.addPushMessage(item)
    }

    override fun getViewBinding(): IotActivityMessageBinding =
        IotActivityMessageBinding.inflate(layoutInflater)

    override fun initView() {
        setImmersiveStatusBar()

        val fragment = MessageListFragment.newInstance(MessageListFragment.TYPE_PUSH)
        pushFragment = fragment
        supportFragmentManager.beginTransaction()
            .replace(R.id.iot_fragment_container, fragment)
            .commit()
    }

    override fun setListener() {
        binding.iotBtnBack.setOnClickListener { finish() }
        binding.iotTvMarkAllRead.setOnClickListener {
            pushFragment?.markAllRead()
            pushMessageList.forEach { it.isRead = true }
            Toast.makeText(this, getString(R.string.iot_message_all_marked_read), Toast.LENGTH_SHORT)
                .show()
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

    class MessageAdapter(
        private val data: MutableList<MessageItem>,
        private val onItemClick: (MessageItem) -> Unit
    ) : RecyclerView.Adapter<MessageAdapter.VH>() {

        class VH(val binding: IotItemMessageBinding) : RecyclerView.ViewHolder(binding.root)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH =
            VH(IotItemMessageBinding.inflate(LayoutInflater.from(parent.context), parent, false))

        override fun onBindViewHolder(holder: VH, position: Int) {
            val item = data[position]
            with(holder.binding) {
                when (item) {
                    is PushItem -> {
                        iotTvMsgTitle.text = item.title
                        iotTvMsgContent.text = item.content
                        iotTvMsgTime.text = formatTime(item.timestamp)
                        iotVUnreadDot.visibility = if (!item.isRead) View.VISIBLE else View.GONE
                        iotTvMsgTitle.typeface =
                            if (!item.isRead) android.graphics.Typeface.DEFAULT_BOLD
                            else android.graphics.Typeface.DEFAULT
                    }
                }
                root.setOnClickListener { onItemClick(item) }
            }
        }

        override fun getItemCount() = data.size

        private fun formatTime(timestamp: Long): String {
            if (timestamp < 0) return ""
            return try {
                SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(timestamp))
            } catch (e: Exception) {
                ""
            }
        }
    }
}
