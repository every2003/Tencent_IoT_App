package com.tencent.iot.txiotdemo.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.resource.bitmap.CenterCrop
import com.bumptech.glide.load.resource.bitmap.RoundedCorners
import com.bumptech.glide.request.RequestOptions
import com.tencent.iot.txiotdemo.R
import com.tencent.liteav.iot.TXIoTCloudStorage.TXIoTEvent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CloudStorageEventAdapter(
    private val data: List<TXIoTEvent>,
    private val onPlayEvent: (TXIoTEvent) -> Unit,
    private val onViewSnapshot: (TXIoTEvent) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private val timeFormatter = SimpleDateFormat("HH:mm:ss", Locale.CHINA)

    companion object {
        private const val VIEW_TYPE_VIDEO = 0
        private const val VIEW_TYPE_SNAPSHOT = 1
    }

    private var eventTypeNames: Map<String, String>? = null

    private fun getEventTypeNames(context: android.content.Context): Map<String, String> {
        return eventTypeNames ?: synchronized(this) {
            eventTypeNames ?: mapOf(
                "1" to context.getString(R.string.iot_event_type_doorbell),
                "2" to context.getString(R.string.iot_event_type_motion),
                "3" to context.getString(R.string.iot_event_type_human),
                "4" to context.getString(R.string.iot_event_type_intrusion),
                "5" to context.getString(R.string.iot_event_type_loitering),
                "6" to context.getString(R.string.iot_event_type_abnormal_sound),
                "100" to context.getString(R.string.iot_event_type_face_recognition),
                "101" to context.getString(R.string.iot_event_type_door_open)
            ).also { eventTypeNames = it }
        }
    }

    class VideoViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val ivThumbnail: ImageView = itemView.findViewById(R.id.iot_ivThumbnail)
        val tvEventTime: TextView = itemView.findViewById(R.id.iot_tvEventTime)
        val tvEventType: TextView = itemView.findViewById(R.id.iot_tvEventType)
        val tvEventDuration: TextView = itemView.findViewById(R.id.iot_tvEventDuration)
    }

    class SnapshotViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val ivThumbnail: ImageView = itemView.findViewById(R.id.iot_ivThumbnail)
        val tvEventTime: TextView = itemView.findViewById(R.id.iot_tvEventTime)
        val tvEventType: TextView = itemView.findViewById(R.id.iot_tvEventType)
    }

    override fun getItemViewType(position: Int): Int =
        if (isSnapshotEvent(data[position])) VIEW_TYPE_SNAPSHOT else VIEW_TYPE_VIDEO

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        if (viewType == VIEW_TYPE_SNAPSHOT) {
            val view = inflater.inflate(R.layout.iot_item_cloud_storage_snapshot_event, parent, false)
            return SnapshotViewHolder(view)
        }
        val view = inflater.inflate(R.layout.iot_item_cloud_storage_event, parent, false)
        return VideoViewHolder(view)
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val event = data[position]
        when (holder) {
            is VideoViewHolder -> bindVideo(holder, event)
            is SnapshotViewHolder -> bindSnapshot(holder, event)
        }
    }

    override fun getItemCount(): Int = data.size

    private fun bindVideo(holder: VideoViewHolder, event: TXIoTEvent) {
        holder.tvEventTime.text = timeFormatter.format(Date(event.eventTimeMs))
        holder.tvEventType.text = formatEventType(holder.itemView.context, event.eventType)
        holder.tvEventDuration.text = formatDuration(event.durationMs)
        loadThumbnail(holder.ivThumbnail, event.thumbnailUrl)
        holder.itemView.setOnClickListener { onPlayEvent(event) }
    }

    private fun bindSnapshot(holder: SnapshotViewHolder, event: TXIoTEvent) {
        holder.tvEventTime.text = timeFormatter.format(Date(event.eventTimeMs))
        holder.tvEventType.text = formatEventType(holder.itemView.context, event.eventType)
        loadThumbnail(holder.ivThumbnail, event.thumbnailUrl)
        holder.itemView.setOnClickListener { onViewSnapshot(event) }
    }

    private fun loadThumbnail(imageView: ImageView, thumb: String?) {
        if (thumb.isNullOrEmpty()) {
            imageView.setImageResource(R.drawable.iot_bg_cloud_thumbnail)
            return
        }
        val cornerPx = dp2px(imageView.context, 12)
        val requestOptions = RequestOptions()
            .transform(CenterCrop(), RoundedCorners(cornerPx))
            .placeholder(R.drawable.iot_bg_cloud_thumbnail)
            .error(R.drawable.iot_bg_cloud_thumbnail)
        Glide.with(imageView.context)
            .load(thumb)
            .apply(requestOptions)
            .into(imageView)
    }

    private fun isSnapshotEvent(event: TXIoTEvent): Boolean =
        event.videoFiles.isNullOrEmpty()

    private fun formatEventType(context: android.content.Context, eventType: String?): String {
        if (eventType.isNullOrEmpty()) return context.getString(R.string.iot_event_type_default)
        return getEventTypeNames(context)[eventType] ?: eventType
    }

    private fun formatDuration(durationMs: Long): String {
        val totalSec = (durationMs / 1000).coerceAtLeast(0)
        if (totalSec < 60) return "${totalSec}s"
        val m = totalSec / 60
        val s = totalSec % 60
        return String.format(Locale.CHINA, "%d:%02d", m, s)
    }

    private fun dp2px(context: android.content.Context, dp: Int): Int {
        return (context.resources.displayMetrics.density * dp + 0.5f).toInt()
    }
}
