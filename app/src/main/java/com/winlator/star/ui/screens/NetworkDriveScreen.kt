package com.winlator.star.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.winlator.star.container.ContainerManager
import com.winlator.star.network.NetworkDriveManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun NetworkDriveScreen(onOpenGames: () -> Unit = {}) {
    val context = LocalContext.current
    val manager = remember { NetworkDriveManager(context.applicationContext) }
    val scope = rememberCoroutineScope()
    var address by rememberSaveable { mutableStateOf(manager.savedAddress) }
    var username by rememberSaveable { mutableStateOf(manager.savedUsername) }
    // Never save a password in Compose saved-state, preferences, logs or a URL.
    var password by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("Checking connection…") }
    var connected by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var folder by remember { mutableStateOf(manager.mountpoint) }
    var entries by remember { mutableStateOf<List<File>>(emptyList()) }
    var browsing by remember { mutableStateOf(false) }
    var containers by remember { mutableStateOf(emptyList<com.winlator.star.container.Container>()) }
    var selectedId by rememberSaveable { mutableStateOf(2) }
    var choosingContainer by remember { mutableStateOf(false) }
    val selected = containers.find { it.id == selectedId }

    fun action(block: () -> String) {
        busy = true
        scope.launch {
            status = withContext(Dispatchers.IO) { runCatching(block).getOrElse { it.message ?: "Operation failed. Check your connection." } }
            connected = withContext(Dispatchers.IO) { runCatching { manager.connected() }.getOrDefault(false) }
            busy = false
        }
    }
    fun browse(target: File) {
        busy = true
        scope.launch {
            val result = withContext(Dispatchers.IO) { runCatching {
                val root = manager.mountpoint.canonicalPath
                val path = target.canonicalPath
                check(path == root || path.startsWith(root + "/")) { "Folder is outside the network drive." }
                target.listFiles()?.filter { it.isDirectory || it.extension.equals("exe", true) }
                    ?.sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name.lowercase() })
                    ?: error("Could not read this folder. Reconnect the drive and check Wi-Fi.")
            } }
            result.onSuccess { folder = target; entries = it; browsing = true }
                .onFailure { status = it.message ?: "Could not browse the drive." }
            busy = false
        }
    }
    LaunchedEffect(Unit) {
        connected = withContext(Dispatchers.IO) { runCatching { manager.connected() }.getOrDefault(false) }
        containers = withContext(Dispatchers.IO) { ContainerManager(context).containers.toList() }
        if (containers.none { it.id == selectedId }) selectedId = containers.firstOrNull()?.id ?: -1
        status = if (connected) "Connected · N:" else "Disconnected"
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Network Drive", style = MaterialTheme.typography.headlineSmall)
        Text("Connect to an SMB drive over Wi-Fi. Games stay on the drive; accessed files are cached on your phone.")
        OutlinedTextField(address, { address = it }, label = { Text("Address") }, placeholder = { Text("smb://192.168.0.1/G/Games") }, singleLine = true, enabled = !busy && !connected, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(username, { username = it }, label = { Text("Username") }, singleLine = true, enabled = !busy && !connected, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text))
        OutlinedTextField(password, { password = it }, label = { Text("Password") }, supportingText = { Text("Leave blank to reconnect using the saved login.") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), enabled = !busy && !connected, modifier = Modifier.fillMaxWidth())
        Text("Root required. Login is saved privately on this phone. The network drive is read-only; game saves stay in your container.", style = MaterialTheme.typography.bodySmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(enabled = !busy && !connected, onClick = {
                val enteredPassword = password
                password = ""
                action { manager.connect(address, username, enteredPassword) }
            }) { Text("Connect") }
            OutlinedButton(enabled = !busy && connected, onClick = { action { manager.disconnect().also { browsing = false } } }) { Text("Disconnect") }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        Text(status, color = if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
        HorizontalDivider()
        Text("Choose a game", style = MaterialTheme.typography.titleMedium)
        OutlinedButton(enabled = !busy && connected, onClick = { browse(manager.mountpoint) }) { Text("Browse network games") }
        if (browsing) {
            Box {
                OutlinedButton(enabled = !busy, onClick = { choosingContainer = true }) { Text("Container: ${selected?.name ?: "Choose a container"}") }
                DropdownMenu(expanded = choosingContainer, onDismissRequest = { choosingContainer = false }) {
                    containers.forEach { container -> DropdownMenuItem(text = { Text(container.name) }, onClick = { selectedId = container.id; choosingContainer = false }) }
                }
            }
            Text("N:/" + folder.relativeTo(manager.mountpoint).path.replace('\\', '/'))
            if (folder != manager.mountpoint) TextButton(enabled = !busy, onClick = { browse(folder.parentFile!!) }) { Text("Up one folder") }
            if (entries.isEmpty()) Text("No folders or game executables here.")
            entries.forEach { file ->
                Surface(tonalElevation = 2.dp, modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        if (file.isDirectory) Text(file.name + " /", Modifier.weight(1f).clickable(enabled = !busy) { browse(file) })
                        else {
                            Text(file.name, Modifier.weight(1f))
                            TextButton(enabled = !busy && selected != null, onClick = { action { manager.addShortcut(selected!!, file) } }) { Text("Add to Games") }
                        }
                    }
                }
            }
            Text("Open the added shortcut from Games. This also maps N: in the chosen container.", style = MaterialTheme.typography.bodySmall)
            OutlinedButton(onClick = onOpenGames, enabled = !busy) { Text("Open Games") }
        }
    }
}
