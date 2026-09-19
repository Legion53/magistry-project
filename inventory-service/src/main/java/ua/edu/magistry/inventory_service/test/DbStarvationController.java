package ua.edu.magistry.inventory_service.test;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/test")
public class DbStarvationController {

    private static final long DB_DELAY_MS = 100L;

    private final DbStarvationService dbStarvationService;

    public DbStarvationController(
            DbStarvationService dbStarvationService
    ) {
        this.dbStarvationService = dbStarvationService;
    }

    @GetMapping("/db-starvation")
    public DbStarvationResponse dbStarvation() {

        long start = System.nanoTime();

        dbStarvationService.execute();

        long elapsedMs =
                (System.nanoTime() - start) / 1_000_000L;

        Thread currentThread = Thread.currentThread();

        return new DbStarvationResponse(
                DB_DELAY_MS,
                elapsedMs,
                currentThread.isVirtual(),
                currentThread.toString()
        );
    }
}