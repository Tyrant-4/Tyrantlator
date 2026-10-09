package android.content;
import java.io.File;
public class Context {
    private final File directory;
    public Context(File directory) { this.directory = directory; }
    public String getPackageName() { return "test.tyrantlator"; }
    public File getExternalFilesDir(String type) { return directory; }
}
