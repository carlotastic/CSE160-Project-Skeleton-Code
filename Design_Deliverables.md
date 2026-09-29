# Write-up design decisions:

## Overview:
- Each node runs flooding for network-wide delivery and neighbor discovery to track its one-hop neighbors. Both share a single link layer, and the application (Node.nc) only uses them through interfaces.

## Architecture:
```
      Node.nc (application: ping / ping reply)
             │                         │
         Flooding              NeighborDiscovery
             │                         │
         FloodingP            NeighborDiscoveryP
             │                         │
             └────────────┬────────────┘
                          │
       LinkLayerP (radio, send queue, sorting)
```

Adding a link layer under both services:
- TinyOS allows one AM receiver per AM id, so something has to receive every packet and pass it to the right service

Node.nc only calls Flooding.send() and handles Flooding.receive
- Node does not know how packets are delivered, so it will make it easier when we need to swap flooding with routing

Initially we had everything in Node.nc and it worked but the mixed application with the networking logic made it harder to follow and debug


## Flooding:
Hashmaps for duplicate cache (key = src, value = highest seq):
- the src and seq are used to uniquely identify a packet.
- storing only the highest seq per source uses one entry per node instead of having a growing list of every packet
- this works because the seq numbers only go up

Record seq before sending:
- the neighbors rebroadcast your packet back to you, so recording it first stops us from flooding it a second time

TTL = 15:
- we decrement TTL after every forward
- when TTL <= 1, it means it ran out of hops and is dropped

Check order:
- first we check if it is a duplicate
- then we check the destination to make sure it is for me
- lastly check TTL so packets arriving on their last hop are still delivered

Always broadcast:
- The destination stops forwarding once it has the packet
- no topology knowledge is needed, which matches the requirement

Self ping:
- avoids flooding a packet nobody else needs

Sequence numbers:
- seq increases only when a node creates a new packet
- forwarding nodes keep the original seq so the packet can still be identified
- a PINGREPLY is a new packet, so it gets its own seq



## Neighbor Discovery:
Reused the pack type:
- marked dest = AM_BROADCAST_ADDR so that the link layer knows it's neighbor discovery

PING/PINGREPLY:
- PING is broadcast with TTL = 1 since it only needs one-hop
- PINGREPLY is unicast since only the node that asked needs the answer

Missed round counter:
- set to 3 rounds to avoid dropping a neighbor over one lost packet
- this is used to handle nodes dying or links breaking

Separate seq counter:
- so neighbor discovery traffic never ends up in flooding's duplicate cache

Timer:
- we set it to 10s + random(0,996ms) to stop nodes from broadcasting all at once and limit radio traffic


## Testing and Problems:
**Tests**:
   - multihop: 9-hop ping and reply on a line
   - cycle: duplicate cache stops loops in a mesh
   - ttl: packet dies after 15 hops
   - unreachable: flood ends cleanly when the path is cut
   - selfping: handled locally, nothing sent
   - concurrent: two floods at once don't interfere

**Problems**:
- initially we had a 3s neighbor discovery timer, but multihop failed 2 runs in a row. The ping reply was lost at a different hop each time
   ex: 10->9 and then 7->6

**Cause**:
Every node that received a packet handled it correctly, so the logic was fine. The packets were just lost in the air. 19 nodes doing neighbor discovery every 3 seconds put enough traffic on the radio to collide with the flood. On a line there is only one path and flooding has no ACKS, so one lost packet ends the delivery

**Fix**:
- we decided to slow the timer to 10 seconds and all six tests passed. 

**Tradeoff**:
However, the dead neighbors now take about 30s to drop instead of 10s
