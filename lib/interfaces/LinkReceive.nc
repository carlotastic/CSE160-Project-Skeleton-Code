#include "../../includes/packet.h"

/*
 * Delivery of a packet that arrived from a one-hop neighbor.
 *
 * LinkLayerC provides one instance of this per upper layer and decides which
 * instance a given packet belongs to, so each upper layer only ever sees the
 * traffic it owns. TinyOS allows just one AMReceiverC per AM id, so this
 * demultiplexing has to happen somewhere; doing it here keeps the upper
 * layers from having to recognize and skip each other's packets.
 */
interface LinkReceive{
   /*
    * @param msg      the packet. It points into the radio's receive buffer and
    *                 is valid for the duration of this event only, so copy
    *                 anything you intend to keep.
    * @param prevHop  the neighbor that transmitted it. This is not the same as
    *                 msg->src once a packet has been forwarded at least once.
    */
   event void receive(pack* msg, uint16_t prevHop);
}
