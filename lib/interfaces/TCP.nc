#include "../../includes/tcp.h"

interface TCP{

    // server: starts listening on a given port
    command error_t listen(uint8_t port);

    // client: opens a connection, returns the record or connection id (-1 if failed)
    command int8_t connect(uint8_t srcPort, uint16_t destAddr, uint8_t destPort);

    // queue bytes to send, returns how many were accepted (may be fewer than the length)
    command uint16_t write(uint8_t id, uint8_t* buf, uint16_t len);

    // take received bytes out of the buffer, returns how many were read
    command uint16_t read(uint8_t id, uint8_t* buf, uint16_t len);

    // graceful close: send the remianing data and then close the connection
    command error_t close(uint8_t id);

    // find a connection by its 4 values (our port, their node address, their port, and the connection id)
    command int8_t findConn(uint8_t localPort, uint16_t remoteAddr, uint8_t remotePort);

    event void connectDone(uint8_t id, error_t result); // client
    event void accepted(uint8_t id); // server
    event void closed(uint8_t id, error_t result);



}