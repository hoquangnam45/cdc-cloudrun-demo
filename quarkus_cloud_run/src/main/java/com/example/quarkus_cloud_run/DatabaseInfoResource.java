package com.example.quarkus_cloud_run;

import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.util.LinkedHashMap;
import java.util.Map;

@Path("/db-info")
@Produces(MediaType.APPLICATION_JSON)
public class DatabaseInfoResource {

    @Inject
    DataSource dataSource;

    @GET
    public Map<String, Object> getDatabaseInfo() {
        Map<String, Object> info = new LinkedHashMap<>();
        
        try (Connection conn = dataSource.getConnection()) {
            DatabaseMetaData metaData = conn.getMetaData();
            
            info.put("databaseProductName", metaData.getDatabaseProductName());
            info.put("databaseProductVersion", metaData.getDatabaseProductVersion());
            info.put("driverName", metaData.getDriverName());
            info.put("driverVersion", metaData.getDriverVersion());
            info.put("url", metaData.getURL());
            info.put("username", metaData.getUserName());
            info.put("connected", true);
            
            // Get table counts
            Map<String, Long> tableCounts = new LinkedHashMap<>();
            tableCounts.put("MyEntity", MyEntity.count());
            tableCounts.put("Message", Message.count());
            info.put("recordCounts", tableCounts);
            
            // Get connection pool info
            info.put("connectionPoolClass", dataSource.getClass().getName());
            
        } catch (Exception e) {
            info.put("error", e.getMessage());
            info.put("connected", false);
        }
        
        return info;
    }

    @GET
    @Path("/test")
    public Map<String, Object> testConnection() {
        Map<String, Object> result = new LinkedHashMap<>();
        
        try {
            // Test read
            long myEntityCount = MyEntity.count();
            long messageCount = Message.count();
            
            result.put("status", "SUCCESS");
            result.put("myEntityCount", myEntityCount);
            result.put("messageCount", messageCount);
            
            // Get sample records
            if (myEntityCount > 0) {
                MyEntity sampleEntity = MyEntity.findAll().firstResult();
                result.put("sampleMyEntity", Map.of(
                    "id", sampleEntity.id,
                    "field", sampleEntity.field
                ));
            }
            
            if (messageCount > 0) {
                Message sampleMessage = Message.findAll().firstResult();
                result.put("sampleMessage", Map.of(
                    "id", sampleMessage.id,
                    "content", sampleMessage.content
                ));
            }
            
        } catch (Exception e) {
            result.put("status", "FAILED");
            result.put("error", e.getMessage());
        }
        
        return result;
    }
}
