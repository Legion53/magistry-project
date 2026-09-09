package ua.edu.magistry.order_service.config;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.http.client.ClientHttpRequestFactoryBuilder;
import org.springframework.boot.http.client.HttpClientSettings;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration(proxyBeanMethods = false)
public class HttpClientConfig {

    @Bean
    RestClient inventoryRestClient(
            @Value("${inventory.base-url}") String baseUrl,
            @Value("${inventory.connect-timeout}") Duration connectTimeout,
            @Value("${inventory.read-timeout}") Duration readTimeout
    ) {
        HttpClientSettings settings = HttpClientSettings.defaults()
                .withConnectTimeout(connectTimeout)
                .withReadTimeout(readTimeout);

        return RestClient.builder()
                .baseUrl(baseUrl)
                .requestFactory(
                        ClientHttpRequestFactoryBuilder.detect().build(settings)
                )
                .build();
    }
}