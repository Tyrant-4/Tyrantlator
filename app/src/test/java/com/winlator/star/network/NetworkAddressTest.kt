package com.winlator.star.network

import com.winlator.star.core.StringUtils
import org.junit.Assert.*
import org.junit.Test

class NetworkAddressTest {
    @Test fun smbAndWindowsAddressesSelectTheSameShare() {
        assertEquals(NetworkAddress.parse("smb://192.168.0.1/G/Games"), NetworkAddress.parse("\\\\192.168.0.1\\G\\Games"))
        assertEquals("router:G/Games", NetworkAddress.parse("192.168.0.1/G/Games/").remote)
    }
    @Test fun urlCannotContainLoginOrTraversal() {
        listOf("smb://admin:secret@192.168.0.1/G", "192.168.0.1", "192.168.0.1/G/../DCIM", "192.168.0.1/G\npass=x", "192.168.0.1/G//Games").forEach {
            assertThrows(IllegalArgumentException::class.java) { NetworkAddress.parse(it) }
        }
    }
    @Test fun desktopRoundTripPreservesGamePathWithSpaces() {
        val path = "Devil-May-Cry-4-SteamRIP.com(1)/Devil May Cry 4 Special Edition/DevilMayCry4SpecialEdition.exe"
        assertEquals("N:\\" + path.replace('/', '\\'), StringUtils.unescape(NetworkAddress.desktopExec(path).removePrefix("wine ")))
    }
    @Test fun quotingKeepsShellMetacharactersInsideOneArgument() {
        assertEquals("'Games/a'\"'\"'b;\$(touch x)'", NetworkAddress.shellQuote("Games/a'b;\$(touch x)"))
    }
}
