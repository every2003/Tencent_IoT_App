package com.tencent.iot.txiotdemo.common.widget

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.util.Utils

class SettingRadioGroup @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : LinearLayout(context, attrs, defStyleAttr) {

    private val tvTitle: TextView
    private val rgOptions: RadioGroup

    private var options: List<Pair<String, String>> = emptyList()

    init {
        orientation = VERTICAL
        LayoutInflater.from(context).inflate(R.layout.iot_view_setting_radio_group, this, true)
        tvTitle = findViewById(R.id.iot_tv_setting_title)
        rgOptions = findViewById(R.id.iot_rg_setting_options)
    }

    fun setTitle(text: CharSequence) {
        tvTitle.text = text
    }

    fun setOptions(items: List<Pair<String, String>>) {
        options = items
        rgOptions.removeAllViews()
        rgOptions.orientation = HORIZONTAL
        items.forEachIndexed { index, (label, _) ->
            val rb = RadioButton(context).apply {
                text = label
                textSize = 14f
                setTextColor(0xFF15161A.toInt())
                id = index
                val lp = LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.WRAP_CONTENT
                )
                if (index > 0) {
                    lp.marginStart = Utils.dp2px(context, 20)
                }
                layoutParams = lp
            }
            rgOptions.addView(rb)
        }
    }

    fun setSelectedValue(value: String) {
        val index = options.indexOfFirst { it.second == value }
        if (index >= 0) {
            rgOptions.check(index)
        }
    }

    fun getSelectedValue(): String? {
        val checkedId = rgOptions.checkedRadioButtonId
        if (checkedId < 0 || checkedId >= options.size) return null
        return options[checkedId].second
    }
}
