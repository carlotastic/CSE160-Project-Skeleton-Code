#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

module FloodingP{
    provides interface Flooding;

    uses interface LinkLayer;
    uses interface LinkReceive;

    // The node table: one entry per source node, holding the highest sequence
    // number seen from it.
    uses interface Hashmap<uint16_t> as SeenMap;
}

implementation{
    uint16_t seqCounter = 0;

    /*
     * The duplicate cache. Returns TRUE if this packet has already been
     * handled, otherwise records it and returns FALSE.
     *
     * Recording on the first sighting is what stops a packet circling a cyclic
     * topology forever: the second copy to arrive finds its own sequence number
     * already at or below what is stored and is dropped.
     */
    bool alreadySeen(uint16_t src, uint16_t seq){
        if(call SeenMap.contains(src) && call SeenMap.get(src) >= seq){
            return TRUE;
        }
        call SeenMap.insert(src, seq);
        return FALSE;
    }

    command uint16_t Flooding.send(uint16_t dest, uint8_t protocol, uint8_t* payload, uint8_t len){
        // A local, so a reply originated from inside Flooding.receive cannot
        // clobber the packet of the call it is nested inside. SimpleSend.send
        // takes the pack by value, so there is nothing to keep alive after.
        pack outgoing;

        if(len > PACKET_MAX_PAYLOAD_SIZE){
            len = PACKET_MAX_PAYLOAD_SIZE;
        }

        outgoing.src = TOS_NODE_ID;
        outgoing.dest = dest;
        outgoing.seq = ++seqCounter;
        outgoing.TTL = MAX_TTL;
        outgoing.protocol = protocol;
        memset(outgoing.payload, 0, PACKET_MAX_PAYLOAD_SIZE);
        memcpy(outgoing.payload, payload, len);

        // Record our own sequence number before transmitting. A neighbor will
        // rebroadcast this packet and we will hear it; without this entry we
        // would treat our own packet as new and flood it a second time.
        call SeenMap.insert(TOS_NODE_ID, outgoing.seq);

        if(call LinkLayer.broadcast(&outgoing) != SUCCESS){
            return 0;
        }
        return outgoing.seq;
    }

    /*
     * A packet arrived from a neighbor. The order of these checks matters: the
     * duplicate cache runs before anything else so a packet is acted on exactly
     * once, and the "is it mine" test runs before the TTL test so a packet that
     * arrives on its last hop is still delivered.
     */
    event void LinkReceive.receive(pack* msg, uint16_t prevHop){
        pack forward;

        dbg(FLOODING_CHANNEL, "Received from %hu (src %hu, dest %hu, seq %hu, TTL: %hhu)\n",
            prevHop, msg->src, msg->dest, msg->seq, msg->TTL);

        if(alreadySeen(msg->src, msg->seq)){
            dbg(FLOODING_CHANNEL, "Duplicate (src %hu, seq %hu), dropping\n", msg->src, msg->seq);
            return;
        }

        if(msg->dest == TOS_NODE_ID){
            signal Flooding.receive(msg);
            return;
        }

        // TTL counts hops left. At 1 this node would be the last hop, and it is
        // not the destination, so the packet dies here rather than being
        // forwarded to a node that could not pass it on either.
        if(msg->TTL <= 1){
            dbg(FLOODING_CHANNEL, "TTL expired (src %hu, seq %hu), dropping\n", msg->src, msg->seq);
            return;
        }

        forward = *msg;
        forward.TTL--;
        call LinkLayer.broadcast(&forward);
        dbg(FLOODING_CHANNEL, "Forwarded (src %hu, seq %hu, TTL now %hhu)\n",
            forward.src, forward.seq, forward.TTL);
    }

    // Flooding has no start-up work; it is ready as soon as someone sends.
    event void LinkLayer.ready(){}
}
