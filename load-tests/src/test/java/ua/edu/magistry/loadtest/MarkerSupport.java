package ua.edu.magistry.loadtest;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.Collection;

final class MarkerSupport {

    private MarkerSupport() {
    }

    static void writeInstantMarker(
            String propertyName
    ) {

        String rawPath =
                System.getProperty(propertyName);

        if (rawPath == null || rawPath.isBlank()) {
            return;
        }

        Path path =
                Path.of(rawPath)
                        .toAbsolutePath();

        createParent(path);

        try {

            Files.writeString(
                    path,
                    Instant.now().toString(),
                    StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE,
                    StandardOpenOption.TRUNCATE_EXISTING,
                    StandardOpenOption.WRITE
            );

        } catch (IOException exception) {

            throw new IllegalStateException(
                    "Unable to write marker: " + path,
                    exception
            );
        }
    }

    static void writeLongSeriesCsv(
            String propertyName,
            String header,
            Collection<Long> values
    ) {

        String rawPath =
                System.getProperty(propertyName);

        if (rawPath == null || rawPath.isBlank()) {
            return;
        }

        Path path =
                Path.of(rawPath)
                        .toAbsolutePath();

        createParent(path);

        StringBuilder content =
                new StringBuilder()
                        .append(header)
                        .append(System.lineSeparator());

        for (Long value : values) {

            content
                    .append(value)
                    .append(System.lineSeparator());
        }

        try {

            Files.writeString(
                    path,
                    content.toString(),
                    StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE,
                    StandardOpenOption.TRUNCATE_EXISTING,
                    StandardOpenOption.WRITE
            );

        } catch (IOException exception) {

            throw new IllegalStateException(
                    "Unable to write CSV: " + path,
                    exception
            );
        }
    }

    private static void createParent(
            Path path
    ) {

        Path parent =
                path.getParent();

        if (parent == null) {
            return;
        }

        try {

            Files.createDirectories(parent);

        } catch (IOException exception) {

            throw new IllegalStateException(
                    "Unable to create directory: "
                            + parent,
                    exception
            );
        }
    }
}