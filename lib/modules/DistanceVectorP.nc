#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/dv.h"
#include <Timer.h>

// Distance-vector routing: keeps the routing table up to date.
// IP asks this module for the next hop. It never forwards data itself.
module DistanceVectorP{
    provides interface DistanceVector;

    uses interface Boot;
    uses interface LinkReceive; // DV advertisements from neighbors
    uses interface NeighborDiscovery; // who is one hop away

    uses interface LinkLayer;               // to send DV packets
    uses interface Timer<TMilli> as dvTimer; // periodic rounds
    uses interface Random;                  // jitter
}

implementation{
    // the routing table: fixed size, no dynamic memory
    RouteEntry table[MAX_ROUTES];
    uint16_t dvSeq = 0; // just for debugging, DV doesn't rely on it

    // slot number of dest's route, or -1 if we don't have one
    int16_t findRoute(uint8_t dest){
        uint8_t i;
        for(i = 0; i < MAX_ROUTES; i++){
            if(table[i].state != ROUTE_EMPTY && table[i].dest == dest){
                return i;
            }
        }
        return -1;
    }

    // first unused slot, or -1 if the table is full
    int16_t findFreeSlot(){
        uint8_t i;
        for(i = 0; i < MAX_ROUTES; i++){
            if(table[i].state == ROUTE_EMPTY){
                return i;
            }
        }
        return -1;
    }

    // write a usable route into slot idx and reset its age
    void setRoute(int16_t idx, uint8_t dest, uint8_t nextHop, uint8_t cost){
        table[idx].dest = dest;
        table[idx].nextHop = nextHop;
        table[idx].cost = cost;
        table[idx].age = 0;
        table[idx].state = ROUTE_VALID;
        dbg(ROUTING_CHANNEL, "Route set: dest %hhu via %hhu cost %hhu\n", dest, nextHop, cost);
    }

    // mark a route unreachable. It stays in the table (advertised as INF)
    // for a while so neighbors hear about the loss.
    void withdrawRoute(int16_t idx){
        if(table[idx].state == ROUTE_WITHDRAWN){
            return;// already withdrawn: do NOT restart the withdrawal clock
        }
        table[idx].cost = DV_INFINITY;
        table[idx].state = ROUTE_WITHDRAWN;
        table[idx].age = 0;
        dbg(ROUTING_CHANNEL, "Route withdrawn: dest %hhu now unreachable\n", table[idx].dest);
    }

    // ---------- Bellman-Ford: one (dest, cost) entry from neighbor ----------

    void processEntry(uint8_t neighbor, uint8_t dest, uint8_t advCost){
        uint8_t newCost;
        int16_t idx;
        uint8_t lc;

        // never replace our own self-route
        if(dest == TOS_NODE_ID){
            return;
        }

        // cost through this neighbor = their cost + link cost, capped at INF.
        // in hop-count mode linkCost is always 1, so this is the same as before.
        // compared BEFORE adding so it can never overflow
        lc = call NeighborDiscovery.linkCost(neighbor);
        if(advCost >= DV_INFINITY - lc){
            newCost = DV_INFINITY;
        } else{
            newCost = advCost + lc;
        }

        idx = findRoute(dest);

        // case A: we've never heard of dest
        if(idx == -1){
            if(newCost >= DV_INFINITY){
                return;   // "unreachable" about something we didn't know: nothing to learn
            }
            idx = findFreeSlot();
            if(idx == -1){
                dbg(ROUTING_CHANNEL, "Table full, cannot add dest %hhu\n", dest);
                return;
            }
            setRoute(idx, dest, neighbor, newCost);
            return;
        }

        // case B: news from our CURRENT next hop: believe it, better OR worse
        if(table[idx].state == ROUTE_VALID && table[idx].nextHop == neighbor){
            if(newCost >= DV_INFINITY){
                withdrawRoute(idx);                       // next hop lost it
            } else if(newCost != table[idx].cost){
                setRoute(idx, dest, neighbor, newCost);   // cost went up or down
            } else{
                table[idx].age = 0;                       // same news: just refresh
            }
            return;
        }

        // case C: news from a DIFFERENT neighbor (or our route is withdrawn)
        if(newCost >= DV_INFINITY){
            return;   // their "unreachable" doesn't affect our route
        }
        if(table[idx].state != ROUTE_VALID || newCost < table[idx].cost){
            setRoute(idx, dest, neighbor, newCost);      // first usable or strictly better
        }
        // equal or worse from someone else: ignore (keeps current next hop = equal-cost rule)
    }



    void ageRoutes(){
        uint8_t i;

        for(i = 0; i < MAX_ROUTES; i++){
            if(table[i].state == ROUTE_EMPTY || table[i].dest == TOS_NODE_ID){
                continue;   // skip empty slots and the self-route
            }

            if(table[i].state == ROUTE_VALID){
                // direct neighbor routes are kept alive by ND, not by adverts
                if(table[i].nextHop == table[i].dest
                   && call NeighborDiscovery.isNeighbor(table[i].dest)){
                    table[i].age = 0;
                    continue;
                }
                table[i].age++;
                if(table[i].age >= ROUTE_TIMEOUT_ROUNDS){
                dbg(ROUTING_CHANNEL, "Route to %hhu expired (not refreshed)\n", table[i].dest);
                withdrawRoute(i);
                }
            } else if(table[i].state == ROUTE_WITHDRAWN){
                table[i].age++;
                if(table[i].age >= WITHDRAW_ROUNDS){
                dbg(ROUTING_CHANNEL, "Route to %hhu reclaimed\n", table[i].dest);
                table[i].state = ROUTE_EMPTY;   // free the slot
                }
            }
        }
    }


    // fill in the header and hand one DV packet to the link layer
    void sendDVPacket(pack* p, uint16_t nbr, uint8_t count){
        dvPayload* adv;

        adv = (dvPayload*) p->payload;
        adv->numEntries = count;

        p->src = TOS_NODE_ID;
        p->dest = nbr;
        p->seq = ++dvSeq;
        p->TTL = 1;                 // one hop only, never forwarded
        p->protocol = PROTOCOL_DV;

        dbg(DV_ADV_CHANNEL, "Sent DV packet to %hu with %hhu entries\n", nbr, count);
        
        if(call LinkLayer.sendDV(p, nbr) != SUCCESS){
            // queue full: skip it, the next periodic round sends again
            dbg(ROUTING_CHANNEL, "DV send to %hu failed (queue full)\n", nbr);
        }
    }

    // build THIS neighbor's own copy of our table and send it
    void sendVectorTo(uint16_t nbr){
        pack p;
        dvPayload* adv;
        uint8_t i;
        uint8_t count = 0;
        uint8_t cost;

        memset(&p, 0, sizeof(pack));
        adv = (dvPayload*) p.payload;

        for(i = 0; i < MAX_ROUTES; i++){
            if(table[i].state == ROUTE_EMPTY){
                continue;
            }

            if(table[i].dest == TOS_NODE_ID){
                cost = 0;                          // self-route always 0
            } else if(table[i].state == ROUTE_WITHDRAWN){
                cost = DV_INFINITY;                // withdrawal: tell everyone
            } else if(table[i].nextHop == nbr){
                cost = DV_INFINITY;                // POISON REVERSE: "don't route this through me"
            } else{
                cost = table[i].cost;              // normal case
            }

            adv->entries[count].dest = table[i].dest;
            adv->entries[count].cost = cost;
            dbg(DV_ADV_CHANNEL, "Adv to %hu: dest %hhu cost %hhu\n", nbr, table[i].dest, cost);
            count++;

            // packet full: send it and start a new one
            if(count == DV_MAX_ENTRIES){
                sendDVPacket(&p, nbr, count);
                memset(&p, 0, sizeof(pack));
                count = 0;
            }
        }

        if(count > 0){
            sendDVPacket(&p, nbr, count);   // leftover entries
        }
    }

    // one advertisement round: a separate vector for every neighbor
    void advertiseAll(){
        uint16_t nbrs[MAX_ROUTES];
        uint16_t numNbrs;
        uint16_t j;

        numNbrs = call NeighborDiscovery.getNeighbors(nbrs, MAX_ROUTES);
        for(j = 0; j < numNbrs; j++){
            sendVectorTo(nbrs[j]);
        }
    }

    event void Boot.booted(){
        uint8_t i;
        for(i = 0; i < MAX_ROUTES; i++){
            table[i].state = ROUTE_EMPTY;
        }
        // the only route we know at boot: ourselves, cost 0
        table[0].dest = TOS_NODE_ID;
        table[0].nextHop = TOS_NODE_ID;
        table[0].cost = 0;
        table[0].age = 0;
        table[0].state = ROUTE_VALID;
    }

    // radio is on: start periodic rounds with a random per-node period
    event void LinkLayer.ready(){
        call dvTimer.startPeriodic(DV_PERIOD + call Random.rand16() % DV_JITTER);
    }

    // one round: age first, then advertise
    event void dvTimer.fired(){
        ageRoutes();
        advertiseAll();
    }

    // ND confirmed a new neighbor: direct route at the link's cost
    event void NeighborDiscovery.neighborAdded(uint16_t id){
        int16_t idx;
        uint8_t lc;

        lc = call NeighborDiscovery.linkCost(id);
        idx = findRoute(id);
        if(idx == -1){
            idx = findFreeSlot();
            if(idx == -1){
                dbg(ROUTING_CHANNEL, "Table full, cannot add neighbor %hu\n", id);
                return;
            }
            setRoute(idx, id, id, lc);
        } else if(table[idx].state != ROUTE_VALID || table[idx].cost > lc){
            setRoute(idx, id, id, lc);   // direct link is better than what we had
        }
    }

    // ND says a neighbor is gone: every route through it is now unusable
    event void NeighborDiscovery.neighborLost(uint16_t id){
        uint8_t i;
        for(i = 0; i < MAX_ROUTES; i++){
            if(table[i].state == ROUTE_VALID && table[i].nextHop == id
                && table[i].dest != TOS_NODE_ID){
                withdrawRoute(i);
            }
        }
    }

    // ND measured a new cost for the link to neighbor id
    event void NeighborDiscovery.linkCostChanged(uint16_t id, uint8_t cost){
        int16_t idx;

        idx = findRoute(id);
        if(idx == -1){
            return;
        }
        // update the direct route if we use it, or switch to it if it's now better.
        // routes to OTHER destinations through id get fixed by id's next advertisement (case B).
        if(table[idx].nextHop == id || table[idx].state != ROUTE_VALID || cost < table[idx].cost){
            setRoute(idx, id, id, cost);
        }
    }

    // a DV advertisement arrived from a one-hop neighbor
    event void LinkReceive.receive(pack* msg, uint16_t prevHop){
        dvPayload* adv;
        uint8_t n;
        uint8_t i;

        if(msg->protocol != PROTOCOL_DV){
            return;
        }
        // only trust nodes ND has confirmed as live neighbors
        if(call NeighborDiscovery.isNeighbor(prevHop) == FALSE){
            dbg(ROUTING_CHANNEL, "Ignoring DV from non-neighbor %hu\n", prevHop);
            return;
        }

        adv = (dvPayload*) msg->payload;
        n = adv->numEntries;

        // validate the count BEFORE reading entries
        if(n > DV_MAX_ENTRIES){
            dbg(ROUTING_CHANNEL, "Bad DV packet from %hu (%hhu entries), dropping\n", prevHop, n);
            return;
        }

        for(i = 0; i < n; i++){
            processEntry((uint8_t) prevHop, adv->entries[i].dest, adv->entries[i].cost);
        }
    }


    command bool DistanceVector.getRoute(uint16_t dest, uint16_t* nextHop, uint8_t* cost){
        int16_t idx;

        if(dest > 255){
            return FALSE;
        }
        idx = findRoute((uint8_t) dest);
        if(idx == -1 || table[idx].state != ROUTE_VALID){
            return FALSE;
        }
        *nextHop = table[idx].nextHop;
        *cost = table[idx].cost;
        return TRUE;
    }

    command void DistanceVector.printTable(){
        uint8_t i;

        dbg(ROUTING_CHANNEL, "Routing table for node %hu:\n", TOS_NODE_ID);
        dbg(ROUTING_CHANNEL, "Dest\tNextHop\tCost\tState\n");
        for(i = 0; i < MAX_ROUTES; i++){
            if(table[i].state == ROUTE_VALID){
                dbg(ROUTING_CHANNEL, "%hhu\t%hhu\t%hhu\tVALID\n",
                    table[i].dest, table[i].nextHop, table[i].cost);
            } else if(table[i].state == ROUTE_WITHDRAWN){
                dbg(ROUTING_CHANNEL, "%hhu\t-\tINF\tWITHDRAWN\n", table[i].dest);
            }
        }
    }
}