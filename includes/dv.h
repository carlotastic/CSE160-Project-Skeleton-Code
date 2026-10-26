#ifndef DV_H
#define DV_H

#include "packet.h"
#define USE_LQ_METRIC 0

enum{
   DV_INFINITY = 16, // "unreachable". Finite costs are 0..15
   MAX_ROUTES  = 32, // most destinations our table can hold

   // how many (dest, cost) pairs fit in one packet:
   // 20-byte payload, minus 1 byte for the count, 2 bytes per pair = 9
   DV_MAX_ENTRIES = (PACKET_MAX_PAYLOAD_SIZE - 1) / 2,

   DV_PERIOD = 5000,// ms between periodic advertisements
   DV_JITTER = 1000, // + random 0..999 ms so nodes don't collide
   ROUTE_TIMEOUT_ROUNDS = 6, // not refreshed for 6 rounds (~30s) -> unreachable
   WITHDRAW_ROUNDS = 6 // keep advertising INF for 6 rounds, then delete
};

// what a slot in the routing table is currently doing
enum{
   ROUTE_EMPTY     = 0, // slot unused
   ROUTE_VALID     = 1, // usable for forwarding
   ROUTE_WITHDRAWN = 2  // unreachable, still advertised as INF for a while
};

// one row of the routing table (lives only in this node's memory)
typedef struct RouteEntry{
   uint8_t dest;
   uint8_t nextHop;
   uint8_t cost;
   uint8_t age;// rounds since last refresh (or since withdrawal began)
   uint8_t state; // ROUTE_EMPTY / ROUTE_VALID / ROUTE_WITHDRAWN
} RouteEntry;

// one (dest, cost) pair inside an advertisement (goes over the radio)
typedef nx_struct dvEntry{
   nx_uint8_t dest;
   nx_uint8_t cost;
} dvEntry;

// the advertisement, placed inside pack.payload
typedef nx_struct dvPayload{
   nx_uint8_t numEntries;
   dvEntry entries[DV_MAX_ENTRIES];
} dvPayload;

#endif