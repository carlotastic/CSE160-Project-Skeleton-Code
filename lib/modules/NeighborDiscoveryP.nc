#include <Timer.h>
#include <AM.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

module NeighborDiscoveryP{
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;
    uses interface LinkLayer;
    uses interface LinkReceive;
    uses interface Hashmap<uint16_t> as NeighborMap; // key=neighbor id and value=missed rounds
}

implementation{
    enum{
        MAX_MISSED = 3 //drops a neighbor after this many rounds of no reply
    };

    uint16_t ndSeq = 0;

    // Setting the header dest to AM_BROADCAST_ADDR marks the packet as neighbor
    // discovery, which is how the link layer knows to route it here instead of
    // into flooding. TTL is 1 because these must never travel past one hop.
    // linkDest is who actually receives it over the radio.
    void sendNDPacket(uint8_t protocol, uint16_t linkDest) {
        pack ndPackage;

        ndPackage.src = TOS_NODE_ID;
        ndPackage.dest = AM_BROADCAST_ADDR;
        ndPackage.TTL = 1;
        ndPackage.protocol = protocol;
        ndPackage.seq = ++ndSeq;
        memset(ndPackage.payload, 0, PACKET_MAX_PAYLOAD_SIZE);

        if(linkDest == AM_BROADCAST_ADDR){
            call LinkLayer.broadcast(&ndPackage);
        } else{
            call LinkLayer.unicast(&ndPackage, linkDest);
        }
    }

    // called every round to increment neighbor's missed count and drop dead ones
    void ageNeighbors() {
        uint32_t keysCopy[20];
        uint16_t count;
        uint16_t i;
        uint16_t missed;

        // getKeys hands back the live array, and remove() shuffles it, so take
        // a copy before iterating.
        count = call NeighborMap.size();
        memcpy(keysCopy, call NeighborMap.getKeys(), count * sizeof(uint32_t));

        for(i=0; i<count; i++) {
            missed = call NeighborMap.get(keysCopy[i]) + 1;
            if (missed > MAX_MISSED) {
                call NeighborMap.remove(keysCopy[i]);
                dbg(NEIGHBOR_CHANNEL, "Neighbor %hu dropped (no reply in %d rounds)\n", (uint16_t) keysCopy[i], MAX_MISSED);
            } else{
                call NeighborMap.insert(keysCopy[i], missed);
            }

        }
    }

    // The radio is up, so start the roll call. Nothing above this module has to
    // remember to start the service or wait for the radio itself.
    event void LinkLayer.ready(){
        call neighborTimer.startPeriodic(3000 + call Random.rand16()%997);
    }

    event void neighborTimer.fired() {
        ageNeighbors();
        sendNDPacket(PROTOCOL_PING, AM_BROADCAST_ADDR);
    }

    // prevHop rather than msg->src: a neighbor is by definition whoever
    // transmitted to us. For these packets the two are always equal, since
    // TTL 1 means they are never forwarded, but prevHop is what we actually
    // mean and it cannot be spoofed by a stale src field.
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
