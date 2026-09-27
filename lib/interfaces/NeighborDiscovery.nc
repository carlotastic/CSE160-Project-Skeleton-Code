/*
 * Which nodes are within one radio hop of this one.
 *
 * The module starts itself as soon as the link layer reports the radio is up,
 * and maintains the list from there, so the application only ever reads from
 * it. There is deliberately no start() and no packet handler here: nothing
 * above this interface should have to recognize neighbor discovery traffic or
 * remember to kick the service off.
 */
interface NeighborDiscovery{
   command uint16_t numNeighbors();
   command void printNeighbors();
}
