package com.tencent.iot.txiotdemo.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.view.isVisible
import androidx.recyclerview.widget.RecyclerView
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.databinding.IotItemChannelVideoBinding
import com.tencent.rtmp.ui.TXCloudVideoView

class MultiChannelAdapter(
    private val channelIds: List<Int>
) : RecyclerView.Adapter<MultiChannelAdapter.ChannelViewHolder>() {

    class ChannelViewHolder(val binding: IotItemChannelVideoBinding) :
        RecyclerView.ViewHolder(binding.root) {
        val videoView: TXCloudVideoView get() = binding.iotChannelVideoView
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ChannelViewHolder {
        val binding = IotItemChannelVideoBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return ChannelViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ChannelViewHolder, position: Int) {
        val channelId = channelIds[position]
        holder.binding.iotTvChannelLabel.text =
            holder.itemView.context.getString(R.string.iot_channel_label, channelId)
        holder.binding.iotChannelLoadingOverlay.isVisible = true
        holder.binding.iotChannelLoadingProgressBar.isVisible = true
        viewHolderMap[channelId] = holder
    }

    override fun getItemCount(): Int = channelIds.size

    fun getVideoView(channelId: Int): TXCloudVideoView? {
        val index = channelIds.indexOf(channelId)
        return if (index >= 0) {
            viewHolderMap[channelId]?.videoView
        } else null
    }

    fun onFirstFrame(channelId: Int) {
        val holder = viewHolderMap[channelId] ?: return
        holder.binding.iotChannelLoadingOverlay.isVisible = false
        holder.binding.iotChannelLoadingProgressBar.isVisible = false
    }

    fun onPlayStateChanged(channelId: Int, loading: Boolean) {
        val holder = viewHolderMap[channelId] ?: return
        holder.binding.iotChannelLoadingProgressBar.isVisible = loading
        holder.binding.iotChannelLoadingOverlay.isVisible = loading
    }

    fun hideAllLoading() {
        viewHolderMap.values.forEach { holder ->
            holder.binding.iotChannelLoadingProgressBar.isVisible = false
            holder.binding.iotChannelLoadingOverlay.isVisible = false
        }
    }

    fun showAllLoading() {
        viewHolderMap.values.forEach { holder ->
            holder.binding.iotChannelLoadingProgressBar.isVisible = true
            holder.binding.iotChannelLoadingOverlay.isVisible = true
        }
    }

    private val viewHolderMap = mutableMapOf<Int, ChannelViewHolder>()
}
