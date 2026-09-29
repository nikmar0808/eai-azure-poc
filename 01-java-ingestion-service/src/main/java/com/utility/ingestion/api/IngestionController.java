package com.utility.ingestion.api;

import com.utility.ingestion.api.dto.BulkIngestionRequest;
import com.utility.ingestion.api.dto.TransformationResponse;
import com.utility.ingestion.service.IngestionService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/ingest")
public class IngestionController {

    private final IngestionService ingestionService;

    public IngestionController(IngestionService ingestionService) {
        this.ingestionService = ingestionService;
    }

    @PostMapping("/bulk")
    public ResponseEntity<TransformationResponse> ingest(
            @Valid @RequestBody BulkIngestionRequest request) {
        return ResponseEntity.ok(ingestionService.ingest(request));
    }
}
