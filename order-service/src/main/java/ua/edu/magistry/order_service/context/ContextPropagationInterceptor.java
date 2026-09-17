package ua.edu.magistry.order_service.context;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpRequest;
import org.springframework.http.client.ClientHttpRequestExecution;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Component
@RequiredArgsConstructor
public class ContextPropagationInterceptor
        implements ClientHttpRequestInterceptor {

    private final ContextAccessor contextAccessor;

    @Override
    public ClientHttpResponse intercept(
            HttpRequest request,
            byte[] body,
            ClientHttpRequestExecution execution
    ) throws IOException {

        TraceContext context =
                contextAccessor.current();

        if (context != null) {
            request.getHeaders().set(
                    TraceContext.HEADER_NAME,
                    context.traceId()
            );
        }

        return execution.execute(request, body);
    }
}