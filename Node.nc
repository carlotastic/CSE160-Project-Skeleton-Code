/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include <AM.h>

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface AMPacket;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface NeighborDiscovery;
   uses interface Hashmap<uint16_t> as SeenMap;
}

implementation{
   pack sendPackage;
   uint16_t seqCounter = 0;


   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   // true if this has already been handled, otherwise records it
   bool alreadySeen(pack* p) {
      if(call SeenMap.contains(p->src) && call SeenMap.get(p->src) >= p->seq) {
         return TRUE;
      }
      call SeenMap.insert(p->src, p->seq);
      return FALSE;
   }

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call NeighborDiscovery.start();
      } else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      pack* myMsg;
      uint16_t prevHop;

      if(len != sizeof(pack)) {
         dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
         return msg;
      }

      myMsg = (pack*) payload;
      prevHop = call AMPacket.source(msg);

      // neighbor disc packets never get flooded
      if(myMsg->dest == AM_BROADCAST_ADDR) {
         call NeighborDiscovery.handle(myMsg);
         return msg;
      }

      dbg(FLOODING_CHANNEL, "Received from %hu (src %hu, dest %hu, seq %hu, TTL: %hhu)\n", prevHop, myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL);
      
      // check for duplicate suppression
      if(alreadySeen(myMsg)) {
         dbg(FLOODING_CHANNEL, "Duplicate (src %hu, seq %hu), dropping\n", myMsg->src, myMsg->seq);
         return msg;
      }

      // check it its for current pack
      if(myMsg->dest == TOS_NODE_ID) {
         if(myMsg->protocol == PROTOCOL_PING) {
            dbg(FLOODING_CHANNEL, "PING from %hu arrived. Payload: %s\n", myMsg->src, myMsg->payload);
            makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, ++seqCounter, (uint8_t*) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call SeenMap.insert(TOS_NODE_ID, seqCounter);
            call Sender.send(sendPackage, AM_BROADCAST_ADDR);
            dbg(FLOODING_CHANNEL, "Sent PINGREPLY to %hu (seq %hu)\n", myMsg->src, seqCounter);
         } else if(myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(FLOODING_CHANNEL, "PINGREPLY from %hu arrived\n", myMsg->src);
         }
         return msg;
      }

      // it not for current package, forward if TTL allows
      if(myMsg->TTL <= 1) {
         dbg(FLOODING_CHANNEL, "TTL expired (src %hu, seq %hu), dropping\n", myMsg->src, myMsg->seq);
         return msg;
      }
      sendPackage = *myMsg;
      sendPackage.TTL--;
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      dbg(FLOODING_CHANNEL, "Forwarded (src %hu, seq %hu, TTL now %hhu)\n", sendPackage.src, sendPackage.seq, sendPackage.TTL);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      if(destination == TOS_NODE_ID) {
         dbg(FLOODING_CHANNEL, "Ping to self, delivered locally: %s\n", payload);
         return;
      }
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, ++seqCounter, payload, PACKET_MAX_PAYLOAD_SIZE);
      call SeenMap.insert(TOS_NODE_ID, seqCounter); // so we dont reflood our own echo
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      dbg(FLOODING_CHANNEL, "Sent PING to %hu (seq %hu)\n", destination, seqCounter);
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

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
