package ua.edu.magistry.order_service.config;

import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.http.client.ClientHttpRequestFactoryBuilder;
import org.springframework.boot.http.client.HttpClientSettings;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;
import ua.edu.magistry.order_service.context.ContextPropagationInterceptor;

import java.time.Duration;

@Configuration(proxyBeanMethods = false)
@RequiredArgsConstructor
public class HttpClientConfig {

    private final ContextPropagationInterceptor contextPropagationInterceptor;

    @Bean
    RestClient restClient(
            RestClient.Builder builder,
            @Value("${inventory.base-url}") String baseUrl,
            @Value("${inventory.connect-timeout:1s}") Duration connectTimeout,
            @Value("${inventory.read-timeout:2s}") Duration readTimeout
    ) {

        HttpClientSettings settings =
                HttpClientSettings.defaults()
                        .withConnectTimeout(connectTimeout)
                        .withReadTimeout(readTimeout);

        return builder
                .baseUrl(baseUrl)
                .requestFactory(
                        ClientHttpRequestFactoryBuilder
                                .detect()
                                .build(settings)
                )
                .requestInterceptor(
                        contextPropagationInterceptor
                )
                .build();
    }
}