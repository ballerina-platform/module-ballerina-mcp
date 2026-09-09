import ballerina/mcp;
import ballerina/io;

configurable string interopUrl = ?;

public function main() returns error? {
    mcp:ProtocolMode[] protocolModes = ["legacy", "auto", "modern"];
    foreach mcp:ProtocolMode protocolMode in protocolModes {
        mcp:StreamableHttpClient peerClient = check new (interopUrl, protocolMode = protocolMode);
        check peerClient->initialize();
        mcp:CallToolResult addResult = check peerClient->callTool({name: "add", arguments: {"firstValue": 2, "secondValue": 3}});
        mcp:TextContent addText = check addResult.content[0].ensureType();
        if addText.text != "5" {
            return error("Unexpected addition result");
        }
        mcp:CallToolResult echoResult = check peerClient->callTool({name: "echo", arguments: {"region": "世界"}});
        mcp:TextContent echoText = check echoResult.content[0].ensureType();
        if echoText.text != "世界" {
            return error("Unexpected mirrored-header result");
        }
        check peerClient->close();
        io:println(protocolMode, " HTTP/SSE add and mirrored-header echo PASS");
    }
}
