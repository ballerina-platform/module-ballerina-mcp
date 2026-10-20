// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/mcp;
import ballerina/time;
import ballerina/uuid;

configurable int cartPort = ?;
listener mcp:StreamableHttpListener cartListener = check new (cartPort, host = "127.0.0.1");

const int CART_TTL_SECONDS = 1800;
const int MAX_CARTS = 1000;

type CartItem record {|
    string productName;
    decimal unitPrice;
    int itemCount;
|};

type CartEntry record {|
    int expiresAt;
    CartItem[] cartItems;
|};

isolated map<CartEntry> cartStore = {};

@mcp:StreamableHttpServiceConfig {info: {name: "Shopping with explicit cart handles", version: "1.0.0"}}
service mcp:StreamableHttpService /mcp on cartListener {
    @mcp:Tool {description: "Create a cart and return its handle. Pass this handle to every cart operation."}
    remote isolated function createCart() returns string|error {
        time:Utc currentTime = time:utcNow();
        int currentSeconds = currentTime[0];
        string cartId = uuid:createRandomUuid();
        lock {
            foreach string storedId in cartStore.keys() {
                CartEntry storedCart = <CartEntry>cartStore[storedId];
                if storedCart.expiresAt <= currentSeconds {
                    _ = cartStore.remove(storedId);
                }
            }
            if cartStore.length() >= MAX_CARTS {
                return error("Cart capacity reached; close an existing cart or try later");
            }
            cartStore[cartId] = {expiresAt: currentSeconds + CART_TTL_SECONDS, cartItems: []};
        }
        return cartId;
    }

    @mcp:Tool {description: "Add an item to an existing cart using the handle returned by createCart."}
    remote isolated function addItem(string cartId, string productName, decimal unitPrice, int itemCount) returns string|error {
        if unitPrice < 0.0d || itemCount <= 0 {
            return error("Price must be non-negative and quantity must be positive");
        }
        time:Utc currentTime = time:utcNow();
        int currentSeconds = currentTime[0];
        lock {
            CartEntry? cartEntry = cartStore[cartId];
            if cartEntry is () || cartEntry.expiresAt <= currentSeconds {
                return error("Cart not found or expired");
            }
            cartEntry.cartItems.push({productName, unitPrice, itemCount});
        }
        return "Item added";
    }

    @mcp:Tool {description: "Read the items in a cart using its explicit handle."}
    remote isolated function viewCart(string cartId) returns CartItem[]|error {
        time:Utc currentTime = time:utcNow();
        int currentSeconds = currentTime[0];
        lock {
            CartEntry? cartEntry = cartStore[cartId];
            if cartEntry is () || cartEntry.expiresAt <= currentSeconds {
                return error("Cart not found or expired");
            }
            return cartEntry.cartItems.cloneReadOnly();
        }
    }

    @mcp:Tool {description: "Delete a cart and release its application state."}
    remote isolated function closeCart(string cartId) returns boolean {
        lock {
            return cartStore.removeIfHasKey(cartId) is CartEntry;
        }
    }
}
