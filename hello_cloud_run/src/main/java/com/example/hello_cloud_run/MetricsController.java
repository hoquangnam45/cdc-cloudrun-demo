package com.example.hello_cloud_run;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.lang.management.ManagementFactory;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
public class MetricsController {

    private final Environment environment;
    private Instant startupTime;
    private long applicationStartupMillis;

    public MetricsController(Environment environment) {
        this.environment = environment;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady(ApplicationReadyEvent event) {
        this.startupTime = Instant.now();
        this.applicationStartupMillis = System.currentTimeMillis() -
            ManagementFactory.getRuntimeMXBean().getStartTime();
    }

    @GetMapping("/metrics")
    public Map<String, Object> getMetrics() {
        Map<String, Object> metrics = new LinkedHashMap<>();

        // Basic info
        metrics.put("application", "hello-cloud-run");
        metrics.put("profile", environment.getActiveProfiles().length > 0
            ? environment.getActiveProfiles()[0] : "default");

        // Image type detection
        String imageType = isNativeImage() ? "Native (GraalVM)" : "JVM";
        metrics.put("imageType", imageType);

        // Connection pool type
        String poolType = environment.getProperty("spring.cloud.gcp.sql.enabled", "false")
            .equals("true") ? "Cloud SQL Connector" : "HikariCP";
        metrics.put("connectionPool", poolType);

        // Startup metrics
        metrics.put("startupTimeMs", applicationStartupMillis);
        metrics.put("startupTimeSeconds", String.format("%.3f", applicationStartupMillis / 1000.0));

        // Uptime
        long uptimeMillis = System.currentTimeMillis() - ManagementFactory.getRuntimeMXBean().getStartTime();
        metrics.put("uptimeMs", uptimeMillis);
        metrics.put("uptimeSeconds", String.format("%.3f", uptimeMillis / 1000.0));

        // Memory usage
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
        metrics.put("memory", memory);

        // JVM info
        Map<String, Object> jvm = new LinkedHashMap<>();
        jvm.put("version", System.getProperty("java.version"));
        jvm.put("vendor", System.getProperty("java.vendor"));
        jvm.put("name", System.getProperty("java.vm.name"));
        metrics.put("jvm", jvm);

        // Timestamp
        metrics.put("timestamp", Instant.now().toString());

        return metrics;
    }

    @GetMapping("/metrics/startup")
    public Map<String, Object> getStartupMetrics() {
        Map<String, Object> startup = new LinkedHashMap<>();

        startup.put("imageType", isNativeImage() ? "Native (GraalVM)" : "JVM");
        startup.put("startupTimeMs", applicationStartupMillis);
        startup.put("startupTimeSeconds", String.format("%.3f", applicationStartupMillis / 1000.0));
        startup.put("profile", environment.getActiveProfiles().length > 0
            ? environment.getActiveProfiles()[0] : "default");

        return startup;
    }

    @GetMapping("/metrics/memory")
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

    private boolean isNativeImage() {
        // Check if running as native image
        return System.getProperty("org.graalvm.nativeimage.imagecode") != null;
    }
}
