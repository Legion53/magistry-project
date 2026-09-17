package ua.edu.magistry.inventory_service.context;

import jakarta.servlet.ServletException;
import org.junit.jupiter.api.Test;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ThreadLocalContextAccessorTest {

    private final ThreadLocalContextAccessor accessor =
            new ThreadLocalContextAccessor();

    @Test
    void contextIsVisibleInsideScopeAndRemovedOutside() throws Exception {
        TraceContext context =
                new TraceContext("test-trace-id");

        assertNull(accessor.current());

        accessor.run(
                context,
                () -> assertSame(context, accessor.current())
        );

        assertNull(accessor.current());
    }

    @Test
    void nestedContextRestoresPreviousContext() throws Exception {
        TraceContext outer =
                new TraceContext("outer");

        TraceContext inner =
                new TraceContext("inner");

        accessor.run(outer, () -> {

            assertSame(
                    outer,
                    accessor.current()
            );

            accessor.run(inner, () -> {

                assertSame(
                        inner,
                        accessor.current()
                );
            });

            assertSame(
                    outer,
                    accessor.current()
            );
        });

        assertNull(accessor.current());
    }

    @Test
    void checkedExceptionsArePreserved() {
        TraceContext context =
                new TraceContext("test-trace-id");

        ServletException servletException =
                new ServletException("servlet");

        ServletException actualServletException =
                assertThrows(
                        ServletException.class,
                        () -> accessor.run(
                                context,
                                () -> {
                                    throw servletException;
                                }
                        )
                );

        assertSame(
                servletException,
                actualServletException
        );

        IOException ioException =
                new IOException("io");

        IOException actualIoException =
                assertThrows(
                        IOException.class,
                        () -> accessor.run(
                                context,
                                () -> {
                                    throw ioException;
                                }
                        )
                );

        assertSame(
                ioException,
                actualIoException
        );

        assertNull(accessor.current());
    }
}
