package demo.model;

import java.time.Instant;
import java.util.Map;

public record ApiResponse(
    String status,
    String flow,
    Map<String, Object> data,
    Instant timestamp
) {
    public static ApiResponse ok(String flow, Map<String, Object> data) {
        return new ApiResponse("ok", flow, data, Instant.now());
    }
}
