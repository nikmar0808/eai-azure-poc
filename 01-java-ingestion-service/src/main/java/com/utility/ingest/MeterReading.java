package com.utility.ingest;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;

public record MeterReading(
    @JsonProperty("timestamp")
    @NotNull(message = "Timestamp cannot be null") 
    String timestamp,
    
    @JsonProperty("kwh_value")
    @NotNull(message = "KWH value cannot be null")
    @PositiveOrZero(message = "KWH value must be greater than zero") 
    Double kwhValue,

    @JsonProperty("voltage")
    Double voltage // Optional field supported by Python schema
) {}
