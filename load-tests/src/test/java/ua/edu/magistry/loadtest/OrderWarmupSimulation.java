package ua.edu.magistry.loadtest;

import io.gatling.javaapi.http.HttpProtocolBuilder;
import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;

import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

public class OrderWarmupSimulation
        extends Simulation {

    public OrderWarmupSimulation() {

        String baseUrl =
                System.getProperty(
                        "baseUrl",
                        "http://localhost:8080"
                );

        int totalRequests =
                Integer.getInteger(
                        "totalRequests",
                        500
                );

        int concurrency =
                Integer.getInteger(
                        "concurrency",
                        20
                );

        if (totalRequests <= 0
                || concurrency <= 0
                || totalRequests % concurrency != 0) {

            throw new IllegalArgumentException(
                    "totalRequests must be > 0 "
                            + "and divisible by concurrency"
            );
        }

        int requestsPerUser =
                totalRequests / concurrency;

        HttpProtocolBuilder httpProtocol =
                http
                        .baseUrl(baseUrl)
                        .contentTypeHeader(
                                "application/json"
                        )
                        .acceptHeader(
                                "application/json"
                        );

        ScenarioBuilder scenario =
                scenario(
                        "Day 09 - Order warm-up"
                )

                        .repeat(
                                requestsPerUser
                        )
                        .on(

                                exec(
                                        http(
                                                "POST /orders"
                                        )
                                                .post("/orders")
                                                .body(
                                                        RawFileBody(
                                                                "bodies/order.json"
                                                        )
                                                )
                                                .check(
                                                        status()
                                                                .is(200)
                                                )
                                )
                        );

        setUp(
                scenario.injectOpen(
                        atOnceUsers(
                                concurrency
                        )
                )
        )
                .protocols(httpProtocol)
                .assertions(
                        global()
                                .failedRequests()
                                .count()
                                .is(0L)
                );
    }
}