#include <Timer.h>
#include <AM.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

// Neighbor discovery: finds which nodes are one hop away.
// every round: broadcast a PING, anyone who hears it sends back a PINGREPLY
module NeighborDiscoveryP{
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer; // fires once per round
    uses interface Random; // randomizes the round length
    uses interface LinkLayer; // for sending
    uses interface LinkReceive; // for receiving (only neighbor discovery packets arrive here)
    uses interface Hashmap<uint16_t> as NeighborMap; // key=neighbor id and value=missed rounds
}

implementation{
    enum{
        MAX_MISSED = 3 //drops a neighbor after this many rounds of no reply
    };

    uint16_t ndSeq = 0; // separate from flooding's seqCounter

    // builds and sends a neighbor discovery packet.
    // linkDest = who actually receives it over the radio (everyone for PING, one node for PINGREPLY)
    void sendNDPacket(uint8_t protocol, uint16_t linkDest) {
        pack ndPackage;

        ndPackage.src = TOS_NODE_ID;
        // dest = AM_BROADCAST_ADDR is how the link layer knows to send it to us instead of flooding.
        ndPackage.dest = AM_BROADCAST_ADDR;
        ndPackage.TTL = 1; // TTL = 1 so it never goes past one hop.
        ndPackage.protocol = protocol;
        ndPackage.seq = ++ndSeq;
        memset(ndPackage.payload, 0, PACKET_MAX_PAYLOAD_SIZE); // no payload needed

        if(linkDest == AM_BROADCAST_ADDR){
            call LinkLayer.broadcast(&ndPackage);
        } else{
            call LinkLayer.unicast(&ndPackage, linkDest);
        }
    }

    // called every round to increment neighbor's missed count and drop dead ones.
    // a reply resets the count to 0, so only neighbors that stopped replying get dropped.
    void ageNeighbors() {
        uint32_t keysCopy[20];
        uint16_t count;
        uint16_t i;
        uint16_t missed;

        // copy the keys first, since remove() changes the hashmap's key array while we loop
        count = call NeighborMap.size();
        memcpy(keysCopy, call NeighborMap.getKeys(), count * sizeof(uint32_t));

        for(i=0; i<count; i++) {
            missed = call NeighborMap.get(keysCopy[i]) + 1;
            if (missed > MAX_MISSED) {
                call NeighborMap.remove(keysCopy[i]);
                dbg(NEIGHBOR_CHANNEL, "Neighbor %hu dropped (no reply in %d rounds)\n", (uint16_t) keysCopy[i], MAX_MISSED);
            } else{
                call NeighborMap.insert(keysCopy[i], missed); // insert on an existing key overwrites it
            }

        }
    }

    // radio is on, so start the rounds
    // random extra time (0-996 ms) so nodes don't all broadcast at once and collide
    event void LinkLayer.ready(){
        call neighborTimer.startPeriodic(10000 + call Random.rand16()%997);
    }

    // one round: age everyone first, then ask who's still there
    event void neighborTimer.fired() {
        ageNeighbors();
        sendNDPacket(PROTOCOL_PING, AM_BROADCAST_ADDR);
    }

    // a neighbor discovery packet arrived.
    // uses prevHop (who transmitted to us) instead of msg->src, since that's what a neighbor is.
    event void LinkReceive.receive(pack* msg, uint16_t prevHop) {
        if(msg->protocol == PROTOCOL_PING) {
            // someone is asking who is there, so answer only to them
            sendNDPacket(PROTOCOL_PINGREPLY, prevHop);
        } else if(msg->protocol == PROTOCOL_PINGREPLY) {
            if(call NeighborMap.contains(prevHop) == FALSE) {
                dbg(NEIGHBOR_CHANNEL, "New neighbor: %hu\n", prevHop);
            }
            call NeighborMap.insert(prevHop, 0); // reset missed count
        }
    }

    command uint16_t NeighborDiscovery.numNeighbors() {
        return call NeighborMap.size();
    }

    // called by Node when the printNeighbors command is run
    command void NeighborDiscovery.printNeighbors() {
        uint32_t* keys;
        uint16_t i;

        keys = call NeighborMap.getKeys();
        dbg(NEIGHBOR_CHANNEL, "Neighbor list (%hu):\n", call NeighborMap.size());
        for(i=0; i<call NeighborMap.size(); i++) {
            dbg(NEIGHBOR_CHANNEL, "   %hu\n", (uint16_t) keys[i]);
        }
    }
}
