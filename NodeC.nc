/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    Node -> MainC.Boot;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    // flooding and neighbor discovery both use LinkLayerC,
    // so Node doesn't need to wire the radio (ActiveMessageC) itself.
    components FloodingC;
    Node.Flooding -> FloodingC;

    components NeighborDiscoveryC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;
}
