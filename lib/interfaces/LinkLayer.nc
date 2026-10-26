#include "../../includes/packet.h"

// One-hop transmission over the radio
interface LinkLayer{
   // Transmit to every node within radio range
   command error_t broadcast(pack* msg);

   // Transmit to a single node within radio range. This is a one-hop address
   command error_t unicast(pack* msg, uint16_t neighbor);

   // one-hop send of a DV advertisement to one neighbor
   command error_t sendDV(pack* msg, uint16_t neighbor);

   // one-hop send of a routed IP packet to the next hop
   command error_t sendIP(pack* msg, uint16_t nextHop);

   // The radio is up and nothing may be sent before this fires
   event void ready();
}
