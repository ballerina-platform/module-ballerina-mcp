// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

enum City {
    NEW_YORK = "New York, NY",
    LOS_ANGELES = "Los Angeles: CA"
}

type Signal "ring\u{7}"|"page\u{C}"|"back\u{8}";

type Alert record {|
    City city;
    Signal signal;
|};

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9345) {
    # Finds a city.
    # + city - The city, as "Name, ST" or {Name: ST}
    # + signal - A control signal
    remote isolated function find(City city, Signal signal) returns Alert => {city, signal};
}
