package ua.edu.magistry.order_service.exception;

public class InventoryItemNotFoundException extends RuntimeException {

    public InventoryItemNotFoundException(long productId, Throwable cause) {
        super("Product with productId=" + productId + " was not found", cause);
    }
}