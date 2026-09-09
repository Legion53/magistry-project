package ua.edu.magistry.order_service.service;

import java.util.UUID;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import ua.edu.magistry.order_service.client.InventoryClient;
import ua.edu.magistry.order_service.dto.CreateOrderRequest;
import ua.edu.magistry.order_service.dto.InventoryResponse;
import ua.edu.magistry.order_service.dto.OrderResponse;
import ua.edu.magistry.order_service.dto.OrderStatus;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final InventoryClient inventoryClient;

    public OrderResponse createOrder(CreateOrderRequest request) {
        InventoryResponse inventory = inventoryClient.getInventory(request.productId());

        OrderStatus status = request.quantity() <= inventory.quantity()
                ? OrderStatus.ACCEPTED
                : OrderStatus.REJECTED;

        return new OrderResponse(
                UUID.randomUUID(),
                status,
                request.productId(),
                request.quantity(),
                inventory.quantity()
        );
    }
}