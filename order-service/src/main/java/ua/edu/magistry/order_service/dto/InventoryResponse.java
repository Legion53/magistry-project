package ua.edu.magistry.order_service.dto;

public record InventoryResponse(
        Long productId,
        String name,
        Integer quantity
) {
}