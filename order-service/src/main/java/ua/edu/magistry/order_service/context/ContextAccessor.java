package ua.edu.magistry.order_service.context;

import jakarta.servlet.ServletException;

import java.io.IOException;

public interface ContextAccessor {

    TraceContext current();

    void run(
            TraceContext context,
            ContextAction action
    ) throws ServletException, IOException;
}