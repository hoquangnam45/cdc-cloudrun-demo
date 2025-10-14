package com.example.quarkus_cloud_run.health;

import io.agroal.api.AgroalDataSource;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;

import java.sql.Connection;
import java.sql.SQLException;

@Readiness
@ApplicationScoped
public class DatabaseHealthIndicator implements HealthCheck {

    @Inject
    AgroalDataSource dataSource;

    @Override
    public HealthCheckResponse call() {
        try (Connection connection = dataSource.getConnection()) {
            if (connection.isValid(1)) {
                return HealthCheckResponse.up("Database connection is valid.");
            }
        } catch (SQLException e) {
            return HealthCheckResponse.down("Database connection is not valid.");
        }
        return HealthCheckResponse.down("Database connection is not valid.");
    }
}