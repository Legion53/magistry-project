package ua.edu.magistry.inventory_service.context;

import java.util.Objects;

public record TraceContext(String traceId) {

    public static final String HEADER_NAME = "X-Trace-Id";

    public TraceContext {
        Objects.requireNonNull(traceId, "traceId must not be null");

        if (traceId.isBlank()) {
            throw new IllegalArgumentException("traceId must not be blank");
        }
    }
}