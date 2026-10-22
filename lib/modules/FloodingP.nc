#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

// Flooding: sends a packet to every node by having each node rebroadcast it.
module FloodingP{
    provides interface Flooding;

    uses interface LinkLayer; // for sending
    uses interface LinkReceive; // for receiving (only flooding packets arrive here)

    // duplicate cache: key = source node id, value = highest seq seen from it
    uses interface Hashmap<uint16_t> as SeenMap;
}

implementation{
    // this node's sequence number, increments every time we start a new flood
    uint16_t seqCounter = 0;

    // TRUE if we've already handled this (src, seq), otherwise records it and returns FALSE.
    // a packet is uniquely identified by its original sender + seq number.
    bool alreadySeen(uint16_t src, uint16_t seq){
        if(call SeenMap.contains(src) && call SeenMap.get(src) >= seq){
            return TRUE;
        }
        call SeenMap.insert(src, seq);
        return FALSE;
    }

    // called by Node to start a new flood. Node only gives dest/protocol/payload, 
    // flooding fills in the rest of the header (src, seq, TTL).
    // returns the seq number used, or 0 if the send failed.
    command uint16_t Flooding.send(uint16_t dest, uint8_t protocol, uint8_t* payload, uint8_t len){
        pack outgoing;

        // don't copy more than the payload field can hold
        if(len > PACKET_MAX_PAYLOAD_SIZE){
            len = PACKET_MAX_PAYLOAD_SIZE;
        }

        outgoing.src = TOS_NODE_ID; // original sender, never changes while forwarding
        outgoing.dest = dest; // final destination
        outgoing.seq = ++seqCounter;
        outgoing.TTL = MAX_TTL; // max hops before the packet is dropped
        outgoing.protocol = protocol; // PING or PINGREPLY, flooding never looks at it
        memset(outgoing.payload, 0, PACKET_MAX_PAYLOAD_SIZE);
        memcpy(outgoing.payload, payload, len);

        // Record sequence number before transmitting, so packet doesn't end up duplicated
        // (neighbors will rebroadcast it back to us)
        call SeenMap.insert(TOS_NODE_ID, outgoing.seq);

        if(call LinkLayer.broadcast(&outgoing) != SUCCESS){
            return 0;
        }
        return outgoing.seq;
    }

    // a flooding packet arrived from a neighbor
    // check order: duplicate -> is it for me -> TTL -> forward
    event void LinkReceive.receive(pack* msg, uint16_t prevHop){
        pack forward;

        dbg(FLOODING_CHANNEL, "Received from %hu (src %hu, dest %hu, seq %hu, TTL: %hhu)\n",
            prevHop, msg->src, msg->dest, msg->seq, msg->TTL);

        // already handled this one, drop it (stops infinite loops)
        if(alreadySeen(msg->src, msg->seq)){
            dbg(FLOODING_CHANNEL, "Duplicate (src %hu, seq %hu), dropping\n", msg->src, msg->seq);
            return;
        }

        // it's for us, hand it up to Node (checked before TTL so a packet on its last hop still gets delivered)
        if(msg->dest == TOS_NODE_ID){
            signal Flooding.receive(msg); // signal = fire an event up to Node
            return;
        }

        // if TTL <= 1, it has expired
        if(msg->TTL <= 1){
            dbg(FLOODING_CHANNEL, "TTL expired (src %hu, seq %hu), dropping\n", msg->src, msg->seq);
            return;
        }

        // not for us and still has hops left, so pass it on.
        // copy it first since msg points into the radio's buffer
        forward = *msg;
        forward.TTL--;
        call LinkLayer.broadcast(&forward);
        dbg(FLOODING_CHANNEL, "Forwarded (src %hu, seq %hu, TTL now %hhu)\n",
            forward.src, forward.seq, forward.TTL);
    }

    // Flooding is ready as soon as someone sends.
    // still has to be here because nesC requires handlers for every event we use.
    event void LinkLayer.ready(){}
}
