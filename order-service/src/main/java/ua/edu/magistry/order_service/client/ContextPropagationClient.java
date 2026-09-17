package ua.edu.magistry.order_service.client;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
@RequiredArgsConstructor
public class ContextPropagationClient {

    private final RestClient restClient;

    public RemoteContextResponse getInventoryContext() {

        RemoteContextResponse response =
                restClient.get()
                        .uri("/test/context")
                        .retrieve()
                        .body(RemoteContextResponse.class);

        if (response == null) {
            throw new IllegalStateException(
                    "inventory-service returned empty context response"
            );
        }

        return response;
    }
}