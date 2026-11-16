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



   // sender side 

   // an ACK from the other side: free the bytes it covers
   void handleAck(uint8_t id, tcpSegment* seg){
      tcpConn* c;
      uint16_t ack;

      c = &conns[id];
      ack = seg->ack;

      // only trust ACKs between what's already ACKed and what we actually sent
      if(ack >= c->sndUna && ack <= c->sndNxt){
         c->peerWindow = seg->window; // newest valid window
         if(ack > c->sndUna){
            c->sndUna = ack; // bytes before ack are confirmed: space is free
            stopTimer(id); // what we waited for arrived
            dbg(TRANSPORT_CHANNEL, "conn=%hhu ACK %hu accepted, in flight=%hu, peer wnd=%hhu\n",
                id, ack, (uint16_t)(c->sndNxt - c->sndUna), c->peerWindow);
            if(c->sndNxt != c->sndUna){
               startTimer(id); // still something in flight
            }
         }
      } else{
         dbg(TRANSPORT_CHANNEL, "conn=%hhu ignoring impossible ACK %hu (una=%hu nxt=%hu)\n",
             id, ack, c->sndUna, c->sndNxt);
      }
   }

   // once all data is ACKed and the app asked to close, send our FIN
   void maybeSendFin(uint8_t id){
      tcpConn* c;

      c = &conns[id];
      if(!c->closeAsked || c->sndUna != c->sndEnd){
         return; // not asked to close, or data still unACKed
      }
      if(c->state == TCP_ESTABLISHED){
         setState(id, TCP_FIN_WAIT_1); // we close first (client)
      } else if(c->state == TCP_CLOSE_WAIT && c->rcvCount == 0){
         setState(id, TCP_LAST_ACK); // they closed first, our app read everything
      } else{
         return;
      }
      c->finSeq = c->sndEnd; // the FIN uses the next sequence number
      c->sndNxt = c->finSeq + 1;
      sendSegment(id, TCP_FLAG_FIN, c->finSeq, NULL, 0);
      startTimer(id);
   }

   // send the next data segment if allowed. STOP-AND-WAIT: only when nothing is in flight.
   void trySend(uint8_t id){
      tcpConn* c;
      uint16_t queued;
      uint8_t len;
      uint8_t i;
      uint8_t data[TCP_MAX_DATA];

      c = &conns[id];
      if(c->state != TCP_ESTABLISHED && c->state != TCP_CLOSE_WAIT){
         return;
      }
      if(c->sndNxt != c->sndUna){
         return; // stop-and-wait: wait for the ACK first
      }

      queued = c->sndEnd - c->sndNxt;
      if(queued == 0){
         maybeSendFin(id);  // nothing left to send: maybe it's time to close
         return;
      }
      if(c->peerWindow == 0){
         dbg(TRANSPORT_CHANNEL, "conn=%hhu peer window is 0, waiting\n", id);
         return;
      }

      // segment size = smallest of: what's queued, what fits in a segment, what they have room for
      len = TCP_MAX_DATA;
      if(queued < len)          len = queued;
      if(c->peerWindow < len)   len = c->peerWindow;

      for(i = 0; i < len; i++){
         data[i] = c->sendBuf[(c->sndNxt + i) % TCP_BUFFER_SIZE];
      }
      sendSegment(id, TCP_FLAG_DATA, c->sndNxt, data, len);
      c->sndNxt += len;
      startTimer(id);
   }




   // receiver side 

   // a data segment: keep it only if it's exactly the next byte we expect
   void handleData(uint8_t id, tcpSegment* seg){
      tcpConn* c;
      uint8_t i;

      c = &conns[id];
      if(seg->seq != c->rcvNxt){
         dbg(TRANSPORT_CHANNEL, "conn=%hhu DATA seq=%hu but expected %hu: discarding (duplicate or out of order)\n",
             id, (uint16_t) seg->seq, c->rcvNxt);
      } else if(seg->len > freeRecvSpace(id)){
         dbg(TRANSPORT_CHANNEL, "conn=%hhu DATA seq=%hu len=%hhu doesn't fit (free %hhu): discarding\n",
             id, (uint16_t) seg->seq, (uint8_t) seg->len, freeRecvSpace(id));
      } else{
         for(i = 0; i < seg->len; i++){
            c->rcvBuf[(c->rcvNxt + i) % TCP_BUFFER_SIZE] = seg->data[i];
         }
         c->rcvNxt   += seg->len;
         c->rcvCount += seg->len;
         dbg(TRANSPORT_CHANNEL, "conn=%hhu DATA seq=%hu len=%hhu accepted, stored=%hhu\n",
             id, (uint16_t) seg->seq, (uint8_t) seg->len, c->rcvCount);
      }
      // ALWAYS answer with the current cumulative ACK, even for discarded segments
      sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0);
   }

   // a FIN: accept it only if every earlier byte has arrived. Returns TRUE if it's new.
   bool acceptFin(uint8_t id, tcpSegment* seg){
      tcpConn* c;

      c = &conns[id];
      if(seg->seq == c->rcvNxt){
         c->rcvNxt++;                                       // the FIN uses one number
         sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0);
         return TRUE;
      }
      // a repeated FIN (our ACK was lost) or an early FIN (data missing): repeat our ACK
      dbg(TRANSPORT_CHANNEL, "conn=%hhu FIN seq=%hu not new (expected %hu), re-ACKing\n",
          id, (uint16_t) seg->seq, c->rcvNxt);
      sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0);
      return FALSE;
   }




   //  finishing a close 

   void enterTimeWait(uint8_t id){
      setState(id, TCP_TIME_WAIT);
      conns[id].retries = 0;
      conns[id].deadline = call tickTimer.getNow() + TCP_TIME_WAIT_MS;
   }

   void finishClose(uint8_t id){
      dbg(TRANSPORT_CHANNEL, "conn=%hhu closed cleanly, releasing record\n", id);
      setState(id, TCP_CLOSED);
      signal TCP.closed(id, SUCCESS);
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
      c->rcvRead = c->rcvNxt;
      c->peerWindow = seg->window;
      c->sndUna     = TCP_ISN_SERVER; // our SYN uses this number
      c->sndNxt     = TCP_ISN_SERVER + 1;
      c->sndEnd     = c->sndNxt;

      setState(id, TCP_SYN_RCVD);
      sendSegment(id, TCP_FLAG_SYN | TCP_FLAG_ACK, TCP_ISN_SERVER, NULL, 0);
      startTimer(id);
   }

   void handleSegment(uint8_t id, tcpSegment* seg){
      tcpConn* c;

      c = &conns[id];

      // handshake

      // client: waiting for a SYN-ACK that acknowledges our SYN
      if(c->state == TCP_SYN_SENT){
         if((seg->flags & TCP_FLAG_SYN) && (seg->flags & TCP_FLAG_ACK)
            && seg->ack == c->sndUna + 1){
            c->rcvNxt     = seg->seq + 1; // their SYN used one number
            c->rcvRead    = c->rcvNxt;
            c->sndUna     = seg->ack; // our SYN is acknowledged
            c->peerWindow = seg->window;
            stopTimer(id);
            setState(id, TCP_ESTABLISHED);
            sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0);
            signal TCP.connectDone(id, SUCCESS);
         } else{
            dbg(TRANSPORT_CHANNEL, "conn=%hhu unexpected segment in SYN_SENT, ignoring\n", id);
         }
         return;
      }

      // server: waiting for the final handshake ACK
      if(c->state == TCP_SYN_RCVD){
         if(seg->flags == TCP_FLAG_SYN){
            dbg(TRANSPORT_CHANNEL, "conn=%hhu duplicate SYN, resending SYN+ACK\n", id);
            sendSegment(id, TCP_FLAG_SYN | TCP_FLAG_ACK, c->sndUna, NULL, 0);
         } else if((seg->flags & TCP_FLAG_ACK) && seg->ack == c->sndUna + 1){
            c->sndUna     = seg->ack;
            c->peerWindow = seg->window;
            stopTimer(id);
            setState(id, TCP_ESTABLISHED);
            signal TCP.accepted(id);
         }
         // data arriving before setup finishes is ignored; the client will resend it
         return;
      }

      // after the handshake

      // a repeated SYN-ACK means our final handshake ACK was lost
      if((seg->flags & TCP_FLAG_SYN) && (seg->flags & TCP_FLAG_ACK)){
         dbg(TRANSPORT_CHANNEL, "conn=%hhu duplicate SYN+ACK, resending ACK\n", id);
         sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0);
         return;
      }

      handleAck(id, seg);

      if(seg->flags & TCP_FLAG_DATA){
         handleData(id, seg);
      }

      switch(c->state){
         case TCP_ESTABLISHED:
            if((seg->flags & TCP_FLAG_FIN) && acceptFin(id, seg)){
               // the other side is done. Our test server closes too,
               // but only after its app reads everything still buffered.
               setState(id, TCP_CLOSE_WAIT);
               c->closeAsked = TRUE;
            }
            break;

         case TCP_FIN_WAIT_1:
            if(c->sndUna == c->finSeq + 1) { // our FIN was ACKed
               setState(id, TCP_FIN_WAIT_2);
               stopTimer(id);
               startTimer(id); // bounded wait for their FIN
            }
            if((seg->flags & TCP_FLAG_FIN) && c->state == TCP_FIN_WAIT_2 && acceptFin(id, seg)) {
               enterTimeWait(id);
            }
            break;

         case TCP_FIN_WAIT_2:
            if((seg->flags & TCP_FLAG_FIN) && acceptFin(id, seg)) {
               enterTimeWait(id);
            }
            break;

         case TCP_LAST_ACK:
            if(c->sndUna == c->finSeq + 1) { // the final ACK
               finishClose(id);
               return;
            }
            if(seg->flags & TCP_FLAG_FIN) {
               acceptFin(id, seg); // repeated FIN: re-ACK it
            }
            break;

         case TCP_CLOSE_WAIT:
         case TCP_TIME_WAIT:
            if(seg->flags & TCP_FLAG_FIN) {
               acceptFin(id, seg);  // repeated FIN: re-ACK it
            }
            break;
      }

      trySend(id);
   }

   // what happens when a connection's timer runs out
   void onTimeout(uint8_t id){
      tcpConn* c;

      c = &conns[id];

      // the end of TIME_WAIT is the normal end of a close, not a failure
      if(c->state == TCP_TIME_WAIT){
         finishClose(id);
         return;
      }

      c->retries++;
      if(c->retries > TCP_MAX_RETRIES){
         dbg(TRANSPORT_CHANNEL, "conn=%hhu no answer after %d retries, giving up\n", id, TCP_MAX_RETRIES);
         failConn(id);
         return;
      }

      dbg(TRANSPORT_CHANNEL, "conn=%hhu TIMEOUT #%hhu in %s\n", id, c->retries, stateName(c->state));

      switch(c->state){
         case TCP_SYN_SENT:
            sendSegment(id, TCP_FLAG_SYN, c->sndUna, NULL, 0);
            break;
         case TCP_SYN_RCVD:
            sendSegment(id, TCP_FLAG_SYN | TCP_FLAG_ACK, c->sndUna, NULL, 0);
            break;
         case TCP_ESTABLISHED:
         case TCP_CLOSE_WAIT:
            if(c->sndNxt != c->sndUna) {
               dbg(TRANSPORT_CHANNEL, "conn=%hhu resending from seq %hu\n", id, c->sndUna);
               c->sndNxt = c->sndUna; // go back to the oldest unACKed byte
               trySend(id);
            }
            break;
         case TCP_FIN_WAIT_1:
         case TCP_LAST_ACK:
            sendSegment(id, TCP_FLAG_FIN, c->finSeq, NULL, 0);
            break;
         default:
            break; // FIN_WAIT_2: nothing to resend, just a bounded wait
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

   // queue bytes to send. Returns how many fit (may be fewer than len).
   command uint16_t TCP.write(uint8_t id, uint8_t* buf, uint16_t len){
      tcpConn* c;
      uint16_t space;
      uint16_t n;
      uint16_t i;

      if(id >= MAX_CONNECTIONS) {
         return 0;
      }
      c = &conns[id];
      if(c->state != TCP_ESTABLISHED || c->closeAsked) {
         return 0; // not connected yet, or closing: no new bytes
      }

      // stored bytes (sent-not-ACKed + queued) can never be more than 128
      space = TCP_BUFFER_SIZE - (uint16_t)(c->sndEnd - c->sndUna);
      n = (len < space) ? len : space;

      for(i = 0; i < n; i++){
         c->sendBuf[(c->sndEnd + i) % TCP_BUFFER_SIZE] = buf[i];
      }
      c->sndEnd += n;
      if(n > 0){
         trySend(id);
      }
      return n;
   }

   // take received bytes out of the buffer. Returns how many were read.
   command uint16_t TCP.read(uint8_t id, uint8_t* buf, uint16_t len){
      tcpConn* c;
      uint16_t n;
      uint16_t i;
      uint8_t freeBefore;

      if(id >= MAX_CONNECTIONS) {
         return 0;
      }
      c = &conns[id];
      if(c->state == TCP_CLOSED || c->state == TCP_LISTEN) {
         return 0;
      }

      n = (len < c->rcvCount) ? len : c->rcvCount;
      freeBefore = freeRecvSpace(id);
      for(i = 0; i < n; i++) {
         buf[i] = c->rcvBuf[(c->rcvRead + i) % TCP_BUFFER_SIZE];
      }
      c->rcvRead  += n;
      c->rcvCount -= n;

      // if our window was too small for the sender, tell it about the new space
      if(n > 0 && freeBefore < TCP_MAX_DATA && c->state == TCP_ESTABLISHED) {
         dbg(TRANSPORT_CHANNEL, "conn=%hhu window reopened to %hhu, sending update\n", id, freeRecvSpace(id));
         sendSegment(id, TCP_FLAG_ACK, c->sndNxt, NULL, 0);
      }
      if(n > 0){
         trySend(id);   // server in CLOSE_WAIT: once everything is read, send our FIN
      }
      return n;
   }

   // graceful close: no new bytes, send what's queued, then FIN
   command error_t TCP.close(uint8_t id){
      if(id >= MAX_CONNECTIONS){
         return FAIL;
      }
      if(conns[id].state != TCP_ESTABLISHED && conns[id].state != TCP_CLOSE_WAIT){
         return FAIL;
      }
      dbg(TRANSPORT_CHANNEL, "conn=%hhu close requested: FIN after queued data is ACKed\n", id);
      conns[id].closeAsked = TRUE;
      trySend(id); // sends the FIN right away if nothing is left
      return SUCCESS;
   }

   command int8_t TCP.findConn(uint8_t localPort, uint16_t remoteAddr, uint8_t remotePort){
      return findExact(localPort, remoteAddr, remotePort);
   }

}   
    


