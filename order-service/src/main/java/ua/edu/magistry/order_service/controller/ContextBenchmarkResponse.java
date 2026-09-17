package ua.edu.magistry.order_service.controller;

public record ContextBenchmarkResponse(
        String traceId,
        int reads,
        long checksum,
        long elapsedMicros,
        boolean virtual,
        String thread,
        String contextImplementation
) {
}