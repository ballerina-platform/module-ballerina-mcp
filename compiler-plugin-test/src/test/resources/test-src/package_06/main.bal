// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/crypto;
import ballerina/lang.array;
import ballerina/log;
import ballerina/mcp;
import ballerina/time;

listener mcp:Listener mcpListener = check new (9092);
listener mcp:Listener mcpListener1 = check new (9091);

@mcp:ServiceConfig {
    info: {
        name: "MCP Shopping Cart Server",
        version: "1.0.0"
    },
    sessionMode: mcp:STATEFUL,
    httpConfig: {
        auth: [
            {
                jwtValidatorConfig: {
                    issuer: "wso2",
                    audience: "ballerina",
                    signatureConfig: {
                        certFile: "./resource/public.crt"
                    }
                }
            }
        ]
    }
}
service mcp:Service /mcp on mcpListener {

    @mcp:Tool {
        description: "Add an item to the shopping cart"
    }
    remote function addToCart(mcp:Session session, string productName, decimal price) returns string|error {
        log:printInfo(string `Adding ${productName} (${price}) to cart for session ${session.getSessionId()}`);

        // Get current cart or create new one
        CartItem[] currentCart = [];
        if session.hasKey("cart") {
            currentCart = check session.getWithType("cart");
        }

        // Add new item
        CartItem newItem = {
            productName: productName,
            price: price,
            addedAt: time:utcToString(time:utcNow())
        };
        currentCart.push(newItem);

        // Update session
        session.set("cart", currentCart);

        return string `Added ${productName} to cart. Total items: ${currentCart.length()}`;
    }

    @mcp:Tool {
        description: "View all items in the current shopping cart"
    }
    remote function viewCart(mcp:Session session) returns CartView|error {
        log:printInfo(string `Viewing cart for session ${session.getSessionId()}`);

        CartItem[] cart = [];
        if session.hasKey("cart") {
            cart = check session.getWithType("cart");
        }

        decimal total = 0.0;
        foreach CartItem item in cart {
            total += item.price;
        }

        return {
            sessionId: session.getSessionId(),
            items: cart,
            totalItems: cart.length(),
            cartTotal: total
        };
    }

    @mcp:Tool {
        description: "Clear all items from the shopping cart"
    }
    remote function clearCart(mcp:Session session) returns string|error {
        log:printInfo(string `Clearing cart for session ${session.getSessionId()}`);

        session.set("cart", <CartItem[]>[]);
        return "Cart cleared successfully";
    }
}

type CartItem record {|
    string productName;
    decimal price;
    string addedAt;
|};

type CartView record {|
    string sessionId;
    CartItem[] items;
    int totalItems;
    decimal cartTotal;
|};


@mcp:ServiceConfig {
    info: {
        name: "MCP Crypto Server",
        version: "1.0.0"
    },
    sessionMode: mcp:STATELESS
}
service mcp:AdvancedService /mcp on mcpListener1 {

    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {
            tools: [
                {
                    name: "hashText",
                    description: "Generate hash for text using various algorithms",
                    inputSchema: {
                        "type": "object",
                        "properties": {
                            "text": {
                                "type": "string",
                                "description": "Text to hash"
                            },
                            "algorithm": {
                                "type": "string",
                                "description": "Hash algorithm (md5, sha1, sha256, sha384, sha512)",
                                "enum": ["md5", "sha1", "sha256", "sha384", "sha512"],
                                "default": "sha256"
                            }
                        },
                        "required": ["text"]
                    }
                },
                {
                    name: "encodeBase64",
                    description: "Encode or decode text using Base64",
                    inputSchema: {
                        "type": "object",
                        "properties": {
                            "text": {
                                "type": "string",
                                "description": "Text to encode/decode"
                            },
                            "operation": {
                                "type": "string",
                                "description": "Operation type (encode or decode)",
                                "enum": ["encode", "decode"],
                                "default": "encode"
                            }
                        },
                        "required": ["text"]
                    }
                }
            ]
        };
    }

    remote isolated function onCallTool(mcp:CallToolParams params, mcp:Session? session) returns mcp:CallToolResult|mcp:ServerError {
        record {} arguments = params.arguments ?: {};
        match params.name {
            "hashText" => {
                return self.handleHashText(arguments);
            }
            "encodeBase64" => {
                return self.handleBase64(arguments);
            }
            _ => {
                return error mcp:ServerError(string `Unknown tool: ${params.name}`);
            }
        }
    }

    private isolated function handleHashText(record {} arguments) returns mcp:CallToolResult|mcp:ServerError {
        string|error text = (arguments["text"]).cloneWithType();
        if text is error {
            return error mcp:ServerError("Invalid 'text' parameter");
        }

        string algorithm = "sha256"; // default
        if arguments.hasKey("algorithm") {
            string|error alg = (arguments["algorithm"]).cloneWithType();
            if alg is error {
                return error mcp:ServerError("Invalid 'algorithm' parameter");
            }
            algorithm = alg;
        }

        string hashedValue = "";
        match algorithm {
            "md5" => {
                byte[] hashedBytes = crypto:hashMd5(text.toBytes());
                hashedValue = hashedBytes.toBase16();
            }
            "sha1" => {
                byte[] hashedBytes = crypto:hashSha1(text.toBytes());
                hashedValue = hashedBytes.toBase16();
            }
            "sha256" => {
                byte[] hashedBytes = crypto:hashSha256(text.toBytes());
                hashedValue = hashedBytes.toBase16();
            }
            "sha384" => {
                byte[] hashedBytes = crypto:hashSha384(text.toBytes());
                hashedValue = hashedBytes.toBase16();
            }
            "sha512" => {
                byte[] hashedBytes = crypto:hashSha512(text.toBytes());
                hashedValue = hashedBytes.toBase16();
            }
            _ => {
                return error mcp:ServerError("Unsupported hash algorithm: " + algorithm);
            }
        }

        log:printInfo(string `Hashed text using ${algorithm}: ${text} -> ${hashedValue}`);

        HashResult result = {
            value: hashedValue,
            algorithm: algorithm,
            originalText: text
        };

        return {
            content: [
                {
                    'type: "text",
                    text: result.toJsonString()
                }
            ]
        };
    }

    private isolated function handleBase64(record {} arguments) returns mcp:CallToolResult|mcp:ServerError {
        string|error text = (arguments["text"]).cloneWithType();
        if text is error {
            return error mcp:ServerError("Invalid 'text' parameter");
        }

        string operation = "encode"; // default
        if arguments.hasKey("operation") {
            string|error op = (arguments["operation"]).cloneWithType();
            if op is error {
                return error mcp:ServerError("Invalid 'operation' parameter");
            }
            operation = op;
        }

        string resultValue;
        if operation == "encode" {
            resultValue = text.toBytes().toBase64();
        } else if operation == "decode" {
            byte[]|error decodedBytes = array:fromBase64(text);
            if decodedBytes is error {
                return error mcp:ServerError("Invalid Base64 input for decoding");
            }
            string|error decodedString = string:fromBytes(decodedBytes);
            if decodedString is error {
                return error mcp:ServerError("Failed to convert decoded bytes to string");
            }
            resultValue = decodedString;
        } else {
            return error mcp:ServerError("Invalid operation. Use 'encode' or 'decode'");
        }

        log:printInfo(string `Base64 ${operation}: ${text} -> ${resultValue}`);

        Base64Result result = {
            result: resultValue,
            operation: operation,
            originalInput: text
        };

        return {
            content: [
                {
                    'type: "text",
                    text: result.toJsonString()
                }
            ]
        };
    }
}
