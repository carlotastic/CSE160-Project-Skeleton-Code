#include "packet.h"
#include "CommandMsg.h"

#ifndef __AM_TYPES_H__
#define __AM_TYPES_H__
enum{
    AM_FLOODING=10,
    AM_DV=11, // distance vector advertisements
    AM_IP=12 // routed (IP) packets like ping
};
#endif
