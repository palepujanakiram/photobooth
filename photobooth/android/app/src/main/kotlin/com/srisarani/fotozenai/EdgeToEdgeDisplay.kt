package com.srisarani.fotozenai

import android.graphics.Color
import android.view.View
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * Android 15 (target SDK 35+) draws edge-to-edge by default. Play Console also
 * wants [enableEdgeToEdge] so API 30–34 match that layout, instead of only
 * 35+ getting transparent system bars.
 *
 * [io.flutter.embedding.android.FlutterActivity] is not a [ComponentActivity],
 * so [MainActivity] hosts Flutter as a [io.flutter.embedding.android.FlutterFragmentActivity].
 * Do not pad the Flutter view — Dart already maps these insets to MediaQuery.
 */
object EdgeToEdgeDisplay {
    fun enable(activity: ComponentActivity) {
        activity.enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
    }

    fun bindSystemBarPadding(
        root: View,
        includeBottom: Boolean = true,
    ) {
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            applySystemBarPadding(view, insets, includeBottom)
        }
        ViewCompat.requestApplyInsets(root)
    }

    fun applySystemBarPadding(
        view: View,
        insets: WindowInsetsCompat,
        includeBottom: Boolean = true,
    ): WindowInsetsCompat {
        applySystemBarPadding(
            view,
            insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.displayCutout(),
            ),
            includeBottom,
        )
        return WindowInsetsCompat.CONSUMED
    }

    fun applySystemBarPadding(
        view: View,
        bars: Insets,
        includeBottom: Boolean = true,
    ) {
        view.setPadding(
            bars.left,
            bars.top,
            bars.right,
            if (includeBottom) bars.bottom else 0,
        )
    }
}
