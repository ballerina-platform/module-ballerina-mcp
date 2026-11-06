import ballerina/mcp as old;
import ballerina/mcp.v2 as mcp;

type Booking record {|
    # The guest's name
    string name;
|};

function elicitForm(string message, typedesc<record {}> schema) returns string => message;

service mcp:StreamableHttpService /v2 on new mcp:StreamableHttpListener(9091) {
    # Books a table
    remote isolated function book(mcp:Context context) returns string|mcp:InputRequiredResult {
        Booking? booking = context.acceptedContent("booking");
        if booking is () {
            return {inputRequests: {"booking": mcp:elicitForm("V2 call", Booking)}};
        }
        return booking.name;
    }
}

service old:StreamableHttpService /root on new old:StreamableHttpListener(9090) {
    # Builds a form request
    remote function prepare() returns string {
        mcp:ElicitRequest request = mcp:elicitForm("Root call", Booking);
        return request.params.message + elicitForm("Local call", Booking);
    }
}
