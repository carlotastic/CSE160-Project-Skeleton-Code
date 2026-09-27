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

    // The two network services. Both sit on the shared LinkLayerC, which owns
    // the radio, the AM receiver and the send queue, so nothing is wired to
    // ActiveMessageC from here.
    components FloodingC;
    Node.Flooding -> FloodingC;

    components NeighborDiscoveryC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;
}
