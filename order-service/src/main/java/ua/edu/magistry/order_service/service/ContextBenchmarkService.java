package ua.edu.magistry.order_service.service;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import ua.edu.magistry.order_service.context.ContextAccessor;
import ua.edu.magistry.order_service.context.TraceContext;

@Service
@RequiredArgsConstructor
public class ContextBenchmarkService {

    private final ContextAccessor contextAccessor;

    public ContextBenchmarkResult run(int reads) {

        if (reads < 1 || reads > 100_000) {
            throw new IllegalArgumentException(
                    "reads must be between 1 and 100000"
            );
        }

        TraceContext initialContext =
                contextAccessor.current();

        if (initialContext == null) {
            throw new IllegalStateException(
                    "Trace context is not available"
            );
        }

        long start =
                System.nanoTime();

        long checksum = 0;

        for (int i = 0; i < reads; i++) {

            TraceContext context =
                    contextAccessor.current();

            if (context == null) {
                throw new IllegalStateException(
                        "Trace context disappeared during benchmark"
                );
            }

            checksum =
                    31 * checksum
                            + context.traceId()
                            .charAt(i % context.traceId().length());
        }

        long elapsedMicros =
                (System.nanoTime() - start) / 1_000;

        return new ContextBenchmarkResult(
                initialContext.traceId(),
                reads,
                checksum,
                elapsedMicros,
                Thread.currentThread().isVirtual(),
                Thread.currentThread().getName(),
                contextAccessor
                        .getClass()
                        .getSimpleName()
        );
    }

    public record ContextBenchmarkResult(
            String traceId,
            int reads,
            long checksum,
            long elapsedMicros,
            boolean virtual,
            String thread,
            String contextImplementation
    ) {
    }
}