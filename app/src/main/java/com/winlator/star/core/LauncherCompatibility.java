package com.winlator.star.core;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.Collection;
import java.util.Arrays;

/** Launcher repairs shared by fresh prefixes and existing containers. */
public final class LauncherCompatibility {
    public static final String DISPLAY_DRIVER = "Mesa Turnip v26.3.0-20261003-r4-A8xx";
    private static final String WN_DRIVER = "WN-Turnip-1.19-p Axxx";
    private static final String METRICS = "Control Panel\\Desktop\\WindowMetrics";
    private static final String VERSION_KEY = "Software\\Tyrantlator\\LauncherCompatibility";
    private static final String[] FONTS = {"CaptionFont", "IconFont", "MenuFont", "MessageFont", "SmCaptionFont", "StatusFont"};
    private static final String[] EA_APPS = {"EADesktop.exe", "EACefSubProcess.exe", "EALaunchHelper.exe", "EASteamProxy.exe"};

    private LauncherCompatibility() {}

    public static String defaultCompositor(Collection<String> installed) {
        return installed.contains(DISPLAY_DRIVER) ? DISPLAY_DRIVER : "system";
    }

    public static String resolveCompositor(String selected, Collection<String> installed) {
        return WN_DRIVER.equals(selected) ? defaultCompositor(installed) : selected;
    }

    public static void seedMissingFonts(WineRegistryEditor registry) {
        for (String font : FONTS) {
            if (!registry.hasValue(METRICS, font)) writeFont(registry, font);
        }
    }

    public static void apply(File userRegistry, boolean freshPrefix) {
        try (WineRegistryEditor registry = new WineRegistryEditor(userRegistry)) {
            if (freshPrefix || registry.getDwordValue(VERSION_KEY, "Version", 0) < 1) {
                for (String font : FONTS) {
                    if (freshPrefix || !registry.hasValue(METRICS, font)) {
                        writeFont(registry, font);
                    } else {
                        byte[] existing = decodeFont(registry.getRawValue(METRICS, font));
                        if (existing != null && isTahoma(existing)) {
                            // Keep the user's height, weight and other LOGFONT attributes.
                            Arrays.fill(existing, 28, 92, (byte) 0);
                            byte[] face = "Segoe UI".getBytes(StandardCharsets.UTF_16LE);
                            System.arraycopy(face, 0, existing, 28, face.length);
                            registry.setHexValue(METRICS, font, existing);
                        }
                    }
                }
                registry.setDwordValue(VERSION_KEY, "Version", 1);
            }
            seedMissingFonts(registry);
            for (String app : EA_APPS) {
                String key = "Software\\Wine\\AppDefaults\\" + app + "\\DllOverrides";
                if (!"builtin".equals(registry.getStringValue(key, "ucrtbase"))) {
                    registry.setStringValue(key, "ucrtbase", "builtin");
                }
            }
        }
    }

    private static void writeFont(WineRegistryEditor registry, String font) {
        MSLogFont data = new MSLogFont().setFaceName("Segoe UI");
        if ("CaptionFont".equals(font)) data.setWeight(700);
        registry.setHexValue(METRICS, font, data.toByteArray());
    }

    private static byte[] decodeFont(String raw) {
        if (raw == null || !raw.startsWith("hex:")) return null;
        String[] hex = raw.substring(4).replace("\\", "").replaceAll("\\s", "").split(",");
        if (hex.length != 92) return null;
        byte[] bytes = new byte[92];
        try {
            for (int i = 0; i < hex.length; i++) bytes[i] = (byte) Integer.parseInt(hex[i], 16);
        } catch (NumberFormatException e) {
            return null;
        }
        return bytes;
    }

    private static boolean isTahoma(byte[] bytes) {
        String face = new String(bytes, 28, 64, StandardCharsets.UTF_16LE);
        int end = face.indexOf('\0');
        return "Tahoma".equalsIgnoreCase(end >= 0 ? face.substring(0, end) : face);
    }
}
