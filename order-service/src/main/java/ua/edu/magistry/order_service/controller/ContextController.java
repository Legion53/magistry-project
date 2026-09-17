package ua.edu.magistry.order_service.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import ua.edu.magistry.order_service.client.ContextPropagationClient;
import ua.edu.magistry.order_service.client.RemoteContextResponse;
import ua.edu.magistry.order_service.context.ContextAccessor;
import ua.edu.magistry.order_service.context.TraceContext;
import ua.edu.magistry.order_service.service.ContextBenchmarkService;

@RestController
@RequestMapping("/test")
@RequiredArgsConstructor
public class ContextController {

    private final ContextAccessor contextAccessor;
    private final ContextPropagationClient contextPropagationClient;
    private final ContextBenchmarkService contextBenchmarkService;

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

    @GetMapping("/context-propagation")
    public ContextPropagationResponse testPropagation() {

        TraceContext localContext =
                contextAccessor.current();

        if (localContext == null) {
            throw new IllegalStateException(
                    "Local trace context is not available"
            );
        }

        RemoteContextResponse remoteContext =
                contextPropagationClient
                        .getInventoryContext();

        return new ContextPropagationResponse(
                localContext.traceId(),
                remoteContext.traceId(),
                localContext.traceId()
                        .equals(remoteContext.traceId()),
                Thread.currentThread().isVirtual(),
                remoteContext.virtual()
        );
    }

    @GetMapping("/context-benchmark")
    public ContextBenchmarkResponse benchmark(
            @RequestParam(defaultValue = "1000") int reads
    ) {

        ContextBenchmarkService.ContextBenchmarkResult result =
                contextBenchmarkService.run(reads);

        return new ContextBenchmarkResponse(
                result.traceId(),
                result.reads(),
                result.checksum(),
                result.elapsedMicros(),
                result.virtual(),
                result.thread(),
                result.contextImplementation()
        );
    }

    public record ContextResponse(
            String traceId,
            boolean virtual,
            String thread
    ) {
    }

    public record ContextPropagationResponse(
            String orderTraceId,
            String inventoryTraceId,
            boolean propagated,
            boolean orderVirtual,
            boolean inventoryVirtual
    ) {
    }
}