package com.tencent.iot.txiotdemo.common

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.databinding.IotDialogCommonBottomSheetBinding

class CommonBottomSheet(private val context: Context) {

    private val binding = IotDialogCommonBottomSheetBinding.inflate(LayoutInflater.from(context))
    val dialog: BottomSheetDialog = BottomSheetDialog(context, R.style.iot_BottomSheetDialogTheme)

    init {
        dialog.setContentView(binding.root)
        binding.iotBtnCommonCancel.setOnClickListener { dialog.dismiss() }
        binding.iotBtnCommonConfirm.setOnClickListener { dialog.dismiss() }
    }

    fun setTitle(text: CharSequence): CommonBottomSheet {
        binding.iotTvCommonTitle.text = text
        return this
    }

    fun setHint(text: CharSequence?): CommonBottomSheet {
        if (text.isNullOrEmpty()) {
            binding.iotTvCommonHint.visibility = View.GONE
        } else {
            binding.iotTvCommonHint.visibility = View.VISIBLE
            binding.iotTvCommonHint.text = text
        }
        return this
    }

    fun setContent(view: View): CommonBottomSheet {
        binding.iotFlCommonContent.removeAllViews()
        val height = view.layoutParams?.height?.takeIf { it > 0 }
            ?: ViewGroup.LayoutParams.WRAP_CONTENT
        binding.iotFlCommonContent.addView(
            view,
            ViewGroup.LayoutParams.MATCH_PARENT,
            height
        )
        return this
    }

    fun inflateContent(layoutRes: Int, attachToRoot: Boolean = false): View {
        val view =
            LayoutInflater.from(context).inflate(layoutRes, binding.iotFlCommonContent, attachToRoot)
        if (!attachToRoot) {
            binding.iotFlCommonContent.removeAllViews()
            binding.iotFlCommonContent.addView(view)
        }
        return view
    }

    fun setDividerVisible(visible: Boolean): CommonBottomSheet {
        binding.iotVCommonDivider.visibility = if (visible) View.VISIBLE else View.GONE
        return this
    }

    fun getConfirmButton(): TextView = binding.iotBtnCommonConfirm

    fun setConfirm(text: String, onClick: (() -> Unit)?): CommonBottomSheet {
        binding.iotBtnCommonConfirm.visibility = View.VISIBLE
        binding.iotBtnCommonConfirm.text = text
        binding.iotBtnCommonConfirm.setOnClickListener {
            onClick?.invoke()
        }
        return this
    }

    fun setConfirmDismiss(text: String, onClick: (() -> Unit)?): CommonBottomSheet {
        binding.iotBtnCommonConfirm.visibility = View.VISIBLE
        binding.iotBtnCommonConfirm.text = text
        binding.iotBtnCommonConfirm.setOnClickListener {
            dialog.dismiss()
            onClick?.invoke()
        }
        return this
    }

    fun hideConfirm(): CommonBottomSheet {
        binding.iotBtnCommonConfirm.visibility = View.GONE
        return this
    }

    fun setConfirmDanger(danger: Boolean): CommonBottomSheet {
        if (danger) {
            binding.iotBtnCommonConfirm.setBackgroundResource(R.drawable.iot_bg_danger_button)
        } else {
            binding.iotBtnCommonConfirm.setBackgroundResource(R.drawable.iot_bg_primary_button)
        }
        return this
    }

    fun setConfirmOutlined(): CommonBottomSheet {
        binding.iotBtnCommonConfirm.setBackgroundResource(R.drawable.iot_bg_outline_button)
        binding.iotBtnCommonConfirm.setTextColor(0xFF006EFF.toInt())
        return this
    }

    fun getCancelButton(): TextView = binding.iotBtnCommonCancel

    fun setCancel(
        text: String = context.getString(R.string.iot_btn_cancel),
        onClick: (() -> Unit)? = null
    ): CommonBottomSheet {
        binding.iotBtnCommonCancel.text = text
        binding.iotBtnCommonCancel.setOnClickListener {
            onClick?.invoke() ?: dialog.dismiss()
        }
        return this
    }

    fun getButtonsContainer(): ViewGroup = binding.iotLlCommonButtons

    fun show() = dialog.show()
    fun dismiss() = dialog.dismiss()
    fun isShowing(): Boolean = dialog.isShowing
}
