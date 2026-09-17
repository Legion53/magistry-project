package ua.edu.magistry.order_service.context;

import jakarta.servlet.ServletException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Component
@ConditionalOnProperty(
        name = "context.propagation.mode",
        havingValue = "threadlocal"
)
public class ThreadLocalContextAccessor implements ContextAccessor {

    private final ThreadLocal<TraceContext> context =
            new ThreadLocal<>();

    @Override
    public TraceContext current() {
        return context.get();
    }

    @Override
    public void run(
            TraceContext traceContext,
            ContextAction action
    ) throws ServletException, IOException {

        TraceContext previous = context.get();

        context.set(traceContext);

        try {
            action.execute();
        } finally {
            if (previous == null) {
                context.remove();
            } else {
                context.set(previous);
            }
        }
    }
}