#include <Timer.h>
#include <AM.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

module NeighborDiscoveryP{
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;

}

implementation{
    command void NeighborDiscovery.start(){
        call neighborTimer.startPeriodic(500 + (uint16_t) call Random.rand16()%500);
    }

    event void neighborTimer.fired() {
        dbg(NEIGHBOR_CHANNEL, "Neighbor Discovery Started\n");
    }

    command void NeighborDiscovery.printNeighbors(){
        
    }
}