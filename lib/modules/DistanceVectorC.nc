#include "../../includes/dv.h"
#include <Timer.h>

// Wiring for distance-vector routing
configuration DistanceVectorC{
   provides interface DistanceVector;
}

implementation{
   components DistanceVectorP;
   DistanceVector = DistanceVectorP.DistanceVector;

   // set up the self-route at boot
   components MainC;
   DistanceVectorP.Boot -> MainC.Boot;

   // DV packets arrive on their own AM type (from Step 3)
   components LinkLayerC;
   DistanceVectorP.LinkReceive -> LinkLayerC.DVReceive;

   // ask ND who our neighbors are, and hear when they change
   components NeighborDiscoveryC;
   DistanceVectorP.NeighborDiscovery -> NeighborDiscoveryC;

   // sending DV packets
   DistanceVectorP.LinkLayer -> LinkLayerC.LinkLayer;

   // periodic advertisement timer (our own private timer)
   components new TimerMilliC() as dvTimer;
   DistanceVectorP.dvTimer -> dvTimer;

   // random jitter so nodes don't all send at once
   components RandomC as Random;
   DistanceVectorP.Random -> Random;
}