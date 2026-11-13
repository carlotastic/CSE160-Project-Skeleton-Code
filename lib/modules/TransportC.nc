#include "../../includes/tcp.h"

configuration TransportC{
    provides interface TCP;
}

implementation{
    components TransportP;
    TCP = TransportP.TCP;


    components IPC;
    TransportP.IP -> IPC;
}

