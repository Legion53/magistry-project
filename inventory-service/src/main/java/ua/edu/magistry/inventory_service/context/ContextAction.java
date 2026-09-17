package ua.edu.magistry.inventory_service.context;

import jakarta.servlet.ServletException;

import java.io.IOException;

@FunctionalInterface
public interface ContextAction {

    void execute() throws ServletException, IOException;
}