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

import ballerina/log;
import ballerina/mcp;
import ballerina/time;

listener mcp:Listener mcpListener = check new (9092);

@mcp:ServiceConfig {
    info: {
        name: "MCP Shopping Cart Server",
        version: "1.0.0"
    },
    sessionMode: mcp:STATEFUL
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