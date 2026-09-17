#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"

module FloodingP{
    provides interface Flooding;

    uses interface SimpleSend as Sender;
    uses interface Receive;
    uses interface Hashmap<uint16_t> as SeenMap;
    
}

implementation{
    pack floodPackage;
    uint16_t seqCounter = 0;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);


    command error_t Flooding.flood(pack *msg) {
        // record the current node in the SeenMap

    }

       event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;

        // CHECK TO SEE IF CURRENT NODE IS IN SEENMAP

         if(myMsg->dest == myMsg->src){
            signal Flooding.receivedFlood(myMsg);
            logPack(myMsg);
         }
         else {
            if(myMsg->TTL == 0){
               dbg(FLOODING_CHANNEL, "SOURCE: %hhu SEQ: %hhu TTL: %hhu Dropped because TTL expired", myMsg->src, myMsg->seq, myMsg->TTL);
               return msg;
            }
            sendPackage = *myMsg; // reuse the already allocated sendPackage variable to store local package
            sendPackage.TTL--;

            if(sendPackage.TTL == 0){
               dbg(FLOODING_CHANNEL, "SOURCE: %hhu SEQ: %hhu TTL: %hhu Dropped because TTL expired after decrementing", sendPackage.src, sendPackage.seq, sendPackage.TTL);
               return msg;
            }
            else {
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);
            }


         }

         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }
}


