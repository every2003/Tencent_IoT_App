package com.tencent.iot.txiotdemo.common.util;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.HashMap;
import java.util.Map;

public class SharePreferenceUtil {

    public static boolean saveInt(Context context, String fileName, String key, int value) {
        SharedPreferences.Editor editor = context.getSharedPreferences(fileName, Context.MODE_PRIVATE).edit();
        Map<String, Integer> map = new HashMap<>();
        map.put(key, value);
        editor.putInt(key, value);
        return editor.commit();
    }

    public static boolean saveLong(Context context, String fileName, String key, long value) {
        SharedPreferences.Editor editor = context.getSharedPreferences(fileName, Context.MODE_PRIVATE).edit();
        Map<String, Long> map = new HashMap<>();
        map.put(key, value);
        editor.putLong(key, value);
        return editor.commit();
    }

    public static boolean saveBoolean(Context context, String fileName, String key, boolean value) {
        SharedPreferences.Editor editor = context.getSharedPreferences(fileName, Context.MODE_PRIVATE).edit();
        Map<String, Boolean> map = new HashMap<>();
        map.put(key, value);
        editor.putBoolean(key, value);
        return editor.commit();
    }

    public static boolean saveString(Context context, String fileName, String key, String value) {
        Map<String, String> map = new HashMap<>();
        map.put(key, value);
        return saveString(context, fileName, map);
    }

    public static boolean clearString(Context context, String fileName, String key) {
        Map<String, String> map = new HashMap<>();
        map.put(key, null);
        return saveString(context, fileName, map);
    }

    public static boolean saveString(Context context, String fileName, Map<String, String> params) {
        SharedPreferences.Editor editor = context.getSharedPreferences(fileName, Context.MODE_PRIVATE).edit();
        for (String key : params.keySet()) {
            String value = params.get(key);
            editor.putString(key, value);
        }
        return editor.commit();
    }

    public static int getInt(Context context, String fileName, String key) {
        SharedPreferences sp = context.getSharedPreferences(fileName, Context.MODE_PRIVATE);
        return sp.getInt(key, 0);
    }

    public static long getLong(Context context, String fileName, String key) {
        SharedPreferences sp = context.getSharedPreferences(fileName, Context.MODE_PRIVATE);
        return sp.getLong(key, 0);
    }

    public static long getLong(Context context, String fileName, String key, long defaultValue) {
        SharedPreferences sp = context.getSharedPreferences(fileName, Context.MODE_PRIVATE);
        return sp.getLong(key, defaultValue);
    }

    public static boolean getBoolean(Context context, String fileName, String key, boolean defaultValue) {
        SharedPreferences sp = context.getSharedPreferences(fileName, Context.MODE_PRIVATE);
        return sp.getBoolean(key, defaultValue);
    }

    public static String getString(Context context, String fileName, String key) {
        SharedPreferences sp = context.getSharedPreferences(fileName, Context.MODE_PRIVATE);
        return sp.getString(key, "");
    }

    public static Map<String, String> getString(Context context, String fileName, String... keys) {
        SharedPreferences sp = context.getSharedPreferences(fileName, Context.MODE_PRIVATE);
        Map<String, String> params = new HashMap<>();
        for (String key : keys) {
            String value = sp.getString(key, "");
            params.put(key, value);
        }
        return params;
    }
}
