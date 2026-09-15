package ua.edu.magistry.order_service.service;

import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClientException;
import ua.edu.magistry.order_service.client.InventoryClient;
import ua.edu.magistry.order_service.dto.CreateOrderRequest;
import ua.edu.magistry.order_service.dto.InventoryResponse;
import ua.edu.magistry.order_service.dto.OrderResponse;
import ua.edu.magistry.order_service.dto.OrderStatus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class OrderServiceTest {

    private final InventoryClient inventoryClient = mock(InventoryClient.class);
    private final OrderService orderService = new OrderService(inventoryClient);

    @Test
    void acceptsOrderWhenInventoryIsSufficient() {
        when(inventoryClient.getByProductId(1L))
                .thenReturn(new InventoryResponse(1L, "Product 1", 100));

        OrderResponse response =
                orderService.createOrder(new CreateOrderRequest(1L, 2));

        assertEquals(OrderStatus.ACCEPTED, response.status());
        assertEquals(1L, response.productId());
        assertEquals(2, response.requestedQuantity());
        assertEquals(100, response.availableQuantity());
    }

    @Test
    void rejectsOrderWhenInventoryIsInsufficient() {
        when(inventoryClient.getByProductId(1L))
                .thenReturn(new InventoryResponse(1L, "Product 1", 100));

        OrderResponse response =
                orderService.createOrder(new CreateOrderRequest(1L, 101));

        assertEquals(OrderStatus.REJECTED, response.status());
        assertEquals(101, response.requestedQuantity());
        assertEquals(100, response.availableQuantity());
    }

    @Test
    void propagatesExceptionWhenInventoryServiceIsUnavailable() {
        RestClientException unavailable =
                new RestClientException("inventory-service is unavailable");

        when(inventoryClient.getByProductId(1L))
                .thenThrow(unavailable);

        RestClientException exception = assertThrows(
                RestClientException.class,
                () -> orderService.createOrder(
                        new CreateOrderRequest(1L, 2)
                )
        );

        assertSame(unavailable, exception);
    }
}