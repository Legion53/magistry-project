package ua.edu.magistry.inventory_service.test;

public record DbStarvationResponse(
        long delayMs,
        long elapsedMs,
        boolean virtual,
        String thread
) {
}