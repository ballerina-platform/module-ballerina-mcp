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

import ballerina/http;
import ballerina/jwt;
import ballerina/mcp;
import ballerina/time;
import ballerina/uuid;

configurable int port = 9093;
# Secret of the demo's HS256 access tokens, shared with the client that issues them.
configurable string tokenSecret = ?;

const TOKEN_ISSUER = "https://login.example.com";
const PENDING_TTL_SECONDS = 600;
const MAX_PENDING_CONNECTIONS = 1000;

final string origin = string `http://localhost:${port}`;
final string mcpUrl = origin + "/mcp";

// One HTTP listener serves both the MCP endpoint and the connect page.
listener http:Listener httpListener = new (port);
listener mcp:StreamableHttpListener mcpListener = check new (httpListener);

type PendingConnection record {|
    # The user the connect link was issued to
    string subject;
    # When the link stops working, in seconds since the epoch
    int expiresAt;
|};

// Connect links waiting to be opened, keyed by an opaque id so the URL names no user.
isolated map<PendingConnection> pendingConnections = {};
// Users whose calendar is connected. A real service would store the third-party tokens here.
isolated map<true> connectedUsers = {};

@mcp:StreamableHttpConfig {
    info: {name: "Calendar", version: "1.0.0"},
    httpConfig: {
        auth: {
            'resource: mcpUrl,
            authorizationServers: [
                {issuer: TOKEN_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: tokenSecret}}}}
            ]
        }
    }
}
service mcp:StreamableHttpService /mcp on mcpListener {
    @mcp:Tool {description: "List today's events in the user's calendar"}
    remote isolated function listEvents(mcp:AuthContext auth, mcp:Context context)
            returns string[]|mcp:InputRequiredResult|error {
        string? subject = auth.subject;
        if subject is () {
            return error("The access token names no user");
        }
        if isConnected(subject) {
            return ["09:30 Standup", "14:00 Design review"];
        }
        mcp:ElicitResult? answer = context.elicitResult("connect");
        if answer is mcp:ElicitResult && answer.action != "accept" {
            return error("The calendar is not connected");
        }
        // Accepting only means the user agreed to open the link. Until the connect page records the
        // connection, ask again with the same link, which the request state carries between rounds.
        string connectionId = check issueConnectLink(context.requestState(), subject);
        return {
            inputRequests: {
                "connect": mcp:elicitUrl("Connect your calendar to list its events",
                        string `${origin}/connect?id=${connectionId}`)
            },
            requestState: connectionId
        };
    }
}

final http:ListenerJwtAuthHandler userAuthenticator = new ({
    issuer: TOKEN_ISSUER,
    audience: mcpUrl,
    signatureConfig: {secret: tokenSecret}
});

service /connect on httpListener {
    // Opening the page as the right user stands in for the third-party consent step. The demo
    // signs the user in with a bearer token; a real page would use the authorization server's login.
    resource isolated function get .(string id, @http:Header string? authorization)
            returns http:Ok|http:Unauthorized|http:Forbidden|http:NotFound {
        if authorization is () {
            return <http:Unauthorized>{};
        }
        jwt:Payload|http:Unauthorized user = userAuthenticator.authenticate(authorization);
        if user !is jwt:Payload {
            return <http:Unauthorized>{};
        }
        string? subject = user.sub;
        int now = time:utcNow()[0];
        lock {
            PendingConnection? pending = pendingConnections[id];
            if pending is () || pending.expiresAt <= now {
                return <http:NotFound>{body: "This connect link has expired. Ask the assistant again."};
            }
            // Phishing defence: only the user the link was issued to may complete it.
            if subject != pending.subject {
                return <http:Forbidden>{body: "This connect link was issued to another user."};
            }
        }
        // Connect first: a round running between the two locks would otherwise issue a needless new link.
        lock {
            connectedUsers[<string>subject] = true;
        }
        lock {
            _ = pendingConnections.remove(id);
        }
        return <http:Ok>{body: "Calendar connected. Return to your assistant."};
    }
}

isolated function isConnected(string subject) returns boolean {
    lock {
        return connectedUsers.hasKey(subject);
    }
}

// Extends the previous round's link, or issues a new one when there is none or it has expired.
isolated function issueConnectLink(string? connectionId, string subject) returns string|error {
    int now = time:utcNow()[0];
    lock {
        foreach [string, PendingConnection] [id, pending] in pendingConnections.entries() {
            if pending.expiresAt <= now {
                _ = pendingConnections.remove(id);
            }
        }
        // The request state is bound to the caller, so its connection id belongs to this subject.
        boolean renewing = connectionId is string && pendingConnections.hasKey(connectionId);
        if !renewing && pendingConnections.length() >= MAX_PENDING_CONNECTIONS {
            return error("Too many pending connections; try again later");
        }
        string id = renewing ? <string>connectionId : uuid:createRandomUuid();
        pendingConnections[id] = {subject, expiresAt: now + PENDING_TTL_SECONDS};
        return id;
    }
}
