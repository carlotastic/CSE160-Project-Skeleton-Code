<style>body { font-size: 12px; line-height: 1.35; } h1 { font-size: 20px; margin: 0 0 6px; } h2 { font-size: 14px; margin: 8px 0 2px; border: none; } ul { margin: 2px 0; padding-left: 18px; } pre { margin: 4px 0; padding: 6px; } p { margin: 2px 0; }</style>

# Project 2 Design: Distance-Vector Routing

## Overview:
- We split routing into two modules. DistanceVector (DV) keeps the routing table up to date, and IP uses it to forward packets. IP never changes the table, it only asks DV "who is the next hop for this destination?"

## Architecture:
```
      Node.nc (ping / ping reply)
             │
            IP  ──────────►  DistanceVector  ◄──── NeighborDiscovery
             │                     │                      │
             └──────────── LinkLayer (one radio) ─────────┘
```
- In Project 1 the link layer sorted packets by checking if dest was the broadcast address. That doesn't work anymore because DV packets go to one neighbor, so they would have ended up in flooding. So each type of traffic got its own AM type: AM_PACK (6) = neighbor discovery + flooding, AM_DV (11) = advertisements, AM_IP (12) = routed packets like ping.
- Flooding is still there from Project 1, but ping doesn't use it anymore.

## Routing table:
- A plain array of 32 entries instead of the Hashmap. The Hashmap's get() gives back a copy, so every change would mean get, change, insert again. With an array we just change the field.
- Each entry has: dest, nextHop, cost, age, and state (empty / valid / withdrawn).
- Slot 0 is the node itself with cost 0 and never gets replaced. New neighbors get a route with cost 1.
- We only keep the best route for each destination. If a route breaks, we find a new one from the next advertisement (~6 s later).
- DV doesn't keep its own neighbor list. It asks neighbor discovery, which tells DV when a neighbor is added or lost.

## How routes get updated (Bellman-Ford):
When neighbor N says "I can reach D with cost c", our cost through N is c + 1 (16 or more = unreachable). Then:

- we never change the route to ourselves, and ignore nodes neighbor discovery hasn't confirmed
- if we don't have a route to D yet, we take it
- if N is already our next hop for D, we believe it even if the cost got worse, since our path goes through N
- if N is a different neighbor, we only switch if it's strictly better. On a tie we keep our route so it doesn't keep flipping.

## Timers:
- Neighbor discovery: every 10 s + random. A neighbor is dropped after 4 rounds with no reply (~40 s).
- Advertisements: every 5 s + random, so nodes don't all send at once. No triggered updates.
- Route timeout: not refreshed for 6 rounds (~30 s) → unreachable. Then we advertise it as 16