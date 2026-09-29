#include "../../includes/packet.h"

// Wiring for the link layer
configuration LinkLayerC{
   provides interface LinkLayer;
   provides interface LinkReceive as FloodReceive; // wired to FloodingC
   provides interface LinkReceive as NeighborReceive; // wired to NeighborDiscoveryC
}

implementation{
   components LinkLayerP;
   LinkLayer = LinkLayerP.LinkLayer;
   FloodReceive = LinkLayerP.FloodReceive;
   NeighborReceive = LinkLayerP.NeighborReceive;

   // Boot is here so the link layer can start the radio itself, Node doesn't have to
   components MainC;
   LinkLayerP.Boot -> MainC.Boot;

   // ActiveMessageC = the actual radio
   components ActiveMessageC;
   LinkLayerP.AMControl -> ActiveMessageC;
   LinkLayerP.AMPacket -> ActiveMessageC;

   // the one sender and one receiver for AM_PACK, shared by all upper layers
   components new SimpleSendC(AM_PACK) as PackSender;
   LinkLayerP.Sender -> PackSender;

   components new AMReceiverC(AM_PACK) as PackReceiver;
   LinkLayerP.Receive -> PackReceiver;
}
