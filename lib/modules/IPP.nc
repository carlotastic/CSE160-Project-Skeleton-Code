#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/tcp.h"

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

    // ---------- TEST ONLY: drop hook (off unless a test sets a rule) ----------
    bool     dropEnabled = FALSE;
    uint16_t dropSrc;      // original sender to match (0 = any)
    uint8_t  dropFlags;    // exact TCP flags to match
    uint16_t dropValue;    // seq for DATA/SYN/FIN, ack number for a pure ACK
    uint8_t  dropLeft;     // how many more matching packets to drop

    // TRUE if this forwarded packet matches the test rule (and should be dropped)
    bool shouldDropForTest(pack* msg) {
        tcpSegment* seg;
        uint16_t value;

        if(!dropEnabled){
            return FALSE;
        }
        // check the protocol and length BEFORE reading it as a TCP header
        if(msg->protocol != PROTOCOL_TCP) {
            return FALSE;
        }
        seg = (tcpSegment*) msg->payload;
        if(seg->len > TCP_MAX_DATA){
            return FALSE;
        }

        if(dropSrc != 0 && msg->src != dropSrc) {
            return FALSE;
        }
        if(dropFlags == TCP_DROP_WINDOW_UPDATE) {
            // TEST ONLY: a pure ACK that reopens the window
            if(seg->flags != TCP_FLAG_ACK || seg->window == 0) {
                return FALSE;
            }
        } else if(seg->flags != dropFlags) {
            return FALSE;
        }
        // a pure ACK is identified by its ack number, everything else by its seq
        value = (seg->flags == TCP_FLAG_ACK) ? seg->ack : seg->seq;
        if(value != dropValue) {
            return FALSE;
        }

        dbg(TRANSPORT_CHANNEL, "TEST DROP at node %hu: discarding TCP from %hu to %hu flags=%hhu seq=%hu ack=%hu\n",
            TOS_NODE_ID, msg->src, msg->dest, (uint8_t) seg->flags,
            (uint16_t) seg->seq, (uint16_t) seg->ack);

        dropLeft--;
        if(dropLeft == 0){
            dropEnabled = FALSE;   // done: later matching packets go through normally
        }
        return TRUE;
    }

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

    command void IP.setTestDrop(uint16_t src, uint8_t flags, uint16_t value, uint8_t count){
        dropSrc     = src;
        dropFlags   = flags;
        dropValue   = value;
        dropLeft    = count;
        dropEnabled = (count > 0);
        dbg(TRANSPORT_CHANNEL, "TEST DROP RULE at node %hu: src=%hu flags=%hhu value=%hu count=%hhu\n",
            TOS_NODE_ID, src, flags, value, count);
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

        // TEST ONLY: drop a chosen transport segment (never happens unless a test sets a rule)
        if(shouldDropForTest(msg)){
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