package ua.edu.magistry.inventory_service.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import ua.edu.magistry.inventory_service.context.ContextAccessor;
import ua.edu.magistry.inventory_service.context.TraceContext;

@RestController
@RequestMapping("/test")
@RequiredArgsConstructor
public class ContextController {

    private final ContextAccessor contextAccessor;

    @GetMapping("/context")
    public ContextResponse getContext() {

        TraceContext context =
                contextAccessor.current();

        if (context == null) {
            throw new IllegalStateException(
                    "Trace context is not available"
            );
        }

        return new ContextResponse(
                context.traceId(),
                Thread.currentThread().isVirtual(),
                Thread.currentThread().getName()
        );
    }

    public record ContextResponse(
            String traceId,
            boolean virtual,
            String thread
    ) {
    }
}