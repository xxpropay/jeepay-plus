package com.jeequan.jeepay.pay.config;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** OpenAPI documentation configuration for the payment gateway. */
@Configuration
public class SwaggerConfiguration {

    @Bean("knife4jDockerBean")
    public GroupedOpenApi paymentApi() {
        return GroupedOpenApi.builder()
                .group("支付网关")
                .pathsToMatch("/api/**")
                .build();
    }
}
