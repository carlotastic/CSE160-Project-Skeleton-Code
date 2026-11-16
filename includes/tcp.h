#ifndef TCP_H
#define TCP_H

#include "packet.h"


// TCP flags
enum{
    TCP_FLAG_SYN = 0x01,
    TCP_FLAG_ACK = 0x02,
    TCP_FLAG_FIN = 0x04,
    TCP_FLAG_DATA = 0x08
};

// TCP constants
enum{
    TCP_HEADER_LENGTH = 9,
    TCP_MAX_DATA = PACKET_MAX_PAYLOAD_SIZE - TCP_HEADER_LENGTH,
    TCP_BUFFER_SIZE = 128, // What is this for?
    MAX_CONNECTIONS = 4, // What is this for?
    TCP_TICK_MS = 250,
    TCP_RTO_MS = 3000, // What is this
    TCP_MAX_RETRIES = 8,
    TCP_TIME_WAIT_MS = 12000,
    TCP_ISN_CLIENT = 100,
    TCP_ISN_SERVER = 500
};

// Connection States
enum{
    TCP_CLOSED = 0,
    TCP_LISTEN,
    TCP_SYN_SENT,
    TCP_SYN_RCVD,
    TCP_ESTABLISHED,
    TCP_FIN_WAIT_1,
    TCP_FIN_WAIT_2,
    TCP_CLOSE_WAIT,
    TCP_LAST_ACK,
    TCP_TIME_WAIT
};

typedef nx_struct tcpSegment{
   nx_uint8_t  srcPort;
   nx_uint8_t  destPort;
   nx_uint8_t  flags;
   nx_uint16_t seq;     // first byte of this segment (or the SYN/FIN's number)
   nx_uint16_t ack;     // next byte we expect from the other side
   nx_uint8_t  window;  // free space in our receive buffer
   nx_uint8_t  len;     // number of data bytes
   nx_uint8_t  data[TCP_MAX_DATA];
} tcpSegment;

typedef struct cpConn{
    uint8_t state;
    uint8_t localPort;
    uint16_t remoteAddr;
    uint8_t remotePort;

    // sending side
    uint16_t sndUna; 
    uint16_t sndNxt;
    uint16_t sndEnd;
    uint8_t sendBuf[TCP_BUFFER_SIZE];
    uint8_t peerWindow;
    bool closeAsked;
    uint16_t finSeq;

    // receiving side
    uint16_t rcvNxt;
    uint8_t rcvBuf[TCP_BUFFER_SIZE];
    uint8_t rcvCount;

    // timer 
    uint32_t deadline;
    uint8_t retries;

} tcpConn;

#endif