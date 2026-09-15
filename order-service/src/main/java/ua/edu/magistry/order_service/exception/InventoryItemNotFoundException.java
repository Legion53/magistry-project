package ua.edu.magistry.order_service.exception;

public class InventoryItemNotFoundException extends RuntimeException {

    public InventoryItemNotFoundException(Long productId) {
        super("Inventory item not found for productId=" + productId);
    }
}