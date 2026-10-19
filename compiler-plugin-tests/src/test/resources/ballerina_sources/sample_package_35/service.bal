// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

type Labels map<string>;

isolated function elicitWith(typedesc<record {}> formType) returns mcp:InputRequest =>
    mcp:elicitForm("Fill in the form", formType);

isolated function elicitLabels() returns mcp:InputRequest => mcp:elicitForm("Add labels", schema = Labels);
