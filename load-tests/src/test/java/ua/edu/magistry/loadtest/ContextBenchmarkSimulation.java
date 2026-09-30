package ua.edu.magistry.loadtest;

import io.gatling.javaapi.http.HttpProtocolBuilder;
import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;

import java.time.Duration;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;

import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

public class ContextBenchmarkSimulation
        extends Simulation {

    private final String baseUrl =
            System.getProperty(
                    "baseUrl",
                    "http://localhost:8080"
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

    private final int reads =
            Integer.getInteger(
                    "reads",
                    10_000
            );

    private final int startDelaySeconds =
            Integer.getInteger(
                    "startDelaySeconds",
                    2
            );

    private final String expectedImplementation =
            System.getProperty(
                    "expectedImplementation",
                    "ScopedValueContextAccessor"
            );

    private final Queue<Long> elapsedMicros =
            new ConcurrentLinkedQueue<>();

    public ContextBenchmarkSimulation() {

        if (totalRequests <= 0
                || concurrency <= 0) {

            throw new IllegalArgumentException(
                    "totalRequests and concurrency "
                            + "must be > 0"
            );
        }

        if (totalRequests % concurrency != 0) {

            throw new IllegalArgumentException(
                    "totalRequests must be "
                            + "divisible by concurrency"
            );
        }

        if (reads < 1 || reads > 100_000) {

            throw new IllegalArgumentException(
                    "reads must be between "
                            + "1 and 100000"
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
                        "Day 09 - Context benchmark"
                )

                        .repeat(
                                requestsPerUser
                        )
                        .on(

                                exec(
                                        http(
                                                "GET /test/context-benchmark"
                                        )
                                                .get(
                                                        "/test/context-benchmark"
                                                                + "?reads="
                                                                + reads
                                                )
                                                .check(
                                                        status()
                                                                .is(200),

                                                        jsonPath(
                                                                "$.reads"
                                                        )
                                                                .ofInt()
                                                                .is(reads),

                                                        jsonPath(
                                                                "$.virtual"
                                                        )
                                                                .ofBoolean()
                                                                .is(true),

                                                        jsonPath(
                                                                "$.contextImplementation"
                                                        )
                                                                .is(
                                                                        expectedImplementation
                                                                ),

                                                        jsonPath(
                                                                "$.elapsedMicros"
                                                        )
                                                                .ofLong()
                                                                .saveAs(
                                                                        "elapsedMicros"
                                                                )
                                                )
                                )

                                        .exec(session -> {

                                            if (
                                                    session.contains(
                                                            "elapsedMicros"
                                                    )
                                            ) {

                                                elapsedMicros.add(
                                                        session.getLong(
                                                                "elapsedMicros"
                                                        )
                                                );
                                            }

                                            return session.remove(
                                                    "elapsedMicros"
                                            );
                                        })
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

        MarkerSupport.writeLongSeriesCsv(
                "contextSamplesPath",
                "elapsed_micros",
                elapsedMicros
        );
    }
}