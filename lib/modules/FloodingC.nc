#include "../../includes/packet.h"

// Wiring for flooding
configuration FloodingC{
    provides interface Flooding;
}

implementation{
    components FloodingP;
    Flooding = FloodingP.Flooding;

    // same shared LinkLayerC that neighbor discovery uses (only one radio).
    // FloodReceive only gets packets with a real dest, not AM_BROADCAST_ADDR.
    components LinkLayerC;
    FloodingP.LinkLayer -> LinkLayerC.LinkLayer;
    FloodingP.LinkReceive -> LinkLayerC.FloodReceive;

    // duplicate cache, holds up to 20 source nodes.
    // "new" = flooding gets its own private hashmap
    components new HashmapC(uint16_t, 20) as SeenMapC;
    FloodingP.SeenMap -> SeenMapC;
}
