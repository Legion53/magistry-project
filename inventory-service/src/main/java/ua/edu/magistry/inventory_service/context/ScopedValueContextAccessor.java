package ua.edu.magistry.inventory_service.context;

import jakarta.servlet.ServletException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Objects;
import java.util.concurrent.Callable;

@Component
@ConditionalOnProperty(
        name = "context.propagation.mode",
        havingValue = "scoped",
        matchIfMissing = true
)
public class ScopedValueContextAccessor implements ContextAccessor {

    private static final ScopedValue<TraceContext> CONTEXT =
            ScopedValue.newInstance();

    @Override
    public TraceContext current() {
        return CONTEXT.isBound()
                ? CONTEXT.get()
                : null;
    }

    @Override
    public void run(TraceContext context, ContextAction action)
            throws ServletException, IOException {

        Objects.requireNonNull(context, "context must not be null");
        Objects.requireNonNull(action, "action must not be null");

        try {
            ScopedValue.where(CONTEXT, context).call(() -> {
                try {
                    action.execute();
                } catch (ServletException | IOException exception) {
                    throw new ContextExecutionException(exception);
                }
                return null;
            });
        } catch (ContextExecutionException exception) {
            Throwable cause = exception.getCause();

            if (cause instanceof ServletException servletException) {
                throw servletException;
            }

            if (cause instanceof IOException ioException) {
                throw ioException;
            }

            if (cause instanceof RuntimeException runtimeException) {
                throw runtimeException;
            }

            throw exception;
        } catch (RuntimeException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new IllegalStateException(
                    "Unexpected exception while executing scoped context",
                    exception
            );
        }
    }

    private static final class ContextExecutionException
            extends RuntimeException {

        private ContextExecutionException(Throwable cause) {
            super(cause);
        }
    }
}