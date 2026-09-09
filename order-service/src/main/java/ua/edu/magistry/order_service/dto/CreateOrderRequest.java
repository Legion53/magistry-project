package ua.edu.magistry.order_service.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record CreateOrderRequest(
        @NotNull @Positive Long productId,
        @NotNull @Positive Integer quantity
) {
}