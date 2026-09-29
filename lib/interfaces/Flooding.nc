#include "../../includes/packet.h"

interface Flooding{
   // send to neighbor nodes
   command uint16_t send(uint16_t dest, uint8_t protocol, uint8_t* payload, uint8_t len);

   // received a flood addressed to this node
   event void receive(pack* msg);
}
