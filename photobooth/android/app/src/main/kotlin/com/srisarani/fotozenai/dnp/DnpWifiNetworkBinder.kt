package com.srisarani.fotozenai.dnp

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import java.util.concurrent.atomic.AtomicBoolean

/** Binds the process to Wi-Fi so DNP LAN printing uses the kiosk subnet. */
internal class DnpWifiNetworkBinder(
    private val appContext: Context,
    private val mainHandler: Handler,
) {
    private var connectivityManager: ConnectivityManager? = null
    private var wifiNetworkCallback: ConnectivityManager.NetworkCallback? = null

    fun bind(onResult: (Boolean) -> Unit) {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        connectivityManager = cm

        val bound = cm.boundNetworkForProcess
        if (bound != null) {
            val caps = cm.getNetworkCapabilities(bound)
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                onResult(true)
                return
            }
        }

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()

        val resolved = AtomicBoolean(false)
        val timeout = Runnable {
            if (resolved.compareAndSet(false, true)) onResult(false)
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val ok = cm.bindProcessToNetwork(network)
                if (resolved.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeout)
                    mainHandler.post { onResult(ok) }
                }
            }

            override fun onUnavailable() {
                if (resolved.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeout)
                    mainHandler.post { onResult(false) }
                }
            }
        }
        wifiNetworkCallback = callback
        cm.requestNetwork(request, callback)
        mainHandler.postDelayed(timeout, 8000)
    }

    fun release() {
        try {
            connectivityManager?.bindProcessToNetwork(null)
            wifiNetworkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        } catch (_: Exception) {
        }
        wifiNetworkCallback = null
        connectivityManager = null
    }
}
