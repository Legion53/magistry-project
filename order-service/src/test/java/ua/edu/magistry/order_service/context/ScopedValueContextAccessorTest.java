package ua.edu.magistry.order_service.context;

import jakarta.servlet.ServletException;
import org.junit.jupiter.api.Test;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ScopedValueContextAccessorTest {

    private final ScopedValueContextAccessor accessor =
            new ScopedValueContextAccessor();

    @Test
    void contextIsVisibleInsideScopeAndAbsentOutside() throws Exception {
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
    void servletExceptionIsPreserved() {
        TraceContext context =
                new TraceContext("test-trace-id");

        ServletException expected =
                new ServletException("test servlet exception");

        ServletException actual =
                assertThrows(
                        ServletException.class,
                        () -> accessor.run(
                                context,
                                () -> {
                                    throw expected;
                                }
                        )
                );

        assertSame(expected, actual);

        assertNull(accessor.current());
    }

    @Test
    void ioExceptionIsPreserved() {
        TraceContext context =
                new TraceContext("test-trace-id");

        IOException expected =
                new IOException("test io exception");

        IOException actual =
                assertThrows(
                        IOException.class,
                        () -> accessor.run(
                                context,
                                () -> {
                                    throw expected;
                                }
                        )
                );

        assertSame(expected, actual);

        assertNull(accessor.current());
    }

    @Test
    void runtimeExceptionIsPreserved() {
        TraceContext context =
                new TraceContext("test-trace-id");

        IllegalStateException expected =
                new IllegalStateException("test runtime exception");

        IllegalStateException actual =
                assertThrows(
                        IllegalStateException.class,
                        () -> accessor.run(
                                context,
                                () -> {
                                    throw expected;
                                }
                        )
                );

        assertSame(expected, actual);

        assertNull(accessor.current());
    }
}