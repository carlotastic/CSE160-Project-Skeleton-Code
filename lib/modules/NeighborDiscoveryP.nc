#include <Timer.h>
#include <AM.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

module NeighborDiscoveryP{
    provides interface NeighborDiscovery;

    uses SimpleSend as Sender;
    uses interface Receive;
    uses interface Timer<TMilli> as beaconTimer;
    uses interface Hashmap<uint16_t> as NeighborMap;

}

implementation{

}