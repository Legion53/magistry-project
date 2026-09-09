package ua.edu.magistry.inventory_service.service;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import ua.edu.magistry.inventory_service.dto.InventoryResponse;
import ua.edu.magistry.inventory_service.repository.InventoryItemRepository;

@Service
@Transactional(readOnly = true)
@RequiredArgsConstructor
public class InventoryService {

    private final InventoryItemRepository inventoryItemRepository;

    public InventoryResponse getByProductId(long productId) {
        if (productId <= 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "productId must be a positive number"
            );
        }

        return inventoryItemRepository.findByProductId(productId)
                .map(InventoryResponse::from)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "Inventory item with productId=" + productId + " was not found"
                ));
    }
}