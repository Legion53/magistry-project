package ua.edu.magistry.order_service.client;

public record RemoteContextResponse(
        String traceId,
        boolean virtual,
        String thread
) {
}