/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "includes/packet.h"
#include "includes/tcp.h"

//The application layer, and nothing else
module Node{
   uses interface Boot;

   uses interface CommandHandler;

   uses interface Flooding;
   uses interface NeighborDiscovery;
   uses interface DistanceVector;

   uses interface IP;
   uses interface TCP;
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

   // cmdTestServer: listen on a port
   event void CommandHandler.setTestServer(uint8_t port){
      dbg(TRANSPORT_CHANNEL, "Test server: listening on port %hhu\n", port);
      call TCP.listen(port);
   }

   // cmdTestClient: open a connection (sending data comes in M3)
   event void CommandHandler.setTestClient(uint16_t server, uint8_t srcPort, uint8_t destPort, uint16_t transferBytes){
      dbg(TRANSPORT_CHANNEL, "Test client: %hu:%hhu -> %hu:%hhu, %hu bytes\n",
          TOS_NODE_ID, srcPort, server, destPort, transferBytes);
      call TCP.connect(srcPort, server, destPort);
   }

   // cmdClientClose (M4)
   event void CommandHandler.clientClose(uint16_t server, uint8_t srcPort, uint8_t destPort){}

   event void TCP.connectDone(uint8_t id, error_t result){}
   event void TCP.accepted(uint8_t id){}
   event void TCP.closed(uint8_t id, error_t result){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
