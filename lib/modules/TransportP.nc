#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/tcp.h"

module TransportP{
    provides interface TCP;
    uses interface IP;

}