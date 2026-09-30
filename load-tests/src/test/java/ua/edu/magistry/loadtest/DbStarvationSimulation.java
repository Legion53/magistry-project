package ua.edu.magistry.loadtest;

import io.gatling.javaapi.http.HttpProtocolBuilder;
import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;

import java.time.Duration;

import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

public class DbStarvationSimulation
        extends Simulation {

    private final String baseUrl =
            System.getProperty(
                    "baseUrl",
                    "http://localhost:8081"
            );

    private final int totalRequests =
            Integer.getInteger(
                    "totalRequests",
                    10_000
            );

    private final int concurrency =
            Integer.getInteger(
                    "concurrency",
                    100
            );

    private final int startDelaySeconds =
            Integer.getInteger(
                    "startDelaySeconds",
                    2
            );

    public DbStarvationSimulation() {

        if (totalRequests <= 0) {
            throw new IllegalArgumentException(
                    "totalRequests must be > 0"
            );
        }

        if (concurrency <= 0) {
            throw new IllegalArgumentException(
                    "concurrency must be > 0"
            );
        }

        if (totalRequests % concurrency != 0) {
            throw new IllegalArgumentException(
                    "totalRequests must be divisible "
                            + "by concurrency"
            );
        }

        int requestsPerUser =
                totalRequests / concurrency;

        HttpProtocolBuilder httpProtocol =
                http
                        .baseUrl(baseUrl)
                        .acceptHeader(
                                "application/json"
                        );

        ScenarioBuilder scenario =
                scenario(
                        "Day 09 - DB starvation"
                )
                        .repeat(
                                requestsPerUser
                        )
                        .on(
                                exec(
                                        http(
                                                "GET /test/db-starvation"
                                        )
                                                .get(
                                                        "/test/db-starvation"
                                                )
                                                .check(
                                                        status()
                                                                .is(200),

                                                        jsonPath(
                                                                "$.delayMs"
                                                        )
                                                                .ofLong()
                                                                .is(100L),

                                                        jsonPath(
                                                                "$.virtual"
                                                        )
                                                                .ofBoolean()
                                                                .is(true)
                                                )
                                )
                        );

        setUp(
                scenario.injectOpen(
                        nothingFor(
                                Duration.ofSeconds(
                                        startDelaySeconds
                                )
                        ),
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

    @Override
    public void before() {

        MarkerSupport.writeInstantMarker(
                "startMarker"
        );
    }

    @Override
    public void after() {

        MarkerSupport.writeInstantMarker(
                "endMarker"
        );
    }
}