package com.tencent.iot.txiotdemo.core.adapter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.tencent.iot.txiotdemo.core.holder.BaseHolder

abstract class BaseAdapter(context: Context, list: List<Any>) :
    RecyclerView.Adapter<BaseHolder<*, *>>() {

    private val mList = list
    private var itemListener: OnItemListener? = null
    val mContext = context
    protected val mInflater by lazy { LayoutInflater.from(mContext) }

    abstract fun createHolder(parent: ViewGroup, viewType: Int): BaseHolder<*, *>

    fun setOnItemListener(onItemListener: OnItemListener) {
        itemListener = onItemListener
    }

    fun onClickItem(holder: BaseHolder<*, *>, clickView: View, position: Int) {
        itemListener?.onItemClick(holder, clickView, position)
    }

    override fun getItemCount(): Int {
        return mList.size
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): BaseHolder<*, *> {
        val holder = createHolder(parent, viewType)
        holder.setAdapter(this)
        return holder
    }

    override fun onBindViewHolder(holder: BaseHolder<*, *>, position: Int) {
        if (position < mList.size && holder.parseData(data(position)))
            holder.show(holder, position)
    }

    fun data(position: Int): Any {
        return mList[position]
    }

}

interface OnItemListener {
    fun onItemClick(holder: BaseHolder<*, *>, clickView: View, position: Int)
}
