package ua.edu.magistry.order_service.service;

import java.util.UUID;


import io.github.resilience4j.retry.annotation.Retry;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;

import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Service;

import ua.edu.magistry.order_service.client.InventoryClient;
import ua.edu.magistry.order_service.dto.CreateOrderRequest;
import ua.edu.magistry.order_service.dto.InventoryResponse;
import ua.edu.magistry.order_service.dto.OrderResponse;
import ua.edu.magistry.order_service.dto.OrderStatus;
import ua.edu.magistry.order_service.exception.InventoryItemNotFoundException;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final InventoryClient inventoryClient;

    @Retry(
            name = "inventoryService",
            fallbackMethod = "createOrderFallback"
    )
    @CircuitBreaker(
            name = "inventoryService"
    )
    public OrderResponse createOrder(CreateOrderRequest request) {

        InventoryResponse inventory =
                inventoryClient.getByProductId(request.productId());

        OrderStatus status =
                request.quantity() <= inventory.quantity()
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

    private OrderResponse createOrderFallback(
            CreateOrderRequest request,
            Throwable exception
    ) {
        if (exception instanceof InventoryItemNotFoundException notFoundException) {
            throw notFoundException;
        }

        return new OrderResponse(
                UUID.randomUUID(),
                OrderStatus.TEMPORARILY_UNAVAILABLE,
                request.productId(),
                request.quantity(),
                null
        );
    }
}