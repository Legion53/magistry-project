package ua.edu.magistry.inventory_service.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import ua.edu.magistry.inventory_service.entity.InventoryItem;

import java.util.Optional;

public interface InventoryItemRepository extends JpaRepository<InventoryItem, Long> {

    Optional<InventoryItem> findByProductId(Long productId);
}