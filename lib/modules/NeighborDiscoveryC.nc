#include <Timer.h>
#include "../../includes/packet.h"

configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    // The shared singleton link layer, the same instance flooding uses.
    // NeighborReceive delivers only packets addressed to everyone.
    components LinkLayerC;
    NeighborDiscoveryP.LinkLayer -> LinkLayerC.LinkLayer;
    NeighborDiscoveryP.LinkReceive -> LinkLayerC.NeighborReceive;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;

    components new HashmapC(uint16_t, 20) as NeighborMapC;
    NeighborDiscoveryP.NeighborMap -> NeighborMapC;
}
