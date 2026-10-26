#include <Timer.h>
#include <AM.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/dv.h"   // for USE_LQ_METRIC

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
        MAX_MISSED = 3, //drops a neighbor after this many rounds of no reply
        LQ_CONFIRM_ROUNDS = 3 // a new link cost must show up this many rounds in a row
    };

    uint16_t ndSeq = 0; // separate from flooding's seqCounter

    // link quality, indexed by neighbor id (ids are at most 255)
    uint16_t history[256];     // last 16 rounds, 1 bit each: 1 = got a reply that round
    bool gotReply[256];        // did we get a reply during the current round?
    uint8_t lqCost[256];       // current link cost (1..4), 0 = never measured
    uint8_t pendingCost[256];  // a new cost we've been seeing, not confirmed yet
    uint8_t pendingCount[256]; // how many rounds in a row we've seen pendingCost

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

    // how many bits are 1 (= how many of the last 16 rounds got a reply)
    uint8_t countBits(uint16_t x) {
        uint8_t c = 0;
        while(x) {
            c += x & 1;
            x >>= 1;
        }
        return c;
    }

    // replies out of 16 -> link cost (rounded ETX)
    uint8_t costFromHistory(uint16_t h) {
        uint8_t k = countBits(h);
        if(k >= 14) return 1;   // >= 87.5%
        if(k >= 12) return 2;   // >= 75%
        if(k >= 8)  return 3;   // >= 50%
        return 4;
    }

    // called once per round: close out the round that just ended for every neighbor
    void updateLinkQuality() {
        uint32_t keysCopy[20];
        uint16_t count;
        uint16_t i;
        uint16_t id;
        uint8_t newCost;

        count = call NeighborMap.size();
        memcpy(keysCopy, call NeighborMap.getKeys(), count * sizeof(uint32_t));

        for(i = 0; i < count; i++) {
            id = (uint16_t) keysCopy[i];
            if(id > 255) {
                continue;
            }

            // shift in this round's result: 1 if they replied, 0 if not
            history[id] = (history[id] << 1) | (gotReply[id] ? 1 : 0);
            gotReply[id] = FALSE;

            newCost = costFromHistory(history[id]);

            // hysteresis: only change after seeing the same new cost several rounds in a row
            if(newCost == lqCost[id]) {
                pendingCount[id] = 0;                  // back to normal, forget the pending value
            } else if(newCost == pendingCost[id]) {
                pendingCount[id]++;                    // same new value again
            } else {
                pendingCost[id] = newCost;             // a different new value, start counting
                pendingCount[id] = 1;
            }

            if(pendingCount[id] >= LQ_CONFIRM_ROUNDS) {
                dbg(NEIGHBOR_CHANNEL, "Link cost to %hu: %hhu -> %hhu (%hhu/16 replies)\n",
                    id, lqCost[id], newCost, countBits(history[id]));
                lqCost[id] = newCost;
                pendingCount[id] = 0;
                if(USE_LQ_METRIC) {
                    signal NeighborDiscovery.linkCostChanged(id, newCost);
                }
            }
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
                signal NeighborDiscovery.neighborLost((uint16_t) keysCopy[i]);
            } else {
                call NeighborMap.insert(keysCopy[i], missed); // insert on an existing key overwrites it
            }

        }
    }

    // radio is on, so start the rounds
    // random extra time (0-996 ms) so nodes don't all broadcast at once and collide
    event void LinkLayer.ready(){
        call neighborTimer.startPeriodic(10000 + call Random.rand16()%997);
    }

    event void neighborTimer.fired() {
        updateLinkQuality(); // record who replied last round
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
            // EVERY reply: mark this round as a success
            if(prevHop <= 255) {
                gotReply[prevHop] = TRUE;
            }

            if(call NeighborMap.contains(prevHop) == FALSE) {
                // ONLY a brand-new neighbor: start its history as "perfect"
                dbg(NEIGHBOR_CHANNEL, "New neighbor: %hu\n", prevHop);
                if(prevHop <= 255) {
                    history[prevHop] = 0xFFFF;   // 16 of 16
                    lqCost[prevHop] = 1;
                    pendingCount[prevHop] = 0;
                }
                call NeighborMap.insert(prevHop, 0);
                signal NeighborDiscovery.neighborAdded(prevHop);
            } else {
                call NeighborMap.insert(prevHop, 0); // reset missed count
            }
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

    command bool NeighborDiscovery.isNeighbor(uint16_t id) {
        return call NeighborMap.contains(id);
    }

    command uint8_t NeighborDiscovery.linkCost(uint16_t id) {
        if(!USE_LQ_METRIC || id > 255 || lqCost[id] == 0) {
            return 1; // hop-count mode, or not measured yet
        }
        return lqCost[id];
    }

    command uint16_t NeighborDiscovery.getNeighbors(uint16_t* buf, uint16_t max) {
        uint32_t* keys;
        uint16_t n;
        uint16_t i;

        keys = call NeighborMap.getKeys();
        n = call NeighborMap.size();
        if(n > max) {
            n = max; // never write past the caller's buffer
        }
        for(i = 0; i < n; i++) {
            buf[i] = (uint16_t) keys[i];
        }
        return n;
    }   

}