#include "../../includes/packet.h"

/*
 * One-hop transmission over the radio.
 *
 * This hides ActiveMessage from everything above it: the layers that use this
 * interface never see message_t, buffer swapping, or AM ids. It is also the
 * only place that knows the radio has to be turned on.
 *
 * Commands fan in, since several upper layers share one radio. ready() fans
 * out to all of them.
 */
interface LinkLayer{
   // Transmit to every node within radio range. One packet on the air, which
   // is the whole point of using a broadcast medium.
   command error_t broadcast(pack* msg);

   // Transmit to a single node within radio range. This is a one-hop address
   // and is unrelated to msg->dest, which is end to end.
   command error_t unicast(pack* msg, uint16_t neighbor);

   // The radio is up. Nothing may be sent before this fires.
   event void ready();
}
