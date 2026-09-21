package com.utility.ingest;

import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/ingest")
public class IngestionController {

    private final IntegrationClient integrationClient;

    public IngestionController(IntegrationClient integrationClient) {
        this.integrationClient = integrationClient;
    }

    @PostMapping("/bulk")
    public ResponseEntity<String> acceptBulkPayload(@Valid @RequestBody SmartMeterPayload payload) {
        // Handoff directly to our resilient transformation pipeline client
        String conversionResult = integrationClient.forwardPayloadToTransformer(payload);
        return ResponseEntity.ok(conversionResult);
    }
}
