package com.example.quarkus_cloud_run;

import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.lang.management.ManagementFactory;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

@Path("/metrics")
@Produces(MediaType.APPLICATION_JSON)
@ApplicationScoped
public class MetricsResource {

    @ConfigProperty(name = "quarkus.profile")
    Optional<String> profile;

    private long applicationStartupMillis;

    void onStart(@Observes StartupEvent ev) {
        this.applicationStartupMillis = System.currentTimeMillis() - ManagementFactory.getRuntimeMXBean().getStartTime();
    }

    @GET
    public Map<String, Object> getMetrics() {
        Map<String, Object> metrics = new LinkedHashMap<>();

        metrics.put("application", "quarkus-cloud-run");
        metrics.put("profile", profile.orElse("default"));

        boolean isNative = System.getProperty("org.graalvm.nativeimage.imagecode") != null;
        String imageType = isNative ? "Native (GraalVM)" : "JVM";
        metrics.put("imageType", imageType);
        metrics.put("isNative", isNative);

        metrics.put("startupTimeMs", applicationStartupMillis);
        metrics.put("startupTimeSeconds", String.format("%.3f", applicationStartupMillis / 1000.0));

        long uptimeMillis = ManagementFactory.getRuntimeMXBean().getUptime();
        metrics.put("uptimeMs", uptimeMillis);
        metrics.put("uptimeSeconds", String.format("%.3f", uptimeMillis / 1000.0));

        metrics.put("memory", getMemoryMetrics());

        Map<String, Object> jvm = new LinkedHashMap<>();
        jvm.put("version", System.getProperty("java.version"));
        jvm.put("vendor", System.getProperty("java.vendor"));
        jvm.put("name", System.getProperty("java.vm.name"));
        metrics.put("jvm", jvm);

        metrics.put("timestamp", Instant.now().toString());

        return metrics;
    }

    @GET
    @Path("/startup")
    public Map<String, Object> getStartupMetrics() {
        Map<String, Object> startup = new LinkedHashMap<>();

        boolean isNative = System.getProperty("org.graalvm.nativeimage.imagecode") != null;
        startup.put("imageType", isNative ? "Native (GraalVM)" : "JVM");
        startup.put("isNative", isNative);
        startup.put("startupTimeMs", applicationStartupMillis);
        startup.put("startupTimeSeconds", String.format("%.3f", applicationStartupMillis / 1000.0));
        startup.put("profile", profile.orElse("default"));

        return startup;
    }

    @GET
    @Path("/memory")
    public Map<String, Object> getMemoryMetrics() {
        Runtime runtime = Runtime.getRuntime();
        long totalMemory = runtime.totalMemory();
        long freeMemory = runtime.freeMemory();
        long usedMemory = totalMemory - freeMemory;
        long maxMemory = runtime.maxMemory();

        Map<String, Object> memory = new LinkedHashMap<>();
        memory.put("usedMB", String.format("%.2f", usedMemory / (1024.0 * 1024.0)));
        memory.put("totalMB", String.format("%.2f", totalMemory / (1024.0 * 1024.0)));
        memory.put("maxMB", String.format("%.2f", maxMemory / (1024.0 * 1024.0)));
        memory.put("freeMB", String.format("%.2f", freeMemory / (1024.0 * 1024.0)));
        memory.put("usagePercent", String.format("%.1f%%", (usedMemory * 100.0) / maxMemory));

        return memory;
    }
}
