package com.tencent.iot.txiotdemo.core.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.util.isCeilingLamp
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo

class DeviceAdapter(private val deviceList: List<TXIoTDeviceInfo>) :
    RecyclerView.Adapter<DeviceAdapter.DeviceViewHolder>() {

    private var itemClickListener: ((Int, TXIoTDeviceInfo) -> Unit)? = null
    private var menuClickListener: ((Int, TXIoTDeviceInfo, View) -> Unit)? = null

    private val statusMap = mutableMapOf<String, Boolean>()

    class DeviceViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val tvDeviceName: TextView = itemView.findViewById(R.id.iot_tv_device_name)
        val ivDeviceIcon: ImageView = itemView.findViewById(R.id.iot_iv_device_icon)
        val tvDeviceStatus: TextView = itemView.findViewById(R.id.iot_tv_device_status)
        val indicatorStatus: View = itemView.findViewById(R.id.iot_indicator_status)
        val btnDeviceMenu: ImageView = itemView.findViewById(R.id.iot_btn_device_menu)
        val tvPid: TextView = itemView.findViewById(R.id.iot_tv_pid)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DeviceViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.iot_item_device_card, parent, false)
        return DeviceViewHolder(view)
    }

    override fun onBindViewHolder(holder: DeviceViewHolder, position: Int) {
        val device = deviceList[position]

        holder.tvDeviceName.text = displayNameOf(device)
        if (device.isCeilingLamp) {
            holder.ivDeviceIcon.setImageResource(R.drawable.iot_ic_lamp_device)
        } else {
            Glide.with(holder.itemView.context).load(device.iconUrl).into(holder.ivDeviceIcon)
        }

        val deviceKey = "${device.deviceId?.productId}_${device.deviceId?.deviceName}"
        val isOnline = statusMap[deviceKey] ?: false
        if (isOnline) {
            holder.tvDeviceStatus.text =
                holder.itemView.context.getString(R.string.iot_device_status_online)
            holder.indicatorStatus.setBackgroundResource(R.drawable.iot_bg_status_online)
        } else {
            holder.tvDeviceStatus.text =
                holder.itemView.context.getString(R.string.iot_device_status_offline)
            holder.indicatorStatus.setBackgroundResource(R.drawable.iot_bg_status_offline)
        }

        holder.tvPid.text =
            "${device.deviceId?.productId ?: ""}/${device.deviceId?.deviceName ?: ""}"

        holder.itemView.setOnClickListener {
            itemClickListener?.invoke(position, device)
        }

        holder.btnDeviceMenu.setOnClickListener {
            menuClickListener?.invoke(position, device, holder.btnDeviceMenu)
        }
    }

    override fun getItemCount(): Int = deviceList.size

    fun updateStatus(newStatusMap: Map<String, Boolean>) {
        statusMap.clear()
        statusMap.putAll(newStatusMap)
        notifyDataSetChanged()
    }

    fun setOnItemClickListener(listener: (Int, TXIoTDeviceInfo) -> Unit) {
        itemClickListener = listener
    }

    fun setOnMenuClickListener(listener: (Int, TXIoTDeviceInfo, View) -> Unit) {
        menuClickListener = listener
    }

    private fun displayNameOf(device: TXIoTDeviceInfo): String =
        device.aliasName?.takeIf { it.isNotBlank() }
            ?: device.deviceId?.deviceName
            ?: ""
}
