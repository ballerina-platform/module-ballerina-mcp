// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

# Adapts the stdio transport's server-message queue to a Ballerina stream.
isolated class StdioServerMessageStream {
    private final StdioClientTransport transport;
    private boolean streamClosed = false;

    isolated function init(StdioClientTransport transport) {
        self.transport = transport;
    }

    public isolated function next() returns record {|JsonRpcMessage value;|}|StreamError? {
        string|StdioTransportError? messageLine = self.transport.readServerMessage();
        if messageLine is StdioTransportError {
            self.closeStream();
            return error StdioMessageStreamError(messageLine.message(), messageLine);
        }
        if messageLine is () {
            self.closeStream();
            return;
        }
        JsonRpcMessage|error message = messageLine.fromJsonStringWithType();
        if message is error {
            return error TypeConversionError(string `Failed to convert server message: ${message.message()}`);
        }
        if message is JsonRpcResponse|JsonRpcError {
            return error StdioMessageStreamError("Received an uncorrelated response on the server message stream.");
        }
        return {value: message.cloneReadOnly()};
    }

    # Releases the transport's single server-message stream reservation.
    #
    # + return - Nil after the stream reservation is released.
    public isolated function close() returns StreamError? {
        self.closeStream();
    }

    private isolated function closeStream() {
        lock {
            if self.streamClosed {
                return;
            }
            self.streamClosed = true;
        }
        self.transport.releaseServerMessageStream();
    }
}
