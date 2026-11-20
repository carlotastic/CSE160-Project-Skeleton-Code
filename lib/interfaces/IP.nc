#include "../../includes/packet.h"

// Multi-hop delivery using the routing table
interface IP{
   // send a new packet to any node in the network
   command error_t send(uint16_t dest, uint8_t protocol, uint8_t* payload, uint8_t len);

   // same as send, but the caller chooses the starting TTL (used for testing)
   command error_t sendTTL(uint16_t dest, uint8_t protocol, uint8_t ttl, uint8_t* payload, uint8_t len);

   // TEST ONLY: drop the next `count` forwarded TCP packets that match. count = 0 turns it off.
   command void setTestDrop(uint16_t src, uint8_t flags, uint16_t value, uint8_t count);

   // a routed packet addressed to this node arrived
   event void receive(pack* msg);
}