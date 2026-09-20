package ua.edu.magistry.order_service.service;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.web.client.RestClientException;
import ua.edu.magistry.order_service.client.InventoryClient;
import ua.edu.magistry.order_service.dto.CreateOrderRequest;
import ua.edu.magistry.order_service.dto.InventoryResponse;
import ua.edu.magistry.order_service.dto.OrderResponse;
import ua.edu.magistry.order_service.dto.OrderStatus;
import ua.edu.magistry.order_service.exception.InventoryItemNotFoundException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SpringBootTest
@TestPropertySource(properties = {
        "resilience4j.retry.instances.inventoryService.maxAttempts=3",
        "resilience4j.retry.instances.inventoryService.waitDuration=10ms",
        "resilience4j.retry.instances.inventoryService.enableExponentialBackoff=false",

        "resilience4j.retry.instances.inventoryService.retryExceptions[0]=org.springframework.web.client.RestClientException",
        "resilience4j.retry.instances.inventoryService.ignoreExceptions[0]=ua.edu.magistry.order_service.exception.InventoryItemNotFoundException",
        "resilience4j.retry.instances.inventoryService.ignoreExceptions[1]=io.github.resilience4j.circuitbreaker.CallNotPermittedException",

        "resilience4j.circuitbreaker.instances.inventoryService.slidingWindowType=COUNT_BASED",
        "resilience4j.circuitbreaker.instances.inventoryService.slidingWindowSize=10",
        "resilience4j.circuitbreaker.instances.inventoryService.minimumNumberOfCalls=5",
        "resilience4j.circuitbreaker.instances.inventoryService.failureRateThreshold=50",
        "resilience4j.circuitbreaker.instances.inventoryService.waitDurationInOpenState=30s",
        "resilience4j.circuitbreaker.instances.inventoryService.permittedNumberOfCallsInHalfOpenState=2",

        "resilience4j.circuitbreaker.instances.inventoryService.ignoreExceptions[0]=ua.edu.magistry.order_service.exception.InventoryItemNotFoundException"
})
class OrderServiceTest {

    @MockitoBean
    private InventoryClient inventoryClient;

    @Autowired
    private OrderService orderService;

    @Autowired
    private CircuitBreakerRegistry circuitBreakerRegistry;

    @BeforeEach
    void setUp() {
        reset(inventoryClient);

        circuitBreakerRegistry
                .circuitBreaker("inventoryService")
                .reset();
    }

    // -------------------------------------------------------------------------
    // 1. Inventory available -> ACCEPTED
    // -------------------------------------------------------------------------

    @Test
    void acceptsOrderWhenInventoryIsSufficient() {

        when(inventoryClient.getByProductId(1L))
                .thenReturn(
                        new InventoryResponse(
                                1L,
                                "Product 1",
                                100
                        )
                );

        OrderResponse response =
                orderService.createOrder(
                        new CreateOrderRequest(1L, 2)
                );

        assertEquals(
                OrderStatus.ACCEPTED,
                response.status()
        );

        assertEquals(
                1L,
                response.productId()
        );

        assertEquals(
                2,
                response.requestedQuantity()
        );

        assertEquals(
                100,
                response.availableQuantity()
        );

        verify(
                inventoryClient,
                times(1)
        ).getByProductId(1L);
    }

    // -------------------------------------------------------------------------
    // 2. Insufficient stock -> REJECTED
    // -------------------------------------------------------------------------

    @Test
    void rejectsOrderWhenInventoryIsInsufficient() {

        when(inventoryClient.getByProductId(1L))
                .thenReturn(
                        new InventoryResponse(
                                1L,
                                "Product 1",
                                100
                        )
                );

        OrderResponse response =
                orderService.createOrder(
                        new CreateOrderRequest(1L, 101)
                );

        assertEquals(
                OrderStatus.REJECTED,
                response.status()
        );

        assertEquals(
                1L,
                response.productId()
        );

        assertEquals(
                101,
                response.requestedQuantity()
        );

        assertEquals(
                100,
                response.availableQuantity()
        );

        verify(
                inventoryClient,
                times(1)
        ).getByProductId(1L);
    }

    // -------------------------------------------------------------------------
    // 3. Inventory unavailable -> TEMPORARILY_UNAVAILABLE
    // -------------------------------------------------------------------------

    @Test
    void returnsTemporarilyUnavailableWhenInventoryServiceIsUnavailable() {

        when(inventoryClient.getByProductId(1L))
                .thenThrow(
                        new RestClientException(
                                "inventory-service is unavailable"
                        )
                );

        OrderResponse response =
                orderService.createOrder(
                        new CreateOrderRequest(1L, 2)
                );

        assertEquals(
                OrderStatus.TEMPORARILY_UNAVAILABLE,
                response.status()
        );

        assertEquals(
                1L,
                response.productId()
        );

        assertEquals(
                2,
                response.requestedQuantity()
        );

        assertEquals(
                null,
                response.availableQuantity()
        );
    }

    // -------------------------------------------------------------------------
    // 4. Retry -> three attempts
    // -------------------------------------------------------------------------

    @Test
    void retriesWhenInventoryServiceFails() {

        when(inventoryClient.getByProductId(1L))
                .thenThrow(
                        new RestClientException(
                                "inventory-service is unavailable"
                        )
                );

        OrderResponse response =
                orderService.createOrder(
                        new CreateOrderRequest(1L, 2)
                );

        assertEquals(
                OrderStatus.TEMPORARILY_UNAVAILABLE,
                response.status()
        );

        verify(
                inventoryClient,
                times(3)
        ).getByProductId(1L);
    }

    // -------------------------------------------------------------------------
    // 5. Circuit Breaker -> OPEN
    // -------------------------------------------------------------------------

    @Test
    void opensCircuitBreakerAfterRepeatedFailures() {

        when(inventoryClient.getByProductId(1L))
                .thenThrow(
                        new RestClientException(
                                "inventory-service is unavailable"
                        )
                );

        /*
         * minimumNumberOfCalls = 5
         *
         * Retry performs up to three attempts for each failed
         * createOrder() invocation.
         */
        for (int i = 0; i < 3; i++) {

            OrderResponse response =
                    orderService.createOrder(
                            new CreateOrderRequest(1L, 2)
                    );

            assertEquals(
                    OrderStatus.TEMPORARILY_UNAVAILABLE,
                    response.status()
            );
        }

        /*
         * Remove previous Mockito interactions.
         */
        clearInvocations(inventoryClient);

        /*
         * Circuit Breaker should now be OPEN.
         *
         * Therefore InventoryClient must not be called.
         */
        OrderResponse response =
                orderService.createOrder(
                        new CreateOrderRequest(1L, 2)
                );

        assertEquals(
                OrderStatus.TEMPORARILY_UNAVAILABLE,
                response.status()
        );

        verify(
                inventoryClient,
                times(0)
        ).getByProductId(1L);
    }

    // -------------------------------------------------------------------------
    // 6. 404 -> no retry storm
    // -------------------------------------------------------------------------

    @Test
    void doesNotRetryWhenInventoryItemIsNotFound() {

        InventoryItemNotFoundException notFound =
                new InventoryItemNotFoundException(999L);

        when(inventoryClient.getByProductId(999L))
                .thenThrow(notFound);

        InventoryItemNotFoundException exception =
                assertThrows(
                        InventoryItemNotFoundException.class,
                        () -> orderService.createOrder(
                                new CreateOrderRequest(999L, 1)
                        )
                );

        assertEquals(
                "Product with productId=999 was not found",
                exception.getMessage()
        );

        /*
         * 404 must not cause three Retry attempts.
         */
        verify(
                inventoryClient,
                times(1)
        ).getByProductId(999L);
    }
}