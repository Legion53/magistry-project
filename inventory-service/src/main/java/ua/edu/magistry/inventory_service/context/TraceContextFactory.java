package ua.edu.magistry.inventory_service.context;

import org.springframework.stereotype.Component;

import java.util.UUID;
import java.util.regex.Pattern;

@Component
public class TraceContextFactory {

    private static final Pattern SAFE_TRACE_ID =
            Pattern.compile("[A-Za-z0-9._:-]{1,128}");

    public TraceContext fromHeader(String headerValue) {
        if (headerValue == null || headerValue.isBlank()) {
            return new TraceContext(generateTraceId());
        }

        String normalized = headerValue.trim();

        if (!SAFE_TRACE_ID.matcher(normalized).matches()) {
            return new TraceContext(generateTraceId());
        }

        return new TraceContext(normalized);
    }

    private String generateTraceId() {
        return UUID.randomUUID()
                .toString()
                .replace("-", "");
    }
}