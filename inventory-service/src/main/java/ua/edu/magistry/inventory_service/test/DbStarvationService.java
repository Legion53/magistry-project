package ua.edu.magistry.inventory_service.test;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.resilience.annotation.ConcurrencyLimit;
import org.springframework.stereotype.Service;

@Service
public class DbStarvationService {

    private final JdbcTemplate jdbcTemplate;

    public DbStarvationService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @ConcurrencyLimit(
            limitString = "${experiment.concurrency-limit:-1}"
    )
    public void execute() {
        jdbcTemplate.execute("SELECT pg_sleep(0.1)");
    }
}