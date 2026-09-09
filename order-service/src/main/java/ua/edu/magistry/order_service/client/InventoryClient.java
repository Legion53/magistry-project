package ua.edu.magistry.order_service.client;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import ua.edu.magistry.order_service.dto.InventoryResponse;
import ua.edu.magistry.order_service.exception.InventoryItemNotFoundException;

@Component
@RequiredArgsConstructor
public class InventoryClient {

    private final RestClient inventoryRestClient;

    public InventoryResponse getInventory(long productId) {
        try {
            return inventoryRestClient.get()
                    .uri("/inventory/{productId}", productId)
                    .retrieve()
                    .requiredBody(InventoryResponse.class);
        } catch (RestClientResponseException exception) {
            if (exception.getStatusCode().value() == 404) {
                throw new InventoryItemNotFoundException(productId, exception);
            }

            throw exception;
        }
    }
}