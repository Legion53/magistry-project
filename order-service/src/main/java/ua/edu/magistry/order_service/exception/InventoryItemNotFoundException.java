package ua.edu.magistry.order_service.exception;

public class InventoryItemNotFoundException extends RuntimeException {

    public InventoryItemNotFoundException(Long productId) {
        super("Product with productId=" + productId + " was not found");
    }
}