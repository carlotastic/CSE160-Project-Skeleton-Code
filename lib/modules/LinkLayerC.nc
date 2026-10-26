#include "../../includes/packet.h"
#include "../../includes/am_types.h"

// Wiring for the link layer
configuration LinkLayerC{
   provides interface LinkLayer;
   provides interface LinkReceive as FloodReceive; // wired to FloodingC
   provides interface LinkReceive as NeighborReceive; // wired to NeighborDiscoveryC
   provides interface LinkReceive as DVReceive;  // wired to DistanceVectorC (later)
   provides interface LinkReceive as IPReceive;  // wired to IPC (later)
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

      DVReceive = LinkLayerP.DVReceive;
   IPReceive = LinkLayerP.IPReceive;

   // DV traffic gets its own AM type, so its own sender + receiver
   components new SimpleSendC(AM_DV) as DVSender;
   LinkLayerP.DVSender -> DVSender;
   components new AMReceiverC(AM_DV) as DVRadioReceiver;
   LinkLayerP.DVRadioReceive -> DVRadioReceiver;

   // same for routed IP traffic
   components new SimpleSendC(AM_IP) as IPSender;
   LinkLayerP.IPSender -> IPSender;
   components new AMReceiverC(AM_IP) as IPRadioReceiver;
   LinkLayerP.IPRadioReceive -> IPRadioReceiver;
}
