package com.tencent.iot.txiotdemo.activity

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.activity.MessageActivity.MessageAdapter
import com.tencent.iot.txiotdemo.activity.MessageActivity.MessageItem
import com.tencent.iot.txiotdemo.activity.MessageActivity.MessageItem.PushItem
import com.tencent.iot.txiotdemo.databinding.IotFragmentMessageListBinding

class MessageListFragment : Fragment() {

    companion object {
        private const val ARG_TYPE = "type"

        const val TYPE_DEVICE = 0
        const val TYPE_FAMILY = 1
        const val TYPE_NOTIFICATION = 2

        const val TYPE_PUSH = 3

        fun newInstance(type: Int): MessageListFragment {
            return MessageListFragment().apply {
                arguments = Bundle().also { it.putInt(ARG_TYPE, type) }
            }
        }
    }

    private var _binding: IotFragmentMessageListBinding? = null
    private val binding get() = _binding!!

    private val type by lazy { arguments?.getInt(ARG_TYPE) ?: TYPE_DEVICE }
    private val messageList = mutableListOf<MessageItem>()
    private lateinit var adapter: MessageAdapter
    private var nextPageToken = ""

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View {
        _binding = IotFragmentMessageListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        adapter = MessageAdapter(messageList) { item ->
            when (item) {
                is PushItem -> {
                    if (!item.isRead) {
                        item.isRead = true
                        adapter.notifyDataSetChanged()
                    }
                }
            }
        }

        binding.iotRvMessageList.layoutManager = LinearLayoutManager(requireContext())
        binding.iotRvMessageList.adapter = adapter

        binding.iotSwipeRefreshLayout.setOnRefreshListener {
            refresh()
        }

        binding.iotBtnLoadMore.setOnClickListener {
            loadNextPage()
        }

        binding.iotSwipeRefreshLayout.isEnabled = false
        binding.iotBtnLoadMore.visibility = View.GONE
        updateEmptyState()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    fun addPushMessage(item: PushItem) {
        messageList.add(0, item)
        val b = _binding ?: return
        adapter.notifyItemInserted(0)
        b.iotRvMessageList.scrollToPosition(0)
        updateEmptyState()
    }

    fun refreshPushMessages(pushList: List<PushItem>) {
        messageList.clear()
        messageList.addAll(pushList)
        _binding ?: return
        adapter.notifyDataSetChanged()
        updateEmptyState()
    }

    fun markAllRead() {
        messageList.forEach { item ->
            when (item) {
                is PushItem -> item.isRead = true
            }
        }
        adapter.notifyDataSetChanged()
    }

    fun refresh() {
        if (type == TYPE_PUSH) return
        nextPageToken = ""
        messageList.clear()
        adapter.notifyDataSetChanged()
        updateEmptyState()
    }

    private fun loadNextPage() {
        Toast.makeText(context, getString(R.string.iot_message_all_loaded), Toast.LENGTH_SHORT).show()
    }

    private fun updateEmptyState() {
        binding.iotEmptyState.visibility = if (messageList.isEmpty()) View.VISIBLE else View.GONE
    }
}
