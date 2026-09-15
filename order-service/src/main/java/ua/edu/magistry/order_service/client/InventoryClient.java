package ua.edu.magistry.order_service.client;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import ua.edu.magistry.order_service.dto.InventoryResponse;
import ua.edu.magistry.order_service.exception.InventoryItemNotFoundException;


@Component
public class InventoryClient {

    private final RestClient restClient;
    private final Tracer tracer;

    public InventoryClient(
            RestClient restClient,
            @Qualifier("openTelemetry") OpenTelemetry openTelemetry) {

        this.restClient = restClient;
        this.tracer = openTelemetry.getTracer(
                "ua.edu.thesis.order.inventory-client");
    }

    public InventoryResponse getByProductId(Long productId) {

        Span span = tracer
                .spanBuilder("check-inventory")
                .setSpanKind(SpanKind.INTERNAL)
                .startSpan();

        try (Scope ignored = span.makeCurrent()) {

            return restClient
                    .get()
                    .uri("/inventory/{productId}", productId)
                    .retrieve()

                    .onStatus(
                            status -> status.value() == HttpStatus.NOT_FOUND.value(),
                            (request, response) -> {
                                throw new InventoryItemNotFoundException(
                                        productId);
                            })
                    
                    .body(InventoryResponse.class);

        } catch (RestClientResponseException exception) {

            span.recordException(exception);
            span.setStatus(StatusCode.ERROR);

            throw exception;

        } catch (RuntimeException exception) {

            span.recordException(exception);
            span.setStatus(StatusCode.ERROR);

            throw exception;

        } finally {

            span.end();
        }
    }
}