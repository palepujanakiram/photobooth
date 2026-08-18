package com.srisarani.fotozenai.canon.usb

/**
 * Picks the PTP interface and its three endpoints out of a device's descriptors.
 *
 * Pure function, no Android types, fully unit tested. Endpoint selection is one of those
 * things that looks trivial and then fails on one specific body because it exposes two
 * bulk IN endpoints, or lists them in an unexpected order, or has a mass-storage interface
 * sitting in front of the still-image one.
 */
object EndpointResolver {

    /**
     * @return the first still-image interface, preferring alternate setting 0.
     * @throws UsbError.NoStillImageInterface when the device exposes none.
     */
    fun findStillImageInterface(interfaces: List<InterfaceDescriptor>): InterfaceDescriptor {
        val candidates = interfaces.filter { it.isStillImage }
        if (candidates.isEmpty()) throw UsbError.NoStillImageInterface(interfaces)

        // Alternate setting 0 is the default. A non-zero alt setting generally needs an
        // explicit SET_INTERFACE, which the Android USB API does not expose cleanly.
        return candidates.firstOrNull { it.alternateSetting == 0 } ?: candidates.first()
    }

    /**
     * Resolves bulk OUT, bulk IN and interrupt IN.
     *
     * Bulk OUT and bulk IN are mandatory - without both there is no PTP.
     *
     * Interrupt IN is optional *at this layer*: a body that does not expose one simply
     * cannot deliver asynchronous events, which M3 needs. We resolve it if present, log
     * loudly if absent, and let M3 decide whether that is fatal. Failing here would block
     * bring-up on a body that is otherwise perfectly usable for M1/M2.
     */
    fun resolveEndpoints(iface: InterfaceDescriptor): ResolvedEndpoints {
        val endpoints = iface.endpoints

        val bulkOut = endpoints.firstOrNull { it.isBulk && it.isOut }
        val bulkIn = endpoints.firstOrNull { it.isBulk && it.isIn }
        val interruptIn = endpoints.firstOrNull { it.isInterrupt && it.isIn }

        if (bulkOut == null || bulkIn == null) {
            val missing = buildList {
                if (bulkOut == null) add("bulk OUT")
                if (bulkIn == null) add("bulk IN")
            }.joinToString(" and ")
            throw UsbError.MissingEndpoints(endpoints, "missing $missing")
        }

        if (bulkIn.maxPacketSize <= 0) {
            // maxPacketSize drives the short-packet and ZLP logic (P-01). A zero here would
            // silently break every data phase, so refuse rather than limp on.
            throw UsbError.MissingEndpoints(endpoints, "bulk IN reports maxPacketSize=${bulkIn.maxPacketSize}")
        }

        return ResolvedEndpoints(bulkOut = bulkOut, bulkIn = bulkIn, interruptIn = interruptIn)
    }

    /** Convenience: interface + endpoints in one step. */
    fun resolve(interfaces: List<InterfaceDescriptor>): Pair<InterfaceDescriptor, ResolvedEndpoints> {
        val iface = findStillImageInterface(interfaces)
        return iface to resolveEndpoints(iface)
    }
}
