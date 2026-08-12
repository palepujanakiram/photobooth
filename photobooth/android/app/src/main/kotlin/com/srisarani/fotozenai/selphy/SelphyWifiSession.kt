package com.srisarani.fotozenai.selphy

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.util.Log
import com.srisarani.fotozenai.dnp.DnpWifiNetworkBinder
import io.flutter.plugin.common.MethodChannel
import jp.co.canon.android.print.selphy.wifisdk.CanonDiscoveryCallback
import java.util.concurrent.atomic.AtomicBoolean
import jp.co.canon.android.print.selphy.wifisdk.CanonPrintDevice as WifiPrintDevice
import jp.co.canon.android.print.selphy.wifisdk.CanonPrintJob as WifiPrintJob

/** Wi‑Fi discovery and print for Canon Selphy. */
internal class SelphyWifiSession(
    private val appContext: Context,
    private val sdkContext: () -> Context,
    private val mainHandler: Handler,
    private val wifiNetworkBinder: DnpWifiNetworkBinder,
) {
    private val logTag = "SelphyWifi"
    var cachedDevice: WifiPrintDevice? = null
        private set

    fun clear() {
        cachedDevice = null
    }

    fun releaseBinding() {
        try {
            WifiPrintDevice.stopDiscovery()
        } catch (e: Exception) {
            Log.d(logTag, "stopDiscovery: ${e.message}")
        }
        wifiNetworkBinder.release()
    }

    fun discover(result: MethodChannel.Result) {
        wifiNetworkBinder.bind { bound ->
            if (!bound) {
                result.error(
                    "WIFI_BIND_FAILED",
                    "Could not route to the Selphy Wi-Fi network",
                    null,
                )
                return@bind
            }
            startDiscovery(result)
        }
    }

    fun startPrint(request: SelphyPrintRequest) {
        val device = cachedDevice
        if (device == null) {
            mainHandler.post {
                request.result.error("NO_PRINTER", "Selphy Wi-Fi printer not ready", null)
            }
            return
        }

        val resizedFile =
            SelphyPrintSupport.preparePrintFile(appContext, request, mainHandler) ?: return

        val job = WifiPrintJob()
        job.setPrintConfiguration(WifiPrintJob.Configuration.Copies, request.copies)
        job.setPrintFile(Uri.fromFile(resizedFile), sdkContext())

        val state =
            SelphyJobFinishState(
                mainHandler = mainHandler,
                result = request.result,
                resolved = AtomicBoolean(false),
                resizedFile = resizedFile,
            )
        val started = device.print(job, sdkContext(), SelphyPrintCallbacks.wifi(state, logTag))

        if (!started) {
            SelphyPrintSupport.failStart(state, "Failed to start Selphy Wi-Fi print")
        }
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        val resolved = AtomicBoolean(false)
        val started =
            WifiPrintDevice.startDiscovery(
                sdkContext(),
                object : CanonDiscoveryCallback() {
                    override fun onFoundPrinter(device: WifiPrintDevice) {
                        if (resolved.compareAndSet(false, true)) {
                            cachedDevice = device
                            try {
                                WifiPrintDevice.stopDiscovery()
                            } catch (e: Exception) {
                                Log.d(logTag, "stopDiscovery after found: ${e.message}")
                            }
                            mainHandler.post {
                                result.success(
                                    "Printer ready: ${device.printerName} (${device.printerIpAddress})",
                                )
                            }
                        }
                    }

                    override fun onFinished(found: Boolean) {
                        if (resolved.compareAndSet(false, true)) {
                            mainHandler.post {
                                result.error(
                                    "NO_PRINTER",
                                    "No Canon Selphy printer found on Wi-Fi",
                                    null,
                                )
                            }
                        }
                    }
                },
            )

        if (!started && resolved.compareAndSet(false, true)) {
            mainHandler.post {
                result.error(
                    "DISCOVERY_FAILED",
                    "Could not start Selphy Wi-Fi discovery",
                    null,
                )
            }
        }
    }
}
