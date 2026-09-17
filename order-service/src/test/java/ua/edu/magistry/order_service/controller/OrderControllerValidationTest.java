package ua.edu.magistry.order_service.controller;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.FilterType;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import ua.edu.magistry.order_service.context.TraceContextFilter;
import ua.edu.magistry.order_service.service.OrderService;

import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(
        controllers = OrderController.class,
        excludeFilters = {
                @ComponentScan.Filter(
                        type = FilterType.ASSIGNABLE_TYPE,
                        classes = TraceContextFilter.class
                )
        }
)
class OrderControllerValidationTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private OrderService orderService;

    @Test
    void returnsBadRequestWhenQuantityIsZero() throws Exception {

        mockMvc.perform(
                        post("/orders")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("""
                                        {
                                            "productId": 1,
                                            "quantity": 0
                                        }
                                        """)
                )
                .andExpect(status().isBadRequest());

        verifyNoInteractions(orderService);
    }
}
