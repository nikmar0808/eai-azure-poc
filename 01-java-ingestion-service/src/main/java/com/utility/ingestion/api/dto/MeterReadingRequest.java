package com.utility.ingestion.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.time.OffsetDateTime;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record MeterReadingRequest(
        @JsonProperty("timestamp")
        @NotNull(message = "Timestamp cannot be null")
        OffsetDateTime timestamp,

        @JsonProperty("kwh_value")
        @NotNull(message = "KWH value cannot be null")
        @Positive(message = "KWH value must be greater than zero")
        Double kwhValue,

        @JsonProperty("voltage")
        Double voltage
) {
}
