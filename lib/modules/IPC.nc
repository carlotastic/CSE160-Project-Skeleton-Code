#include "../../includes/packet.h"

// Wiring for the IP (forwarding) module
configuration IPC{
    provides interface IP;
}

implementation{
    components IPP;
    IP = IPP.IP;

    // IP packets travel on their own AM type (from Step 3)
    components LinkLayerC;
    IPP.LinkLayer -> LinkLayerC.LinkLayer;
    IPP.LinkReceive -> LinkLayerC.IPReceive;

    // ask DV for the next hop
    components DistanceVectorC;
    IPP.DistanceVector -> DistanceVectorC;
}