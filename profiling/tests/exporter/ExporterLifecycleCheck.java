import android.content.Context;
import android.os.SystemClock;
import android.util.AtomicFile;
import com.winlator.star.perf.ProfileExporter;
import com.winlator.star.widget.FpsCounter;
import org.json.JSONObject;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** Runs the real exporter/counter with file and clock shims; not Android device/renderer QA. */
public class ExporterLifecycleCheck {
    private static Path output;
    private static JSONObject await(String status, String differentSession) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(4);
        do {
            try {
                JSONObject data = new JSONObject(Files.readString(output));
                if (status.equals(data.getString("status"))
                        && !data.getString("session").equals(differentSession)) return data;
            } catch (Exception ignored) {}
            Thread.sleep(10);
        } while (System.nanoTime() < deadline);
        throw new AssertionError("Export did not reach " + status);
    }
    private static void assertStoppedWrites() throws Exception {
        int count = AtomicFile.writes.get();
        Thread.sleep(1250);
        if (AtomicFile.writes.get() != count) throw new AssertionError("Writes continued while disabled");
    }
    public static void main(String[] args) throws Exception {
        Path directory = Files.createTempDirectory("tyrantlator-exporter-");
        output = directory.resolve("tyrantlator-profile.json");
        FpsCounter counter = new FpsCounter();
        for (int i = 0; i < 200; i++) { SystemClock.now += 16; counter.tick(); }
        AtomicBoolean bound = new AtomicBoolean(true);
        ProfileExporter exporter = new ProfileExporter(new Context(directory.toFile()), counter,
                "Control", 3, "opengl", bound::get);
        try {
            JSONObject active = await("active", "");
            if (active.getJSONArray("intervals_ms").length() != 120 || active.getDouble("fps") <= 0)
                throw new AssertionError("Frame data missing");
            if (active.getInt("schema") != 1 || !"test.tyrantlator".equals(active.getString("package")))
                throw new AssertionError("Export identity changed");
            String firstSession = active.getString("session");
            exporter.setEnabled(false);
            await("stopped", "");
            assertStoppedWrites();
            exporter.setEnabled(false); // Idempotent stop does not schedule another write.
            assertStoppedWrites();
            exporter.setEnabled(true);
            JSONObject resumed = await("active", firstSession);
            String resumedSession = resumed.getString("session");
            exporter.setEnabled(true); // Idempotent start preserves the session.
            Thread.sleep(1100);
            if (!resumedSession.equals(await("active", "").getString("session")))
                throw new AssertionError("Idempotent start reset the session");
            bound.set(false);
            await("idle", "");
            bound.set(true);
            await("active", "");
            for (int i = 0; i < 20; i++) { exporter.setEnabled(false); exporter.setEnabled(true); }
            await("active", resumedSession);
            Thread.sleep(1100);
            await("active", resumedSession); // A late stopped marker must not overwrite the new session.
            exporter.close();
            await("stopped", "");
            assertStoppedWrites();
            exporter.setEnabled(true);
            exporter.close();
            assertStoppedWrites();
            java.lang.reflect.Field workerField = ProfileExporter.class.getDeclaredField("worker");
            workerField.setAccessible(true);
            if (!((ScheduledExecutorService)workerField.get(exporter)).awaitTermination(2, TimeUnit.SECONDS))
                throw new AssertionError("Worker survives activity teardown");
            System.out.println("PASS: live stop/resume, no disabled writes, fresh sessions, rapid toggles, idle source, teardown");
        } finally {
            exporter.close();
            Files.deleteIfExists(output);
            Files.deleteIfExists(directory);
        }
    }
}
