#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

// IP: forwards packets hop by hop using DV's routing table.
// Never floods. No route = drop.
module IPP{
    provides interface IP;

    uses interface LinkLayer; // to send one hop
    uses interface LinkReceive; // IP packets from a neighbor
    uses interface DistanceVector; // to look up the next hop
}

implementation{
    uint16_t ipSeq = 0; // this node's IP sequence numbers, separate from flooding's

    // look up the next hop for p->dest and send one hop.
    // used both for packets we start and packets we pass along.
    error_t routePacket(pack* p){
        uint16_t nextHop;
        uint8_t cost;

        if(call DistanceVector.getRoute(p->dest, &nextHop, &cost) == FALSE){
            dbg(ROUTING_CHANNEL, "No route to %hu, dropping (src %hu, seq %hu)\n",
                p->dest, p->src, p->seq);
            return FAIL;
        }

        if(call LinkLayer.sendIP(p, nextHop) != SUCCESS){
            dbg(ROUTING_CHANNEL, "Send queue full, dropping (src %hu, dest %hu, seq %hu)\n",
                p->src, p->dest, p->seq);
            return FAIL;
        }

        dbg(ROUTING_CHANNEL, "Routing Packet - src: %hu, dest: %hu, seq: %hu, next hop: %hu, cost: %hhu\n",
            p->src, p->dest, p->seq, nextHop, cost);
        return SUCCESS;
    }

    // build a brand-new packet from this node and route it
    error_t startPacket(uint16_t dest, uint8_t protocol, uint8_t ttl, uint8_t* payload, uint8_t len){
        pack p;

        if(len > PACKET_MAX_PAYLOAD_SIZE){
            dbg(ROUTING_CHANNEL, "Payload too long (%hhu bytes), not sending\n", len);
            return FAIL;   // refuse instead of silently cutting it off
        }
        if(ttl == 0){
            dbg(ROUTING_CHANNEL, "TTL must be at least 1, not sending\n");
            return FAIL;
        }

        memset(&p, 0, sizeof(pack));
        p.src = TOS_NODE_ID;    // original sender, never changes on the way
        p.dest = dest;          // final destination, never changes on the way
        p.seq = ++ipSeq;
        p.TTL = ttl;            // source sends it unchanged; each forwarder subtracts 1
        p.protocol = protocol;
        memcpy(p.payload, payload, len);

        return routePacket(&p);
    }

    command error_t IP.send(uint16_t dest, uint8_t protocol, uint8_t* payload, uint8_t len){
        return startPacket(dest, protocol, MAX_TTL, payload, len);
    }

    command error_t IP.sendTTL(uint16_t dest, uint8_t protocol, uint8_t ttl, uint8_t* payload, uint8_t len){
        return startPacket(dest, protocol, ttl, payload, len);
    }

    // an IP packet arrived from a neighbor
    event void LinkReceive.receive(pack* msg, uint16_t prevHop){
        pack fwd;

        // it's for us: deliver it up to Node
        if(msg->dest == TOS_NODE_ID){
            if(msg->TTL > 0){
                signal IP.receive(msg);
            }
            return;
        }

        // not for us: forward only if it has hops left
        if(msg->TTL <= 1){
            dbg(ROUTING_CHANNEL, "TTL expired, dropping (src %hu, dest %hu, seq %hu)\n",
                msg->src, msg->dest, msg->seq);
            return;
        }

        // copy first: msg points into the radio's buffer
        fwd = *msg;
        fwd.TTL--;
        routePacket(&fwd);
    }

    // IP has nothing to start when the radio comes up
    event void LinkLayer.ready(){}
}