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
}

implementation{

   event void Boot.booted(){
      // The link layer brings the radio up and neighbor discovery starts itself
      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      uint16_t seq;

      dbg(GENERAL_CHANNEL, "PING EVENT \n");

      // ping to self is handled here instead of flooding it.
      // otherwise every node would rebroadcast a packet that nobody else needs.
      if(destination == TOS_NODE_ID){
         dbg(FLOODING_CHANNEL, "Ping to self, delivered locally: %s\n", payload);
         return;
      }

      seq = call Flooding.send(destination, PROTOCOL_PING, payload, PACKET_MAX_PAYLOAD_SIZE);
      dbg(FLOODING_CHANNEL, "Sent PING to %hu (seq %hu)\n", destination, seq);
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

   event void CommandHandler.printNeighbors(){
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
