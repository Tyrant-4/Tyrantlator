package com.winlator.star.perf;

import android.content.Context;
import android.util.AtomicFile;

import com.winlator.star.widget.FpsCounter;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

/** Opt-in, local telemetry from the existing HUD counter; never performs I/O on a present thread. */
public final class ProfileExporter implements AutoCloseable {
    private final FpsCounter counter;
    private final AtomicFile output;
    private final String packageName;
    private final String game;
    private final int containerId;
    private final String displayBackend;
    private final BooleanSupplier sourceEnabled;
    private final String session = UUID.randomUUID().toString();
    private final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor();
    private final ScheduledFuture<?> task;
    private boolean closed;

    public ProfileExporter(Context context, FpsCounter counter, String game, int containerId,
                           String displayBackend, BooleanSupplier sourceEnabled) {
        this.counter = counter;
        this.game = game;
        this.containerId = containerId;
        this.displayBackend = displayBackend;
        this.sourceEnabled = sourceEnabled;
        packageName = context.getPackageName();
        File directory = context.getExternalFilesDir(null);
        output = directory == null ? null : new AtomicFile(new File(directory, "tyrantlator-profile.json"));
        task = worker.scheduleWithFixedDelay(() -> write(false), 0, 1, TimeUnit.SECONDS);
    }

    private void write(boolean stopped) {
        if (output == null) return;
        FileOutputStream stream = null;
        try {
            FpsCounter.ProfileSnapshot frames = counter.getProfileSnapshot();
            boolean active = !stopped && sourceEnabled.getAsBoolean()
                    && frames.frameAgeMs >= 0 && frames.frameAgeMs <= 1500;
            JSONObject json = new JSONObject();
            json.put("schema", 1);
            json.put("session", session);
            json.put("package", packageName);
            json.put("game", game);
            json.put("container_id", containerId);
            json.put("display_backend", displayBackend);
            json.put("source", "app_hud_present_intervals");
            json.put("status", stopped ? "stopped" : active ? "active" : "idle");
            json.put("elapsed_ms", frames.elapsedMs);
            json.put("frame_age_ms", frames.frameAgeMs);
            json.put("fps", active ? frames.fps : JSONObject.NULL);
            JSONArray intervals = new JSONArray();
            if (active) for (float value : frames.intervalsMs) intervals.put(value);
            json.put("intervals_ms", intervals);
            stream = output.startWrite();
            stream.write(json.toString().getBytes(StandardCharsets.UTF_8));
            output.finishWrite(stream);
        } catch (Exception ignored) {
            // Unmounted storage or an export error must not interrupt the game. The PC marks it stale.
            if (stream != null) output.failWrite(stream);
        }
    }

    @Override public synchronized void close() {
        if (closed) return;
        closed = true;
        task.cancel(false);
        worker.execute(() -> write(true));
        worker.shutdown();
    }
}
