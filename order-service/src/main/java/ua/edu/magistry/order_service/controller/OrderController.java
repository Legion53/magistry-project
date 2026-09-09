package ua.edu.magistry.order_service.controller;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import ua.edu.magistry.order_service.dto.CreateOrderRequest;
import ua.edu.magistry.order_service.dto.OrderResponse;
import ua.edu.magistry.order_service.dto.OrderStatus;
import ua.edu.magistry.order_service.service.OrderService;

@RestController
@RequestMapping("/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @PostMapping
    public ResponseEntity<OrderResponse> createOrder(
            @Valid @RequestBody CreateOrderRequest request
    ) {
        OrderResponse response = orderService.createOrder(request);

        HttpStatus httpStatus = response.status() == OrderStatus.REJECTED
                ? HttpStatus.CONFLICT
                : HttpStatus.OK;

        return ResponseEntity.status(httpStatus).body(response);
    }
}