#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/tcp.h"
#include <Timer.h>

module TransportP{
   provides interface TCP;
   uses interface IP;
   uses interface Timer<TMilli> as tickTimer;
   uses interface Boot;

}


implementation{
   tcpConn conns[MAX_CONNECTIONS];

   char* stateName(uint8_t s){
      switch(s){
         case TCP_CLOSED:      return "CLOSED";
         case TCP_LISTEN:      return "LISTEN";
         case TCP_SYN_SENT:    return "SYN_SENT";
         case TCP_SYN_RCVD:    return "SYN_RCVD";
         case TCP_ESTABLISHED: return "ESTABLISHED";
         case TCP_FIN_WAIT_1:  return "FIN_WAIT_1";
         case TCP_FIN_WAIT_2:  return "FIN_WAIT_2";
         case TCP_CLOSE_WAIT:  return "CLOSE_WAIT";
         case TCP_LAST_ACK:    return "LAST_ACK";
         case TCP_TIME_WAIT:   return "TIME_WAIT";
         default:              return "?";
      }
   }

   void flagStr(uint8_t f, char* out){
      out[0] = '\0';
      if (f & TCP_FLAG_SYN) strcat(out, "SYN+");
      if (f & TCP_FLAG_ACK) strcat(out, "ACK+");
      if (f & TCP_FLAG_DATA) strcat(out, "DATA+");
      if (f & TCP_FLAG_FIN) strcat(out, "FIN+");
      if(out[0] != '\0'){
         out[strlen(out) - 1] = '\0';
      } else {
         strcat(out, "NONE");
      }
    }


   int8_t findExact(uint8_t localPort, uint16_t remoteAddr, uint8_t remotePort){
      uint8_t i;
      for(i = 0; i < MAX_CONNECTIONS; i++){
         if(conns[i].state != TCP_CLOSED && conns[i].state != TCP_LISTEN
            && conns[i].localPort == localPort
            && conns[i].remoteAddr == remoteAddr
            && conns[i].remotePort == remotePort){
            return i;
         }
      }
      return -1;
   }

   int8_t findListener(uint8_t localPort){
      uint8_t i;
      for(i = 0; i < MAX_CONNECTIONS; i++){
         if(conns[i].state == TCP_LISTEN && conns[i].localPort == localPort){
            return i;
         }
      }
      return -1;
   }

   int8_t allocConn(){ // allocating a connection record
      uint8_t i;
      for(i = 0; i < MAX_CONNECTIONS; i++){
         if(conns[i].state == TCP_CLOSED){
            memset(&conns[i], 0, sizeof(tcpConn));
            dbg(TRANSPORT_CHANNEL, "conn=%hhu allocated\n", i);
            return i;
         }
      }
      dbg(TRANSPORT_CHANNEL, "Connection table full\n");
      return -1;
   }

    void setState(uint8_t id, uint8_t s){
      dbg(TRANSPORT_CHANNEL, "conn=%hhu %hu:%hhu->%hu:%hhu %s -> %s\n",
         id, TOS_NODE_ID, conns[id].localPort, conns[id].remoteAddr, conns[id].remotePort,
         stateName(conns[id].state), stateName(s));
      conns[id].state = s;
   }

   uint8_t freeRecvSpace(uint8_t id){
      return TCP_BUFFER_SIZE - conns[id].rcvCount;
   }

   // sending a packet with flags and stuff
   void sendSegment(uint8_t id, uint8_t flags, uint16_t seq, uint8_t* data, uint8_t len){
      tcpSegment seg; // segment to send
      tcpConn* c; // connection record
      char fl[20]; // flag

      c = &conns[id]; // set the connection record pointer to what was given
      memset(&seg, 0, sizeof(tcpSegment));
      seg.srcPort  = c->localPort;
      seg.destPort = c->remotePort;
      seg.flags    = flags;
      seg.seq      = seq;
      seg.ack      = c->rcvNxt; // always tell them what we expect next
      seg.window   = freeRecvSpace(id); // and how much room we have
      seg.len      = len;
      if(len > 0){
         memcpy(seg.data, data, len);
      }

      flagStr(flags, fl);
      dbg(TRANSPORT_CHANNEL, "conn=%hhu %hu:%hhu->%hu:%hhu TX %s seq=%hu ack=%hu len=%hhu wnd=%hhu\n",
          id, TOS_NODE_ID, c->localPort, c->remoteAddr, c->remotePort,
          fl, seq, (uint16_t) seg.ack, len, (uint8_t) seg.window);

      // a fresh IP packet every time: current route, new TTL (spec requirement)
      if(call IP.send(c->remoteAddr, PROTOCOL_TCP, (uint8_t*) &seg, sizeof(tcpSegment)) != SUCCESS){
         dbg(TRANSPORT_CHANNEL, "conn=%hhu send failed (no route or queue full), timer will retry\n", id);
      }
   }


   // start (or restart) the retransmit timer for this connection
   void startTimer(uint8_t id){
      conns[id].deadline = call tickTimer.getNow() + TCP_RTO_MS;
   }

   // the thing we were waiting for arrived: stop the timer and reset retries
   void stopTimer(uint8_t id){
      conns[id].deadline = 0;
      conns[id].retries = 0;
   }

   // give up on a connection: free the record and tell the app
   void failConn(uint8_t id){
      uint8_t oldState;

      oldState = conns[id].state;
      dbg(TRANSPORT_CHANNEL, "conn=%hhu FAILED in %s, releasing record\n", id, stateName(oldState));
      setState(id, TCP_CLOSED);   // CLOSED = record is free again

      if(oldState == TCP_SYN_SENT){
         signal TCP.connectDone(id, FAIL); // client never connected
      } else if(oldState != TCP_SYN_RCVD){
         signal TCP.closed(id, FAIL); // was connected, now broken
      }
      // SYN_RCVD: a half-open server record the app never saw, nothing to report
   }

   //the server side of a new connection

   // a SYN reached a listening port, so make a NEW record (the listener stays LISTEN)
   void acceptSyn(uint16_t fromAddr, tcpSegment* seg){
      int8_t id;
      tcpConn* c;

      id = allocConn();
      if(id < 0){
         dbg(TRANSPORT_CHANNEL, "No free record, ignoring SYN (the client will retry)\n");
         return;
      }

      c = &conns[id];
      c->localPort  = seg->destPort;
      c->remoteAddr = fromAddr;
      c->remotePort = seg->srcPort;
      c->rcvNxt     = seg->seq + 1; // their SYN used one number
      c->peerWindow = seg->window;
      c->sndUna     = TCP_ISN_SERVER; // our SYN uses this number
      c->sndNxt     = TCP_ISN_SERVER + 1;
      c->sndEnd     = c->sndNxt;

      setState(id, TCP_SYN_RCVD);
      sendSegment(id, TCP_FLAG_SYN | TCP_FLAG_ACK, TCP_ISN_SERVER, NULL, 0);
      startTimer(id);
   }

   //a segment for an existing connection
   void handleSegment(uint8_t id, tcpSegment* seg){
      tcpConn* c;

      c = &conns[id];

      switch(c->state){

         // client: waiting for a SYN-ACK that acknowledges our SYN
         case TCP_SYN_SENT:
            if((seg->flags & TCP_FLAG_SYN) && (seg->flags & TCP_FLAG_ACK)
               && seg->ack == c->sndUna + 1){
               c->rcvNxt     = seg->seq + 1; // their SYN used one number
               c->sndUna     = seg->ack; // our SYN is acknowledged
               c->peerWindow = seg->window;
               stopTimer(id);
               setState(id, TCP_ESTABLISHED);
               sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0); // final handshake ACK
               signal TCP.connectDone(id, SUCCESS);
            } else{
               dbg(TRANSPORT_CHANNEL, "conn=%hhu unexpected segment in SYN_SENT, ignoring\n", id);
            }
            break;

         // server is waiting for the final ACK
         case TCP_SYN_RCVD:
            if(seg->flags == TCP_FLAG_SYN){
               // the client resent its SYN, so our SYN-ACK was lost, so resend it, NO new record
               dbg(TRANSPORT_CHANNEL, "conn=%hhu duplicate SYN, resending SYN+ACK\n", id);
               sendSegment(id, TCP_FLAG_SYN | TCP_FLAG_ACK, c->sndUna, NULL, 0);
            } else if((seg->flags & TCP_FLAG_ACK) && seg->ack == c->sndUna + 1){
               c->sndUna     = seg->ack;       // our SYN is acknowledged
               c->peerWindow = seg->window;
               stopTimer(id);
               setState(id, TCP_ESTABLISHED);
               signal TCP.accepted(id);
            }
            break;

         case TCP_ESTABLISHED:
            // a repeated SYN-ACK means our final ACK was lost, so send it again
            if((seg->flags & TCP_FLAG_SYN) && (seg->flags & TCP_FLAG_ACK)){
               dbg(TRANSPORT_CHANNEL, "conn=%hhu duplicate SYN+ACK, resending ACK\n", id);
               sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0);
               break;
            }
            break;

         default:
            break;
      }
   }

   // what happens when a connection's timer runs out
   void onTimeout(uint8_t id){
      tcpConn* c;

      c = &conns[id];
      c->retries++;

      if(c->retries > TCP_MAX_RETRIES){
         dbg(TRANSPORT_CHANNEL, "conn=%hhu no answer after %d retries, giving up\n", id, TCP_MAX_RETRIES);
         failConn(id);
         return;
      }

      dbg(TRANSPORT_CHANNEL, "conn=%hhu TIMEOUT #%hhu in %s, retransmitting\n",
          id, c->retries, stateName(c->state));

      switch(c->state){
         case TCP_SYN_SENT:
            sendSegment(id, TCP_FLAG_SYN, c->sndUna, NULL, 0);
            break;
         case TCP_SYN_RCVD:
            sendSegment(id, TCP_FLAG_SYN | TCP_FLAG_ACK, c->sndUna, NULL, 0);
            break;
         // M3: resend data. M4: resend FIN, end TIME_WAIT.
         default:
            break;
      }
      startTimer(id);
   }

   // receiving a packet from IP layer
   event void IP.receive(pack* msg){
      tcpSegment* seg;
      int8_t id;
      char fl[20];

      if(msg->protocol != PROTOCOL_TCP){
         return;   // ping and others belong to Node
      }

      seg = (tcpSegment*) msg->payload;

      // check the length BEFORE touching the data (spec: validate before access)
      if(seg->len > TCP_MAX_DATA){
         dbg(TRANSPORT_CHANNEL, "Malformed segment from %hu (len %hhu), dropping\n", msg->src, (uint8_t) seg->len);
         return;
      }

      flagStr(seg->flags, fl);
      dbg(TRANSPORT_CHANNEL, "RX %s from %hu:%hhu to port %hhu seq=%hu ack=%hu len=%hhu wnd=%hhu\n",
         fl, msg->src, (uint8_t) seg->srcPort, (uint8_t) seg->destPort,
         (uint16_t) seg->seq, (uint16_t) seg->ack, (uint8_t) seg->len, (uint8_t) seg->window);

      id = findExact(seg->destPort, msg->src, seg->srcPort);
      if(id >= 0){
         handleSegment(id, seg);
         return;
      }

      // 2) no connection yet: only a SYN to a listening port can start one
      if(seg->flags == TCP_FLAG_SYN){
         if(findListener(seg->destPort) >= 0){
            acceptSyn(msg->src, seg);
         } else{
            dbg(TRANSPORT_CHANNEL, "SYN for port %hhu but nobody is listening, ignoring\n", (uint8_t) seg->destPort);
         }
         return;
      }

      dbg(TRANSPORT_CHANNEL, "No connection for this segment, ignoring\n");
   }

   event void Boot.booted(){
      call tickTimer.startPeriodic(TCP_TICK_MS);
   }

   // every 250 ms, any connection whose deadline has passed gets onTimeout
   event void tickTimer.fired(){
      uint8_t i;
      uint32_t now;

      now = call tickTimer.getNow();
      for(i = 0; i < MAX_CONNECTIONS; i++){
         if(conns[i].state == TCP_CLOSED || conns[i].state == TCP_LISTEN){
            continue; // free records and listeners have no timer
         }
         if(conns[i].deadline != 0 && now >= conns[i].deadline){
            onTimeout(i);
         }
      }
   }

   command error_t TCP.listen(uint8_t port){
      int8_t id;

      if(findListener(port) >= 0){
         return SUCCESS; // already listening
      }
      id = allocConn();
      if(id < 0){
         return FAIL;
      }
      conns[id].localPort = port;
      setState(id, TCP_LISTEN);
      return SUCCESS;
   }

   command int8_t TCP.connect(uint8_t srcPort, uint16_t destAddr, uint8_t destPort){
      int8_t id;
      tcpConn* c;

      if(findExact(srcPort, destAddr, destPort) >= 0){
         dbg(TRANSPORT_CHANNEL, "Connection %hhu->%hu:%hhu already exists\n", srcPort, destAddr, destPort);
         return -1;
      }
      id = allocConn();
      if(id < 0){
         return -1;
      }

      c = &conns[id];
      c->localPort  = srcPort;
      c->remoteAddr = destAddr;
      c->remotePort = destPort;
      c->sndUna = TCP_ISN_CLIENT; // our SYN uses this number
      c->sndNxt = TCP_ISN_CLIENT + 1; // the first data byte comes after the SYN
      c->sndEnd = c->sndNxt; // nothing queued yet

      setState(id, TCP_SYN_SENT);
      sendSegment(id, TCP_FLAG_SYN, TCP_ISN_CLIENT, NULL, 0);
      startTimer(id);

      return id;
   }

   command uint16_t TCP.write(uint8_t id, uint8_t* buf, uint16_t len){
      return 0;   // M3
   }

   command uint16_t TCP.read(uint8_t id, uint8_t* buf, uint16_t len){
      return 0;   // M3
   }

   command error_t TCP.close(uint8_t id){
      return FAIL;   // M4
   }

   command int8_t TCP.findConn(uint8_t localPort, uint16_t remoteAddr, uint8_t remotePort){
      return findExact(localPort, remoteAddr, remotePort);
   }

}   
    


