package com.winlator.star.network

import android.content.Context
import android.system.Os
import com.winlator.star.container.Container
import com.winlator.star.perf.RootManager
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/** One read-only network drive, with root-private credentials and local Wine saves. */
class NetworkDriveManager(private val context: Context) {
    companion object { private val connectionLock = Any() }
    private val prefs = context.getSharedPreferences("network_drive", Context.MODE_PRIVATE)
    val savedAddress get() = prefs.getString("address", "smb://192.168.0.1/G/Games")!!
    val savedUsername get() = prefs.getString("username", "admin")!!
    val mountpoint = File(context.filesDir, "network-games")
    private val net = "/data/adb/tyrantlator-network"
    private fun q(value: String) = NetworkAddress.shellQuote(value)
    private fun root(script: String): String = RootManager.runNetworkScript(script)
    fun connected(): Boolean = File("/proc/self/mounts").useLines { lines ->
        lines.any { it.contains(" ${mountpoint.canonicalPath} fuse.rclone ") || it.contains(" ${mountpoint.absolutePath} fuse.rclone ") }
    }

    fun connect(address: String, username: String, password: String): String = synchronized(connectionLock) {
        val endpoint = NetworkAddress.parse(address)
        require(!password.contains('\u0000')) { "Password contains an unsupported character." }
        require(username.none { it.isISOControl() }) { "Username cannot contain control characters." }
        require(context.packageName == "com.tencent.ig") { "This connector requires the PUBG variant." }
        check(RootManager.ensureGrantedBlocking()) { "Root access is required. Allow Tyrantlator in the superuser prompt." }
        if (connected()) {
            check(endpoint.display == savedAddress && username == savedUsername && password.isEmpty()) {
                "Disconnect the current drive before changing its login or address."
            }
            return@synchronized "Connected · N:"
        }
        val stage = File(context.filesDir, "network-connect-stage").apply { mkdirs(); Os.chmod(absolutePath, 448) }
        try {
            bootstrap(stage)
            val endpointFile = File(stage, "endpoint").apply {
                createNewFile(); Os.chmod(absolutePath, 384)
                writeText("[router]\ntype = smb\nhost = ${endpoint.host}\nuser = $username\n")
            }
            val reuse = password.isEmpty() && endpoint.display == savedAddress && username == savedUsername
            val config = if (reuse) {
                "test -s ${q("$net/rclone.conf")} || exit 22\ncp ${q("$net/rclone.conf")} ${q("$net/candidate.conf")}"
            } else {
                "cp ${q(endpointFile.absolutePath)} ${q("$net/candidate.conf")}\n" +
                "printf 'pass = ' >> ${q("$net/candidate.conf")}\n" +
                "printf %s ${q(password)} | ${q("$net/bin/rclone")} obscure - >> ${q("$net/candidate.conf")}"
            }
            val result = root("""
                set -eu
                umask 077
                $config
                chmod 600 ${q("$net/candidate.conf")}
                ${q("$net/bin/rclone")} lsf ${q(endpoint.remote)} --config ${q("$net/candidate.conf")} --max-depth 1 --contimeout 8s --timeout 15s > /dev/null 2>&1 || exit 23
                mv ${q("$net/candidate.conf")} ${q("$net/rclone.conf")}
            """.trimIndent())
            check(result == "OK") { if (result == "22") "Enter the password for your first connection." else "Could not sign in or read that share. Check the address, login and Wi-Fi." }
            val script = File(stage, "mount.sh").apply { writeText(mountScript(endpoint)); Os.chmod(absolutePath, 384) }
            check(root("set -eu\ncp ${q(script.absolutePath)} ${q("$net/mount.sh")}\nchmod 700 ${q("$net/mount.sh")}\n${q("$net/mount.sh")} > /dev/null 2>&1") == "OK") {
                "Login succeeded, but Android could not mount the drive. Check root and FUSE support."
            }
            check(connected()) { "Mount is not visible to Tyrantlator. Reopen the app and connect again." }
            prefs.edit().putString("address", endpoint.display).putString("username", username).apply()
            return@synchronized "Connected · N:"
        } finally {
            stage.listFiles()?.filter { it.name in setOf("password", "endpoint", "mount.sh", "rclone", "fusermount3") }?.forEach { it.delete() }
            root("rm -f ${q("$net/candidate.conf")}")
        }
    }

    private fun bootstrap(stage: File) {
        if (root("test -x ${q("$net/bin/rclone")} && test -x ${q("$net/bin/fusermount3")}") == "OK") return
        val binary = File(stage, "rclone")
        ZipInputStream(context.assets.open("network/rclone.zip")).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.name.endsWith("/rclone")) { binary.outputStream().use { zip.copyTo(it) }; break }
            }
        }
        check(binary.isFile && hash(binary) == "5aa85195f836e62f76e9dbb94dada612bd08be892f8f4196ec54ed7fee01a3c0") { "Network connector verification failed." }
        val helper = File(stage, "fusermount3")
        context.assets.open("network/fusermount3").use { input -> helper.outputStream().use { input.copyTo(it) } }
        check(hash(helper) == "40e12ddb8934f587dd6eb6c49548ab569c12e9f54435143a29b5c1edc8407c79") { "Mount helper verification failed." }
        check(root("""
            set -eu
            mkdir -p ${q("$net/bin")}
            chmod 700 ${q(net)} ${q("$net/bin")}
            cp ${q(binary.absolutePath)} ${q("$net/bin/rclone")}
            cp ${q(helper.absolutePath)} ${q("$net/bin/fusermount3")}
            chmod 700 ${q("$net/bin/rclone")} ${q("$net/bin/fusermount3")}
            ln -sf fusermount3 ${q("$net/bin/fusermount")}
        """.trimIndent()) == "OK") { "Could not install the root network connector." }
    }
    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream -> val buffer = ByteArray(65536); while (true) { val n = stream.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) } }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    private fun mountScript(endpoint: NetworkAddress) = """
        #!/system/bin/sh
        set -eu
        MP=${q(mountpoint.canonicalPath)}
        NET=${q(net)}
        if grep -q " ${'$'}MP fuse.rclone " /proc/mounts; then exit 0; fi
        mkdir -p "${'$'}MP"
        chown ${context.applicationInfo.uid}:${context.applicationInfo.uid} "${'$'}MP"
        chmod 770 "${'$'}MP"
        LABEL=${'$'}(ls -Zd ${q(context.filesDir.canonicalPath)} | awk '{print ${'$'}1}')
        case "${'$'}LABEL" in u:object_r:app_data_file:*) chcon "${'$'}LABEL" "${'$'}MP" ;; *) exit 24 ;; esac
        export PATH="${'$'}NET/bin:/system/bin:${'$'}PATH"
        "${'$'}NET/bin/rclone" mount ${q(endpoint.remote)} "${'$'}MP" --config "${'$'}NET/rclone.conf" \
         --read-only --allow-other --uid ${context.applicationInfo.uid} --gid ${context.applicationInfo.uid} --dir-perms 0770 --file-perms 0640 \
         --vfs-cache-mode full --vfs-cache-max-size 2G --vfs-cache-max-age 1h --buffer-size 16M --vfs-read-ahead 32M \
         --cache-dir "${'$'}NET/cache/${endpoint.display.toByteArray().let { MessageDigest.getInstance("SHA-256").digest(it) }.joinToString("") { "%02x".format(it) }.take(16)}" --dir-cache-time 30s --poll-interval 0 --contimeout 8s --timeout 30s \
         --daemon --daemon-wait 10s --log-file "${'$'}NET/mount.log" --log-level ERROR \
         </dev/null >"${'$'}NET/daemon-start.log" 2>&1
    """.trimIndent() + "\n"

    fun disconnect(): String = synchronized(connectionLock) {
        check(RootManager.ensureGrantedBlocking()) { "Root access is required." }
        val result = root("""
            set -eu
            if ps -A -o UID,NAME | grep -E '^ *${context.applicationInfo.uid} +.*(wineserver|wine64|wine|\.exe|proot|gamescope|steam)' > /dev/null; then exit 25; fi
            if grep -q ' ${mountpoint.canonicalPath} fuse.rclone ' /proc/mounts; then
                ${q("$net/bin/fusermount3")} -u ${q(mountpoint.canonicalPath)} > /dev/null 2>&1
            fi
        """.trimIndent())
        check(result == "OK") { if (result == "25") "Close the running container before disconnecting." else "The drive is busy. Close its games and file browsers, then retry." }
        return@synchronized "Disconnected"
    }
    fun addShortcut(container: Container, file: File): String {
        check(connected()) { "Connect the drive first." }
        val root = mountpoint.canonicalFile
        val target = file.canonicalFile
        require(target.path.startsWith(root.path + "/") && target.extension.equals("exe", true)) { "Select a game executable on the network drive." }
        val mappings = container.drivesIterator().asSequence().map { it[0] to it[1] }.toList()
        val existing = mappings.find { it.first.equals("N", true) }
        check(existing == null || File(existing.second).canonicalPath == root.path) { "N: is already assigned in this container. Choose a different container." }
        if (existing == null) { container.drives = container.drives + "N:" + root.path; container.saveData() }
        val name = target.nameWithoutExtension.replace(Regex("[^A-Za-z0-9 _.-]"), "_") + " - Network"
        val folder = File(container.rootDir, ".local/share/applications").apply { mkdirs() }
        val shortcut = File(folder, "$name.desktop")
        check(!shortcut.exists()) { "That network shortcut already exists in this container." }
        shortcut.writeText("[Desktop Entry]\nType=Application\nName=$name\nExec=${NetworkAddress.desktopExec(target.relativeTo(root).path)}\n[Extra Data]\ncontainer_id=${container.id}\n")
        return "Added $name to Games · ${container.name}"
    }
}
