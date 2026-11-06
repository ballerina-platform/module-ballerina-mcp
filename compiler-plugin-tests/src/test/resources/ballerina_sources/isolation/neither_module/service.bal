import ballerina/http;

annotation record {| string description; |} Tool on function;

function elicitForm(string message, typedesc<record {}> schema) returns string => message;

type Booking record {|
    string name;
|};

service /api on new http:Listener(9092) {
    @Tool {description: "Not an MCP tool"}
    resource function get booking() returns string {
        return elicitForm("Local call", Booking);
    }
}
