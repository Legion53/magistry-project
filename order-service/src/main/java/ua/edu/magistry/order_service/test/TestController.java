package ua.edu.magistry.order_service.test;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/test")
public class TestController {

    private static final long DELAY_MS = 1_000L;

    @GetMapping("/delay")
    public DelayResponse delay() throws InterruptedException {
        long start = System.nanoTime();

        Thread.sleep(DELAY_MS);

        long elapsedMs =
                (System.nanoTime() - start) / 1_000_000L;

        Thread currentThread = Thread.currentThread();

        return new DelayResponse(
                DELAY_MS,
                elapsedMs,
                currentThread.isVirtual(),
                currentThread.toString()
        );
    }
}