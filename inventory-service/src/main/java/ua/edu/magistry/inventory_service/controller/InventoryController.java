package ua.edu.magistry.inventory_service.controller;

import jakarta.validation.constraints.Positive;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import ua.edu.magistry.inventory_service.dto.InventoryResponse;
import ua.edu.magistry.inventory_service.service.InventoryService;

@RestController
@RequestMapping("/inventory")
@Validated
public class InventoryController {

    private final InventoryService inventoryService;

    public InventoryController(InventoryService inventoryService) {
        this.inventoryService = inventoryService;
    }

    @GetMapping("/{productId}")
    public InventoryResponse getInventory(
            @PathVariable @Positive Long productId
    ) {
        return inventoryService.getByProductId(productId);
    }
}