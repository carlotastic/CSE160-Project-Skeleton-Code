# Discussion questions:
### 1. Describe the pros and cons of using event-driven programming.
- The pros of event-driven programming are that code only runs when an event is triggered, so the node isn't wasting time or power waiting and can sleep in between. There are also no threads to manage.
- The cons are that logic gets split across multiple functions (ex: AMControl.start() returns immediately and the result comes later in startDone()). The state has to be stored in variables between events, a long-running handler blocks everything else since tasks can't be interrupted, and it's harder to debug because the order depends on when events fire.

### 2. Flooding includes a mechanism to prevent packets from circulating indefinitely, and the TTL field provides another mechanism. What is the benefit of having both? What would happen if we only had flooding checks? What would happen if we had only TTL checks?
- The duplicate cache Hashmap stores the highest seq seen from each src, so each node forwards a packet only once. TTL limits how many hops a packet can travel.
- If we only had the Hashmap, floods would normally still end, since each node forwards once. But if the cache fails (like it is full or a node breaks), nothing would stop a packet from circulating forever.
- If we only had TTL, packets would eventually die, but in a topology with cycles every node would forward every copy it receives. The number of packets would grow exponentially until TTL hit 0.
- Having both means the cache keeps flooding efficient normally, and TTL is a guaranteed backup in case the cache fails.

### 3. When using the flooding protocol, what would be the total number of packets sent/received by all the nodes in the best-case situation? Worse case situation? Explain the topology and the reasoning behind each case.
- Best case: a line or tree with few links and no cycles. Each node sends once, about N sends. Each send is only heard by 1–2 neighbors, so about 2(N−1) receives. The count grows linearly with the number of nodes.
- Worst case: fully connected and every node can hear every other node. Each node still sends once, N sends, but every send is heard by all N−1 other nodes, so N(N−1) receives, which grows with N².
- Our duplicate cache Hashmap is what keeps it bounded. Without it (TTL only), a topology with cycles could produce on the order of (neighbors per node)^TTL packets.
- Example from our tests: in cycle (9 nodes), each flood had 7 forwards. Every node except the source and destination forwarded exactly once.

### 4. Using the information gathered from neighbor discovery, what would be a better way of accomplishing multi-hop communication?
- A better way would be routing. Each node shares its neighbor list with the rest of the network, so every node can build a map of the whole topology (link-state routing). Each node can then run a shortest-path algorithm like Dijkstra's to build a routing table of "to reach node X, send to neighbor Y."
- Packets are then unicast to the next hop instead of broadcast to everyone. Only nodes on the path send the packet, so there are far fewer packets and collisions, and it scales better.
- The downside is the extra traffic to share neighbor lists, and the tables have to be updated when neighbors change.

### 5. Describe a design decision you could have made differently given that you can change the provided skeleton code and the pros and cons compared to the decision you made.
- We mark neighbor discovery packets by setting dest = AM_BROADCAST_ADDR, and the link layer uses that to decide where each packet goes. If we could change the skeleton, we would give each service its own AM id (or add a packet type field to the header) instead.
- Pros: it's more reliable, since a flood addressed to the broadcast address would currently be mistaken for neighbor discovery. It would also make adding new protocols easier.
- Cons: it needs more wiring (a separate AMReceiverC and sender for each service) and changes to the provided packet and header files. Our approach worked without changing the packet format.
