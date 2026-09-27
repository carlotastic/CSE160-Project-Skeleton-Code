#include <AM.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module LinkLayerP{
   provides interface LinkLayer;

   // One receive path per upper layer. See Receive.receive for the split.
   provides interface LinkReceive as FloodReceive;
   provides interface LinkReceive as NeighborReceive;

   uses interface Boot;
   uses interface SplitControl as AMControl;
   uses interface SimpleSend as Sender;
   uses interface Receive;
   uses interface AMPacket;
}

implementation{

   event void Boot.booted(){
      call AMControl.start();
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         // Every upper layer learns it may start transmitting. Nothing above
         // this module has to know the radio exists, let alone start it.
         signal LinkLayer.ready();
      } else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   command error_t LinkLayer.broadcast(pack* msg){
      return call Sender.send(*msg, AM_BROADCAST_ADDR);
   }

   command error_t LinkLayer.unicast(pack* msg, uint16_t neighbor){
      return call Sender.send(*msg, neighbor);
   }

   /*
    * The single radio receive path for AM_PACK.
    *
    * Neighbor discovery marks its packets by addressing them to everyone;
    * anything carrying a real destination belongs to flooding. Splitting here
    * means neither upper layer ever sees the other's traffic, which in turn
    * keeps neighbor discovery's sequence numbers out of flooding's duplicate
    * cache.
    */
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      pack* received;
      uint16_t prevHop;

      if(len != sizeof(pack)){
         dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
         return msg;
      }

      received = (pack*) payload;
      prevHop = call AMPacket.source(msg);

      if(received->dest == AM_BROADCAST_ADDR){
         signal NeighborReceive.receive(received, prevHop);
      } else{
         signal FloodReceive.receive(received, prevHop);
      }

      // Both handlers are synchronous and neither keeps a reference to the
      // buffer, so we hand the same one back for the radio to reuse.
      return msg;
   }
}
