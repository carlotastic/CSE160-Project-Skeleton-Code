#include "../../includes/packet.h"

/*
 * A singleton on purpose, not a generic component.
 *
 * Every upper layer names this same component, so they share one radio, one
 * AM receiver and one send queue. Making it generic would hand each client its
 * own AMReceiverC(AM_PACK), and the same AM id cannot be wired twice.
 */
configuration LinkLayerC{
   provides interface LinkLayer;
   provides interface LinkReceive as FloodReceive;
   provides interface LinkReceive as NeighborReceive;
}

implementation{
   components LinkLayerP;
   LinkLayer = LinkLayerP.LinkLayer;
   FloodReceive = LinkLayerP.FloodReceive;
   NeighborReceive = LinkLayerP.NeighborReceive;

   // The link layer owns radio start-up, so no application code has to.
   components MainC;
   LinkLayerP.Boot -> MainC.Boot;

   components ActiveMessageC;
   LinkLayerP.AMControl -> ActiveMessageC;
   LinkLayerP.AMPacket -> ActiveMessageC;

   components new SimpleSendC(AM_PACK) as PackSender;
   LinkLayerP.Sender -> PackSender;

   components new AMReceiverC(AM_PACK) as PackReceiver;
   LinkLayerP.Receive -> PackReceiver;
}
