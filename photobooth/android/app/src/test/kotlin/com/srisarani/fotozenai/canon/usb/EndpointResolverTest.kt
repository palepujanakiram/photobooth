package com.srisarani.fotozenai.canon.usb

import com.google.common.truth.Truth.assertThat
import org.junit.Assert.assertThrows
import org.junit.Test

class EndpointResolverTest {

    private fun ep(address: Int, direction: Int, type: Int, max: Int = 512) =
        EndpointDescriptor(address, direction, type, max)

    private fun stillImage(
        id: Int = 0,
        alt: Int = 0,
        endpoints: List<EndpointDescriptor>,
    ) = InterfaceDescriptor(id, alt, UsbClass.STILL_IMAGE, 1, 1, endpoints)

    /** The endpoint layout an EOS body actually presents. */
    private fun canonLayout() = listOf(
        ep(0x81, UsbDirection.IN, UsbTransferType.BULK, 512),
        ep(0x02, UsbDirection.OUT, UsbTransferType.BULK, 512),
        ep(0x83, UsbDirection.IN, UsbTransferType.INTERRUPT, 8),
    )

    @Test
    fun `resolves the canon endpoint triple`() {
        val (iface, endpoints) = EndpointResolver.resolve(listOf(stillImage(endpoints = canonLayout())))

        assertThat(iface.interfaceClass).isEqualTo(UsbClass.STILL_IMAGE)
        assertThat(endpoints.bulkIn.address).isEqualTo(0x81)
        assertThat(endpoints.bulkOut.address).isEqualTo(0x02)
        assertThat(endpoints.interruptIn?.address).isEqualTo(0x83)
        assertThat(endpoints.bulkIn.maxPacketSize).isEqualTo(512)
    }

    @Test
    fun `skips non still-image interfaces`() {
        // A mass-storage interface listed first is common; picking by index would grab it.
        val massStorage = InterfaceDescriptor(
            id = 0, alternateSetting = 0,
            interfaceClass = 8, interfaceSubclass = 6, interfaceProtocol = 80,
            endpoints = listOf(
                ep(0x81, UsbDirection.IN, UsbTransferType.BULK),
                ep(0x02, UsbDirection.OUT, UsbTransferType.BULK),
            ),
        )
        val ptp = stillImage(id = 1, endpoints = canonLayout())

        val (iface, _) = EndpointResolver.resolve(listOf(massStorage, ptp))

        assertThat(iface.id).isEqualTo(1)
    }

    @Test
    fun `prefers alternate setting zero`() {
        val alt1 = stillImage(id = 0, alt = 1, endpoints = canonLayout())
        val alt0 = stillImage(id = 0, alt = 0, endpoints = canonLayout())

        val iface = EndpointResolver.findStillImageInterface(listOf(alt1, alt0))

        assertThat(iface.alternateSetting).isEqualTo(0)
    }

    @Test
    fun `fails clearly when no still-image interface exists`() {
        val hid = InterfaceDescriptor(0, 0, 3, 0, 0, emptyList())

        val error = assertThrows(UsbError.NoStillImageInterface::class.java) {
            EndpointResolver.resolve(listOf(hid))
        }
        // The message must name what WAS found - "not found" alone is useless in the field.
        assertThat(error.message).contains("class=3")
    }

    @Test
    fun `fails when bulk out is missing`() {
        val iface = stillImage(
            endpoints = listOf(
                ep(0x81, UsbDirection.IN, UsbTransferType.BULK),
                ep(0x83, UsbDirection.IN, UsbTransferType.INTERRUPT),
            ),
        )

        val error = assertThrows(UsbError.MissingEndpoints::class.java) {
            EndpointResolver.resolveEndpoints(iface)
        }
        assertThat(error.message).contains("missing bulk OUT")
    }

    @Test
    fun `fails when both bulk endpoints are missing`() {
        val iface = stillImage(endpoints = listOf(ep(0x83, UsbDirection.IN, UsbTransferType.INTERRUPT)))

        val error = assertThrows(UsbError.MissingEndpoints::class.java) {
            EndpointResolver.resolveEndpoints(iface)
        }
        assertThat(error.message).contains("missing bulk OUT and bulk IN")
    }

    /**
     * maxPacketSize drives every short-packet and ZLP decision (P-01). A zero would break
     * every data phase in a way that looks like a parser bug, so refuse up front.
     */
    @Test
    fun `rejects a bulk in endpoint reporting zero max packet size`() {
        val iface = stillImage(
            endpoints = listOf(
                ep(0x81, UsbDirection.IN, UsbTransferType.BULK, max = 0),
                ep(0x02, UsbDirection.OUT, UsbTransferType.BULK),
            ),
        )

        val error = assertThrows(UsbError.MissingEndpoints::class.java) {
            EndpointResolver.resolveEndpoints(iface)
        }
        assertThat(error.message).contains("maxPacketSize=0")
    }

    /**
     * A missing interrupt endpoint is not fatal at this layer - M3's event loop needs it,
     * M1 and M2 do not. Failing here would block bring-up on an otherwise usable body.
     */
    @Test
    fun `tolerates a missing interrupt endpoint`() {
        val iface = stillImage(
            endpoints = listOf(
                ep(0x81, UsbDirection.IN, UsbTransferType.BULK),
                ep(0x02, UsbDirection.OUT, UsbTransferType.BULK),
            ),
        )

        val endpoints = EndpointResolver.resolveEndpoints(iface)

        assertThat(endpoints.interruptIn).isNull()
        assertThat(endpoints.bulkIn).isNotNull()
    }

    @Test
    fun `picks the first bulk endpoint when a body exposes duplicates`() {
        val iface = stillImage(
            endpoints = listOf(
                ep(0x81, UsbDirection.IN, UsbTransferType.BULK, 512),
                ep(0x84, UsbDirection.IN, UsbTransferType.BULK, 512),
                ep(0x02, UsbDirection.OUT, UsbTransferType.BULK, 512),
            ),
        )

        assertThat(EndpointResolver.resolveEndpoints(iface).bulkIn.address).isEqualTo(0x81)
    }

    @Test
    fun `endpoints summary is loggable`() {
        val endpoints = EndpointResolver.resolveEndpoints(stillImage(endpoints = canonLayout()))

        assertThat(endpoints.toString()).contains("bulkOut=0x02")
        assertThat(endpoints.toString()).contains("bulkIn=0x81")
        assertThat(endpoints.toString()).contains("interruptIn=0x83")
    }
}
