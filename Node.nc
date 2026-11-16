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

   uses interface Timer<TMilli> as appTimer;
}

implementation{

   enum{
      TEST_CHUNK = 32,     // bytes per write/read attempt
      APP_TICK_MS = 500    // how often the producer/consumer runs
   };

   // per-connection test state (index = transport record id)
   bool isClient[MAX_CONNECTIONS];
   bool isServer[MAX_CONNECTIONS];
   bool closeSent[MAX_CONNECTIONS];
   uint16_t toSend[MAX_CONNECTIONS]; // client: total bytes to send
   uint16_t accepted[MAX_CONNECTIONS]; // client: bytes transport accepted
   uint16_t consumed[MAX_CONNECTIONS]; // server: bytes read and checked
   uint16_t mismatches[MAX_CONNECTIONS]; // server: bytes that weren't k mod 256

   event void Boot.booted(){
      // The link layer brings the radio up and neighbor discovery starts itself
      dbg(GENERAL_CHANNEL, "Booted\n");
      call appTimer.startPeriodic(APP_TICK_MS);
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

   // cmdTestClient: open a connection; bytes are sent once it's ESTABLISHED
   event void CommandHandler.setTestClient(uint16_t server, uint8_t srcPort, uint8_t destPort, uint16_t transferBytes){
      int8_t id;

      dbg(TRANSPORT_CHANNEL, "Test client: %hu:%hhu -> %hu:%hhu, %hu bytes\n",
          TOS_NODE_ID, srcPort, server, destPort, transferBytes);
      id = call TCP.connect(srcPort, server, destPort);
      if(id >= 0){
         toSend[id] = transferBytes;
         accepted[id] = 0;
         closeSent[id] = FALSE;
      }
   }

   // cmdClientClose: graceful close of that connection
   event void CommandHandler.clientClose(uint16_t server, uint8_t srcPort, uint8_t destPort){
      int8_t id;

      id = call TCP.findConn(srcPort, server, destPort);
      if(id < 0){
         dbg(TRANSPORT_CHANNEL, "Test client: no connection %hhu->%hu:%hhu to close\n", srcPort, server, destPort);
         return;
      }
      closeSent[id] = TRUE;
      call TCP.close(id);
   }

   event void TCP.connectDone(uint8_t id, error_t result){
      if(result == SUCCESS){
         dbg(TRANSPORT_CHANNEL, "Test client: conn=%hhu CONNECTED, sending %hu bytes\n", id, toSend[id]);
         isClient[id] = TRUE; // the producer starts on the next app tick
      } else{
         dbg(TRANSPORT_CHANNEL, "Test client: conn=%hhu FAILED to connect\n", id);
      }
   }

   event void TCP.accepted(uint8_t id){
      dbg(TRANSPORT_CHANNEL, "Test server: ACCEPTED conn=%hhu\n", id);
      isServer[id] = TRUE;
      consumed[id] = 0;
      mismatches[id] = 0;
   }

   event void TCP.closed(uint8_t id, error_t result){
      if(isClient[id]){
         dbg(TRANSPORT_CHANNEL, "Test client: conn=%hhu closed %s, %hu of %hu bytes accepted\n",
             id, (result == SUCCESS) ? "OK" : "FAILED", accepted[id], toSend[id]);
      }
      if(isServer[id]){
         dbg(TRANSPORT_CHANNEL, "Test server: conn=%hhu closed %s, consumed %hu bytes, %hu mismatches\n",
             id, (result == SUCCESS) ? "OK" : "FAILED", consumed[id], mismatches[id]);
      }
      isClient[id] = FALSE; // the record id may be reused later
      isServer[id] = FALSE;
   }

   // every 0.5 s: the producer writes, the consumer reads and checks
   event void appTimer.fired(){
      uint8_t id;
      uint8_t buf[TEST_CHUNK];
      uint16_t want;
      uint16_t got;
      uint16_t i;

      for(id = 0; id < MAX_CONNECTIONS; id++){

         // ---- producer: byte k = k mod 256, only as fast as transport accepts ----
         if(isClient[id] && accepted[id] < toSend[id] && !closeSent[id]){
            want = toSend[id] - accepted[id];
            if(want > TEST_CHUNK){
               want = TEST_CHUNK;
            }
            for(i = 0; i < want; i++){
               buf[i] = (accepted[id] + i) % 256;
            }
            got = call TCP.write(id, buf, want);
            accepted[id] += got; // advance ONLY by what transport took

            if(accepted[id] == toSend[id]){
               dbg(TRANSPORT_CHANNEL, "Test client: conn=%hhu all %hu bytes accepted, closing\n", id, toSend[id]);
               closeSent[id] = TRUE;
               call TCP.close(id);
            }
         }

         // ---- consumer: read and check every byte ----
         if(isServer[id]){
            got = call TCP.read(id, buf, TEST_CHUNK);
            if(got > 0){
               for(i = 0; i < got; i++){
                  if(buf[i] != (uint8_t)((consumed[id] + i) % 256)){
                     mismatches[id]++;
                  }
               }
               dbg(TRANSPORT_CHANNEL, "Test server: conn=%hhu read %hu bytes [%hhu..%hhu], total %hu, mismatches %hu\n",
                   id, got, buf[0], buf[got - 1], consumed[id] + got, mismatches[id]);
               consumed[id] += got;
            }
         }
      }
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
