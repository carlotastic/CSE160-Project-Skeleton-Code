#include <AM.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"

// Link layer: the only module that talks to the radio.
// turns the radio on, sends packets one hop, and sorts incoming packets to either flooding or neighbor discovery.
module LinkLayerP{
   provides interface LinkLayer;

   // One receive path per upper layer
   provides interface LinkReceive as FloodReceive;
   provides interface LinkReceive as NeighborReceive;

   uses interface Boot; // tells us the node has started
   uses interface SplitControl as AMControl; // turns the radio on/off
   uses interface SimpleSend as Sender; // queues packets for the radio
   uses interface Receive; // raw incoming packets
   uses interface AMPacket; // reads the link-level sender of a packet
}

implementation{

   event void Boot.booted(){
      call AMControl.start(); // split-phase: result comes back later in startDone
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         // tells flooding AND neighbor discovery they can start sending
         signal LinkLayer.ready();
      } else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   // one packet on the air, heard by every node in radio range (one hop only)
   command error_t LinkLayer.broadcast(pack* msg){
      return call Sender.send(*msg, AM_BROADCAST_ADDR);
   }

   // one packet on the air, only accepted by that one neighbor
   command error_t LinkLayer.unicast(pack* msg, uint16_t neighbor){
      return call Sender.send(*msg, neighbor);
   }

   // Every AM_PACK packet from the radio comes through here.
   //This way each layer only sees its own packets.
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      pack* received;
      uint16_t prevHop;

      // ignore anything that isn't our pack struct
      if(len != sizeof(pack)){
         dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
         return msg;
      }

      received = (pack*) payload;
      prevHop = call AMPacket.source(msg); // the neighbor who just transmitted this

      if(received->dest == AM_BROADCAST_ADDR){
         signal NeighborReceive.receive(received, prevHop);
      } else{
         signal FloodReceive.receive(received, prevHop);
      }

      // return a buffer so the radio can reuse it.
      // safe to return the same one since the handlers above already finished with it.
      return msg;
   }
}
