// Which nodes are within one radio hop of this one
interface NeighborDiscovery{
   command uint16_t numNeighbors();
   command void printNeighbors();

   // is this node currently a live neighbor?
   command bool isNeighbor(uint16_t id);

   // copies up to `max` neighbor IDs into buf, returns how many were copied
   command uint16_t getNeighbors(uint16_t* buf, uint16_t max);

   // ND tells everyone wired to it when the neighbor list changes
   event void neighborAdded(uint16_t id);
   event void neighborLost(uint16_t id);

   // current cost of the link to this neighbor (always 1 in hop-count mode)
   command uint8_t linkCost(uint16_t id);

   // the measured cost of a link changed (only signaled when USE_LQ_METRIC is 1)
   event void linkCostChanged(uint16_t id, uint8_t cost);
}