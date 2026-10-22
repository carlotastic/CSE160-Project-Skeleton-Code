#include "../../includes/packet.h"

// Delivery of a packet that arrived from a one-hop neighbor
interface LinkReceive{
   event void receive(pack* msg, uint16_t prevHop);
}
