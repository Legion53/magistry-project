package ua.edu.magistry.inventory_service.service;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import ua.edu.magistry.inventory_service.dto.InventoryResponse;
import ua.edu.magistry.inventory_service.entity.InventoryItem;
import ua.edu.magistry.inventory_service.repository.InventoryItemRepository;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class InventoryServiceTest {

    private final InventoryItemRepository inventoryItemRepository = mock(InventoryItemRepository.class);
    private final InventoryService inventoryService = new InventoryService(inventoryItemRepository);

    @Test
    void returnsInventoryWhenProductExists() {
        InventoryItem item = new InventoryItem(1L, "Product 1", 100);
        when(inventoryItemRepository.findByProductId(1L)).thenReturn(Optional.of(item));

        InventoryResponse response = inventoryService.getByProductId(1L);

        assertEquals(1L, response.productId());
        assertEquals("Product 1", response.name());
        assertEquals(100, response.quantity());
    }

    @Test
    void throwsNotFoundWhenProductDoesNotExist() {
        when(inventoryItemRepository.findByProductId(999L)).thenReturn(Optional.empty());

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> inventoryService.getByProductId(999L)
        );

        assertEquals(HttpStatus.NOT_FOUND, exception.getStatusCode());
    }
}
