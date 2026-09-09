package ua.edu.magistry.inventory_service.dto;

import ua.edu.magistry.inventory_service.entity.InventoryItem;

public record InventoryResponse(
        Long productId,
        String name,
        Integer quantity
) {

    public static InventoryResponse from(InventoryItem item) {
        return new InventoryResponse(
                item.getProductId(),
                item.getName(),
                item.getQuantity()
        );
    }
}