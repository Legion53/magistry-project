package ua.edu.magistry.inventory_service.config;

import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import ua.edu.magistry.inventory_service.entity.InventoryItem;
import ua.edu.magistry.inventory_service.repository.InventoryItemRepository;

import java.util.List;

@Configuration(proxyBeanMethods = false)
public class SeedDataConfig {

    @Bean
    ApplicationRunner seedInventory(InventoryItemRepository repository) {
        return arguments -> {
            if (repository.count() != 0) {
                return;
            }

            repository.saveAll(List.of(
                    new InventoryItem(1L, "Product 1", 100),
                    new InventoryItem(2L, "Product 2", 0)
            ));
        };
    }
}