// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

enum Area {
    INDOOR = "indoor",
    PATIO = "patio"
}

type Diet "vegan"|"gluten-free";

# A table booking.
type Booking record {|
    # The guest's name
    string name;
    # How many people are coming
    int guests;
    # Whether to sit outside
    boolean outdoor?;
    # The seating area
    Area area;
    # Dietary needs
    Diet[] diets;
    # The deposit to hold
    decimal deposit;
|};

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9333) {
    remote isolated function book(mcp:Context context) returns string|mcp:InputRequiredResult {
        Booking? booking = context.acceptedContent("booking");
        if booking is () {
            return {inputRequests: {"booking": mcp:elicitForm("Book a table", Booking)}};
        }
        return booking.name;
    }
}
