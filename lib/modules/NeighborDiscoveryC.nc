#include "../../includes/packet.h"

configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;

    components new SimpleSendC(AM_PACK) as NDSender;
    NeighborDiscoveryP.Sender -> NDSender;

    components new HashmapC(uint16_t, 20) as NeighborMapC;
    NeighborDiscoveryP.NeighborMap -> NeighborMapC;
}