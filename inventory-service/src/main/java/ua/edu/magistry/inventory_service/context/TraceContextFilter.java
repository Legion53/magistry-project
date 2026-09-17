package ua.edu.magistry.inventory_service.context;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
@RequiredArgsConstructor
public class TraceContextFilter extends OncePerRequestFilter {

    private final ContextAccessor contextAccessor;
    private final TraceContextFactory traceContextFactory;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String uri = request.getRequestURI();

        return uri.startsWith("/actuator")
                || uri.equals("/test/delay");
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {

        TraceContext context =
                traceContextFactory.fromHeader(
                        request.getHeader(TraceContext.HEADER_NAME)
                );

        response.setHeader(
                TraceContext.HEADER_NAME,
                context.traceId()
        );

        contextAccessor.run(
                context,
                () -> filterChain.doFilter(request, response)
        );
    }
}