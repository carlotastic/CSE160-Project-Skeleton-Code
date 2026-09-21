configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;
}