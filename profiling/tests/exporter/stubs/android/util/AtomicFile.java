package android.util;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicInteger;
public class AtomicFile {
    public static final AtomicInteger writes = new AtomicInteger();
    private final File file;
    public AtomicFile(File file) { this.file = file; }
    public FileOutputStream startWrite() throws IOException { return new FileOutputStream(file); }
    public void finishWrite(FileOutputStream stream) throws IOException { stream.close(); writes.incrementAndGet(); }
    public void failWrite(FileOutputStream stream) { try { stream.close(); } catch (IOException ignored) {} }
}
