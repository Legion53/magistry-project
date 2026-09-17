package ua.edu.magistry.order_service.context;

import jakarta.servlet.ServletException;

import java.io.IOException;

@FunctionalInterface
public interface ContextAction {

    void execute() throws ServletException, IOException;
}