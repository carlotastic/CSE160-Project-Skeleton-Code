#include "../../includes/packet.h"

interface NeighborDiscovery{
    command void start();
    command void handle(pack* msg);
    command uint16_t numNeighbors();
    command void printNeighbors();
}