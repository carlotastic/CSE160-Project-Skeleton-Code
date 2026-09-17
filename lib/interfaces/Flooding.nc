#include "../../includes/packet.h"

interface Flooding{
    command error_t flood(pack *msg);
    event void receivedFlood(pack *msg);
    
}