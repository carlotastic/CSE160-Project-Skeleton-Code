// Which nodes are within one radio hop of this one
interface NeighborDiscovery{
   command uint16_t numNeighbors();
   command void printNeighbors();
}
