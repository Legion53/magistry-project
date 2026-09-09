package ua.edu.magistry.order_service.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.RestClientException;

import ua.edu.magistry.order_service.exception.InventoryItemNotFoundException;

@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(InventoryItemNotFoundException.class)
    ProblemDetail handleInventoryNotFound(InventoryItemNotFoundException exception) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.NOT_FOUND,
                exception.getMessage()
        );
        problem.setTitle("Inventory item not found");

        return problem;
    }

    @ExceptionHandler(RestClientException.class)
    ProblemDetail handleInventoryUnavailable(RestClientException exception) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.SERVICE_UNAVAILABLE,
                "inventory-service is unavailable or did not respond in time"
        );
        problem.setTitle("Downstream service unavailable");

        return problem;
    }
}