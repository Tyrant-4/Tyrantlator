package com.winlator.star.network

/** SMB endpoint only: credentials are entered separately, never accepted in the URL. */
data class NetworkAddress(val host: String, val share: String, val directory: String) {
    val remote: String get() = "router:$share" + if (directory.isEmpty()) "" else "/$directory"
    val display: String get() = "smb://$host/$share" + if (directory.isEmpty()) "" else "/$directory"
    companion object {
        fun parse(raw: String): NetworkAddress {
            val path = raw.trim().replace('\\', '/').removePrefix("smb://").trimStart('/').trimEnd('/')
            val parts = path.split('/')
            require(parts.size >= 2) { "Enter an address with a share, for example smb://192.168.0.1/G/Games" }
            val host = parts.first()
            require(host.matches(Regex("[A-Za-z0-9][A-Za-z0-9.-]{0,252}"))) { "Use a hostname or IPv4 address, without a username or password." }
            require(parts.drop(1).all { p -> p.isNotBlank() && p != "." && p != ".." && p.none { it.isISOControl() || it in ":[]" } }) { "Invalid share or folder path." }
            return NetworkAddress(host, parts[1], parts.drop(2).joinToString("/"))
        }
        fun shellQuote(value: String): String = "'" + value.replace("'", "'\"'\"'") + "'"
        fun desktopExec(relativePath: String): String {
            require(!relativePath.contains('\n') && !relativePath.contains('\r'))
            // Shortcut.unescape makes two passes before collapsing doubled backslashes.
            return "wine " + ("N:\\" + relativePath.replace('/', '\\'))
                .replace("\\", "\\\\\\\\").replace(" ", "\\ ")
        }
    }
}
