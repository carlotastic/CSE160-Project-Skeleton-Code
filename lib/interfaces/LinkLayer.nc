#include "../../includes/packet.h"

// One-hop transmission over the radio
interface LinkLayer{
   // Transmit to every node within radio range
   command error_t broadcast(pack* msg);

   // Transmit to a single node within radio range. This is a one-hop address
   command error_t unicast(pack* msg, uint16_t neighbor);

   // The radio is up and nothing may be sent before this fires
   event void ready();
}
