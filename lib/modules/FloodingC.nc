#include "../../includes/packet.h"

configuration FloodingC{
    provides interface Flooding;
}

implementation{
    components FloodingP;
    Flooding = FloodingP.Flooding;

    // The shared singleton link layer, the same instance neighbor discovery
    // uses. FloodReceive delivers only packets with a real destination.
    components LinkLayerC;
    FloodingP.LinkLayer -> LinkLayerC.LinkLayer;
    FloodingP.LinkReceive -> LinkLayerC.FloodReceive;

    // The duplicate cache, owned solely by flooding. Node used to keep its own
    // copy of this, which meant the two never agreed on what had been seen.
    components new HashmapC(uint16_t, 20) as SeenMapC;
    FloodingP.SeenMap -> SeenMapC;
}
