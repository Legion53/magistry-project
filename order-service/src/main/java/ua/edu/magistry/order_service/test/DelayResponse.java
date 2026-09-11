package ua.edu.magistry.order_service.test;

public record DelayResponse(
        long delayMs,
        long elapsedMs,
        boolean virtual,
        String thread
) {
}
