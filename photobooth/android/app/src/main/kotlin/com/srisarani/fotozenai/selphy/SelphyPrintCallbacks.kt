package com.srisarani.fotozenai.selphy

import android.os.Handler
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintCallback as UsbPrintCallback
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintJob as UsbPrintJob
import jp.co.canon.android.print.selphy.usbsdk.CanonPrinterStatus as UsbPrinterStatus
import jp.co.canon.android.print.selphy.wifisdk.CanonPrintCallback as WifiPrintCallback
import jp.co.canon.android.print.selphy.wifisdk.CanonPrintJob as WifiPrintJob
import jp.co.canon.android.print.selphy.wifisdk.CanonPrinterStatus as WifiPrinterStatus

/** Mutable state for a single in-flight Selphy print job. */
internal data class SelphyJobFinishState(
    val mainHandler: Handler,
    val result: MethodChannel.Result,
    val resolved: AtomicBoolean,
    val resizedFile: File,
)

/** USB/Wi‑Fi SDK callbacks that share the same finish path. */
internal object SelphyPrintCallbacks {
    fun usb(
        state: SelphyJobFinishState,
        logTag: String,
    ) = object : UsbPrintCallback() {
        override fun onChangedJobStatus(job: UsbPrintJob) = notifyJob(state, job.isFinished, job.status.toString())

        override fun onChangedPrinterStatus(
            job: UsbPrintJob,
            status: UsbPrinterStatus,
        ) = logStatus(logTag, status.toString())
    }

    fun wifi(
        state: SelphyJobFinishState,
        logTag: String,
    ) = object : WifiPrintCallback() {
        override fun onChangedJobStatus(job: WifiPrintJob) {
            // Wi‑Fi jobs can emit intermediate statuses; finish only when done.
            notifyJob(state, job.isFinished, job.status.toString())
        }

        override fun onChangedPrinterStatus(
            job: WifiPrintJob,
            status: WifiPrinterStatus,
        ) {
            logStatus(logTag, "wifi:$status")
        }
    }

    private fun notifyJob(
        state: SelphyJobFinishState,
        isFinished: Boolean,
        statusMessage: String,
    ) {
        if (!isFinished) return
        SelphyPrintSupport.finishJob(state, statusMessage)
    }

    private fun logStatus(
        logTag: String,
        status: String,
    ) {
        Log.d(logTag, "printer status: $status")
    }
}
