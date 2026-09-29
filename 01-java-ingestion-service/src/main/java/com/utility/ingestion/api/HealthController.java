package com.utility.ingestion.api;

import com.utility.ingestion.configuration.IntegrationProperties;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.time.Duration;

@RestController
public class HealthController {

    private final RestClient downstreamClient;

    public HealthController(RestClient.Builder restClientBuilder, IntegrationProperties properties) {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout((int) Duration.ofSeconds(2).toMillis());
        requestFactory.setReadTimeout((int) Duration.ofSeconds(2).toMillis());

        this.downstreamClient = restClientBuilder
                .baseUrl(properties.baseUrl())
                .requestFactory(requestFactory)
                .build();
    }

    public record HealthStatus(String status, String pythonValidator) {}

    @GetMapping("/health")
    public ResponseEntity<HealthStatus> health() {
        String downstreamStatus;
        try {
            downstreamClient.get().uri("/").retrieve().toBodilessEntity();
            downstreamStatus = "UP";
        } catch (RestClientException e) {
            downstreamStatus = "DOWN";
        }

        HealthStatus body = new HealthStatus("UP", downstreamStatus);
        return "DOWN".equals(downstreamStatus)
                ? ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(body)
                : ResponseEntity.ok(body);
    }
}