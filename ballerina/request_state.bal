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

import ballerina/crypto;
import ballerina/lang.array;
import ballerina/time;
import ballerina/uuid;

const REQUEST_STATE_VERSION = "v1";

# The signed form of a handler's request state.
type RequestStateEnvelope record {|
    # The plain text the handler returned
    string state;
    # The tool the state was issued for
    string tool;
    # SHA-256 digest of the call's arguments in canonical form
    string argumentsDigest;
    # The issuer, client and subject of the caller's auth context, or nil when there was none
    string? caller;
    # When the state stops being valid, in seconds since the epoch
    decimal expiresAt;
|};

# Signs request state when a handler returns it and verifies it on the continuation.
isolated readonly class RequestStateSigner {
    private final byte[][] & readonly keys;
    private final decimal ttl;

    # Creates a signer. Without keys, it signs with a random key of its own.
    #
    # + config - The service's request state configuration
    # + return - An error if the configuration is invalid
    isolated function init(RequestStateConfig config) returns Error? {
        if config.keys.some(key => key.toBytes().length() < 32) {
            return error DispatcherError("Request state keys must be at least 32 bytes");
        }
        if config.ttl <= 0d {
            return error DispatcherError("Request state ttl must be positive");
        }
        self.ttl = config.ttl;
        // UUIDs come from a cryptographically secure source; hashing two yields a full-length key.
        self.keys = config.keys.length() > 0 ? from string key in config.keys select key.toBytes().cloneReadOnly()
            : [crypto:hashSha256((uuid:createType4AsString() + uuid:createType4AsString()).toBytes()).cloneReadOnly()];
    }

    # Signs a handler's state, binding it to the call, the caller and an expiry.
    #
    # + state - The plain text the handler returned
    # + callParams - The call the handler answered
    # + authContext - The caller of that call
    # + return - The signed request state, or an error if signing fails
    isolated function sign(string state, CallToolParams callParams, AuthContext? authContext) returns string|error {
        RequestStateEnvelope envelope = {
            state,
            tool: callParams.name,
            argumentsDigest: argumentsDigest(callParams),
            caller: callerOf(authContext),
            expiresAt: epochSeconds() + self.ttl
        };
        string payload = envelope.toJsonString().toBytes().toBase64();
        byte[] mac = check crypto:hmacSha256(payload.toBytes(), self.keys[0]);
        return string `${REQUEST_STATE_VERSION}.${payload}.${mac.toBase64()}`;
    }

    # Verifies signed request state against the call it arrived on.
    #
    # + signedState - The request state the client sent
    # + callParams - The call it arrived on
    # + authContext - The caller of that call
    # + return - The plain text, or an error naming why the state was rejected
    isolated function verify(string signedState, CallToolParams callParams, AuthContext? authContext)
            returns string|error {
        string[] parts = re `\.`.split(signedState);
        if parts.length() != 3 || parts[0] != REQUEST_STATE_VERSION {
            return error("Malformed request state");
        }
        byte[] mac = check array:fromBase64(parts[2]);
        boolean signedByKnownKey = false;
        foreach byte[] key in self.keys {
            if constantTimeEquals(mac, check crypto:hmacSha256(parts[1].toBytes(), key)) {
                signedByKnownKey = true;
            }
        }
        if !signedByKnownKey {
            return error("Request state signature does not match");
        }
        RequestStateEnvelope envelope = check (check string:fromBytes(check array:fromBase64(parts[1])))
            .fromJsonStringWithType();
        if envelope.expiresAt < epochSeconds() {
            return error("Request state has expired");
        }
        if envelope.tool != callParams.name {
            return error("Request state was issued for another tool");
        }
        if envelope.argumentsDigest != argumentsDigest(callParams) {
            return error("Request state was issued for other arguments");
        }
        if envelope.caller != callerOf(authContext) {
            return error("Request state was issued to another caller");
        }
        return envelope.state;
    }
}

// The caller as HTTP session ownership sees it, but bound even when the access token names no client or subject.
isolated function callerOf(AuthContext? authContext) returns string? {
    if authContext is AuthContext {
        return [authContext.issuer, authContext.clientId, authContext.subject].toJsonString();
    }
    return;
}

isolated function epochSeconds() returns decimal {
    time:Utc now = time:utcNow();
    return <decimal>now[0] + now[1];
}

isolated function argumentsDigest(CallToolParams callParams) returns string =>
    crypto:hashSha256(canonicalJson((callParams.arguments ?: {}).toJson()).toBytes()).toBase64();

// Serializes JSON with object members sorted by key, so the same value always yields the same text.
isolated function canonicalJson(json value) returns string {
    if value is map<json> {
        string[] members = from string key in value.keys().sort()
            select key.toJsonString() + ":" + canonicalJson(value[key]);
        return "{" + string:'join(",", ...members) + "}";
    }
    if value is json[] {
        return "[" + string:'join(",", ...value.map(canonicalJson)) + "]";
    }
    return value.toJsonString();
}

isolated function constantTimeEquals(byte[] left, byte[] right) returns boolean {
    if left.length() != right.length() {
        return false;
    }
    int difference = 0;
    foreach int index in 0 ..< left.length() {
        difference |= left[index] ^ right[index];
    }
    return difference == 0;
}
