#include <Timer.h>
#include "../../includes/packet.h"

// Wiring for neighbor discovery
configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    // same shared LinkLayerC that flooding uses (only one radio).
    // NeighborReceive only gets packets with dest = AM_BROADCAST_ADDR.
    components LinkLayerC;
    NeighborDiscoveryP.LinkLayer -> LinkLayerC.LinkLayer;
    NeighborDiscoveryP.LinkReceive -> LinkLayerC.NeighborReceive;

    components new TimerMilliC() as neighborTimer; // "new" = our own private timer
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random; // not "new", RandomC is shared by everyone
    NeighborDiscoveryP.Random -> Random;

    components new HashmapC(uint16_t, 20) as NeighborMapC; // up to 20 neighbors, separate from flooding's SeenMap
    NeighborDiscoveryP.NeighborMap -> NeighborMapC;
}
