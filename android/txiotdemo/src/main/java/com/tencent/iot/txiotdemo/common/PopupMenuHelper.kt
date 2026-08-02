package com.tencent.iot.txiotdemo.common

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.PopupWindow
import androidx.core.content.ContextCompat
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.databinding.IotItemPopupMenuBinding

object PopupMenuHelper {

    data class Item(
        val icon: String = "",
        val label: String,
        val destructive: Boolean = false,
        val onClick: () -> Unit
    )

    fun show(
        context: android.content.Context,
        anchor: View,
        items: List<Item>
    ) {
        val density = context.resources.displayMetrics.density
        val hasIcons = items.any { it.icon.isNotEmpty() }

        val contentView = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            val padH = (4 * density).toInt()
            val padV = (8 * density).toInt()
            setPadding(padH, padV, padH, padV)
        }

        val popupWindow = PopupWindow(
            contentView,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            true
        ).apply {
            isOutsideTouchable = true
            setBackgroundDrawable(ContextCompat.getDrawable(context, R.drawable.iot_bg_popup_menu))
            elevation = 8f * density
        }

        items.forEachIndexed { index, item ->
            val binding =
                IotItemPopupMenuBinding.inflate(LayoutInflater.from(context), contentView, false)
            binding.iotTvItemName.text = item.label

            if (item.destructive) {
                binding.iotTvItemName.setTextColor(Color.RED)
                binding.iotTvItemIcon.setTextColor(Color.RED)
            }

            if (hasIcons) {
                binding.iotTvItemIcon.text = item.icon
                if (item.icon.isEmpty()) {
                    binding.iotTvItemIcon.visibility = View.INVISIBLE
                }
            } else {
                binding.iotTvItemIcon.visibility = View.INVISIBLE
                binding.iotSpacer.visibility = View.INVISIBLE
            }

            val normalBg = binding.root.background
            val pressedBg = ColorDrawable(Color.parseColor("#0D000000"))
            binding.root.setOnTouchListener { v, event ->
                when (event.action) {
                    android.view.MotionEvent.ACTION_DOWN -> v.background = pressedBg
                    android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                        v.background = normalBg
                        if (event.action == android.view.MotionEvent.ACTION_UP) {
                            v.performClick()
                        }
                    }
                }
                true
            }

            binding.root.setOnClickListener {
                popupWindow.dismiss()
                item.onClick()
            }
            contentView.addView(binding.root)

            if (index < items.size - 1) {
                val divider = View(context).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        (1 * density).toInt()
                    )
                    setBackgroundColor(Color.parseColor("#F2F4F8"))
                }
                contentView.addView(divider)
            }
        }

        contentView.measure(
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val popupWidth = (contentView.measuredWidth + 32 * density).toInt()
        val yOffset = (4 * density).toInt()
        popupWindow.width = popupWidth
        popupWindow.showAsDropDown(anchor, anchor.width - popupWidth, yOffset)
    }
}
