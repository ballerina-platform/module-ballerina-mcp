# Additional initialization options.
#
# + enforceStrictCapabilities - Whether to restrict emitted requests to only those that the remote 
#                               side has indicated that they can handle, through their advertised 
#                               capabilities. Note that this DOES NOT affect checking of _local_ 
#                               side capabilities, as it is considered a logic error to mis-specify 
#                               those. Currently this defaults to false, for backwards compatibility 
#                               with SDK versions that did not advertise capabilities correctly. In 
#                               future, this will default to true.
public type ProtocolOptions record {|
    boolean enforceStrictCapabilities?;
|};
