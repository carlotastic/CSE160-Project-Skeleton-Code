/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "includes/packet.h"

//The application layer, and nothing else
module Node{
   uses interface Boot;

   uses interface CommandHandler;

   uses interface Flooding;
   uses interface NeighborDiscovery;
   uses interface DistanceVector;

   uses interface IP;
}

implementation{

   event void Boot.booted(){
      // The link layer brings the radio up and neighbor discovery starts itself
      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");

      // ping to self never goes on the radio
      if(destination == TOS_NODE_ID){
         dbg(ROUTING_CHANNEL, "Ping to self, delivered locally: %s\n", payload);
         return;
      }

      // routed, not flooded
      call IP.send(destination, PROTOCOL_PING, payload, PACKET_MAX_PAYLOAD_SIZE);
   }

   event void Flooding.receive(pack* msg){
      uint16_t seq;

      if(msg->protocol == PROTOCOL_PING){
         dbg(FLOODING_CHANNEL, "PING from %hu arrived. Payload: %s\n", msg->src, msg->payload);

         // Answer the original sender
         seq = call Flooding.send(msg->src, PROTOCOL_PINGREPLY, (uint8_t*) msg->payload, PACKET_MAX_PAYLOAD_SIZE);
         dbg(FLOODING_CHANNEL, "Sent PINGREPLY to %hu (seq %hu)\n", msg->src, seq);

      } else if(msg->protocol == PROTOCOL_PINGREPLY){
         // A reply ends the exchange
         dbg(FLOODING_CHANNEL, "PINGREPLY from %hu arrived\n", msg->src);
      }
   }

   event void NeighborDiscovery.neighborAdded(uint16_t id){}

   event void NeighborDiscovery.neighborLost(uint16_t id){}

   event void NeighborDiscovery.linkCostChanged(uint16_t id, uint8_t cost){}

   // a routed packet for this node arrived
   event void IP.receive(pack* msg){
      if(msg->protocol == PROTOCOL_PING){
         dbg(ROUTING_CHANNEL, "PING from %hu arrived. Payload: %s\n", msg->src, msg->payload);
         // reply is routed too
         call IP.send(msg->src, PROTOCOL_PINGREPLY, (uint8_t*) msg->payload, PACKET_MAX_PAYLOAD_SIZE);

      } else if(msg->protocol == PROTOCOL_PINGREPLY){
         dbg(ROUTING_CHANNEL, "PINGREPLY from %hu arrived\n", msg->src);
      }
   }

   event void CommandHandler.pingTTL(uint16_t destination, uint8_t ttl, uint8_t *payload){
      dbg(ROUTING_CHANNEL, "PING to %hu with TTL %hhu\n", destination, ttl);
      call IP.sendTTL(destination, PROTOCOL_PING, ttl, payload, PACKET_MAX_PAYLOAD_SIZE);
   }

   event void CommandHandler.printNeighbors(){
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
      call DistanceVector.printTable();
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
