#include "../../includes/packet.h"

/*
 * Network-wide delivery by controlled rebroadcast.
 *
 * Callers hand over a destination and a payload; this module owns the source
 * address, the sequence number, the TTL and the duplicate cache. Nothing above
 * this interface needs to know a packet was flooded rather than routed, which
 * is what makes it reusable as the transport for a later routing project.
 */
interface Flooding{
   /*
    * Originate a flood towards dest.
    *
    * @param protocol what the payload means to the application layer; this
    *                 module never inspects it.
    * @param len      bytes of payload to copy, clamped to
    *                 PACKET_MAX_PAYLOAD_SIZE.
    * @return the sequence number assigned to the packet, which together with
    *         this node's address identifies it uniquely across the network, or
    *         0 if it could not be handed to the link layer. Sequence numbers
    *         start at 1, so 0 is never a valid one.
    */
   command uint16_t send(uint16_t dest, uint8_t protocol, uint8_t* payload, uint8_t len);

   /*
    * A flood addressed to this node arrived. msg points into the radio's
    * receive buffer and is valid for the duration of this event only, so copy
    * anything you intend to keep.
    */
   event void receive(pack* msg);
}
