// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

type Address record {|
    string city;
|};

type Shipping record {|
    string name;
    Address address;
|};

type Note record {|
    json details;
|};

type Delivery record {|
    Address[] stops;
|};

type Contact record {|
    string? phone;
|};

isolated function elicitations() returns mcp:ElicitRequest[] => [
    mcp:elicitForm("Where to?", Shipping),
    mcp:elicitForm("Any notes?", Note),
    mcp:elicitForm("Which stops?", Delivery),
    mcp:elicitForm("How to reach you?", Contact)
];
