package ua.edu.magistry.order_service.dto;

import java.util.UUID;

public record OrderResponse(
        UUID orderId,
        OrderStatus status,
        Long productId,
        Integer requestedQuantity,
        Integer availableQuantity
) {
}