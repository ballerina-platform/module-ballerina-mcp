// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

type Labels map<string>;

isolated function elicitWith(typedesc<record {}> formType) returns mcp:ElicitRequest =>
    mcp:elicitForm("Fill in the form", formType);

isolated function elicitLabels() returns mcp:ElicitRequest => mcp:elicitForm("Add labels", schema = Labels);

isolated function elicitWithEither(mcp:FormSchema|typedesc<record {}> schema) returns mcp:ElicitRequest =>
    mcp:elicitForm("Fill in the form", schema);

// A form schema value is not a type, so it needs no compile-time schema.
isolated function elicitWithSchema(mcp:FormSchema schema) returns mcp:ElicitRequest =>
    mcp:elicitForm("Fill in the form", schema);
