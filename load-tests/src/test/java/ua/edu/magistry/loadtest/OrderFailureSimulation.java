package ua.edu.magistry.loadtest;

import io.gatling.javaapi.http.HttpProtocolBuilder;
import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;

import java.time.Duration;

import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

public class OrderFailureSimulation
        extends Simulation {

    private final String baseUrl =
            System.getProperty(
                    "baseUrl",
                    "http://localhost:8080"
            );

    private final double usersPerSecond =
            Double.parseDouble(
                    System.getProperty(
                            "usersPerSecond",
                            "20"
                    )
            );

    private final int durationSeconds =
            Integer.getInteger(
                    "durationSeconds",
                    90
            );

    private final int startDelaySeconds =
            Integer.getInteger(
                    "startDelaySeconds",
                    2
            );

    public OrderFailureSimulation() {

        if (usersPerSecond <= 0.0
                || durationSeconds <= 0) {

            throw new IllegalArgumentException(
                    "usersPerSecond and "
                            + "durationSeconds must be > 0"
            );
        }

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
                        "Day 09 - Failure and recovery"
                )

                        .exec(
                                http(
                                        "POST /orders"
                                )
                                        .post("/orders")
                                        .body(
                                                RawFileBody(
                                                        "bodies/order.json"
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

                        constantUsersPerSec(
                                usersPerSecond
                        )
                                .during(
                                        Duration.ofSeconds(
                                                durationSeconds
                                        )
                                )
                )
        )
                .protocols(httpProtocol)

                .maxDuration(
                        Duration.ofSeconds(
                                startDelaySeconds
                                        + durationSeconds
                                        + 60L
                        )
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