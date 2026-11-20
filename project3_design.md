<style>body { font-size: 11.5px; line-height: 1.3; } h1 { font-size: 20px; margin: 0 0 6px; } h2 { font-size: 14px; margin: 8px 0 2px; border: none; } ul { margin: 2px 0; padding-left: 18px; } pre { margin: 4px 0; padding: 6px; } p { margin: 2px 0; }</style>

# Project 3 Design: Reliable Transport

## Overview:
- Transport sits on top of our Project 2 routing. It sends every segment with `IP.send(dest, PROTOCOL_TCP, ...)`, so it never floods or touches the radio. Every resend is a new IP packet, so it uses the current route and a fresh TTL.
```
   Node.nc (test client + server)  →  Transport  →  IP  →  DistanceVector / ND  →  LinkLayer
```

## Connection state:
- Each node has a fixed table of 4 connection records (no dynamic memory). A record is matched by all four values: our address, our port, their address, their port.
- The listener is its own record and stays in LISTEN. Each SYN that reaches it makes a **new** record, so a node can have several connections on the same port. A repeated SYN finds the existing record and doesn't make a second one.
- Each record has: state, ports/address, a 128-byte send buffer with `sndUna` (oldest unACKed), `sndNxt` (next to send) and `sndEnd` (end of what the app wrote), a 128-byte receive buffer with `rcvNxt` (next expected) and `rcvCount` (bytes waiting for the app), and a timer (`deadline`, `retries`).
- Byte number s is stored at `buffer[s % 128]`, so a small buffer can carry a big transfer.
- States: CLOSED, LISTEN, SYN_SENT, SYN_RCVD, ESTABLISHED, FIN_WAIT_1, FIN_WAIT_2, CLOSE_WAIT, LAST_ACK, TIME_WAIT.

## Packet format:
- 28-byte packet = 8-byte IP header + 9-byte transport header + **11 bytes of data**.
- Transport header: srcPort 1, destPort 1, flags 1 (SYN/ACK/FIN/DATA bits), seq 2, ack 2, window 1, len 1.
- Every segment carries the next byte we expect (ack) and our free space (window). Length is checked before reading any data.
- Sequence numbers are 16-bit with no wraparound: client starts at 100, server at 500. SYN and FIN each use one number. Transfers up to 60,000 bytes.

## ACKs and retransmission:
- The receiver only keeps the exact next segment it expects. Duplicates and out-of-order segments are thrown away, so the app never gets a byte twice. Every data segment gets an ACK, even discarded ones.
- ACKs are cumulative ("I have everything before N"), so one ACK can cover several segments and a lost ACK is covered by the next one.
- One 250 ms timer checks every record. If the oldest unACKed data isn't ACKed in ~3 s, we resend everything from `sndUna` (Go-Back-N). SYN, SYN-ACK and FIN are resent the same way.
- Any valid ACK resets the retry count. 8 timeouts in a row with no answer means failure: the app is told and the record is freed.

## Sender and receiver windows:
- The sender keeps sending while bytes in flight < the smaller of our fixed window (44 bytes = 4 segments) and the receiver's window. A segment can be shorter than 11 if only a little room is left.
- The receiver advertises 128 minus the bytes waiting for the app. Window 0 means stop sending new data (it's not a failure).
- While the window is 0, the sender sends a 1-byte probe every timeout. When the app reads and frees space, the receiver sends a window update. If that update is lost, the next probe finds the open window.

## Cleanup:
- The client sends FIN only after all its data is ACKed. The server sends its FIN only after its app has read everything, so unread data is never thrown away.
- The client stays in TIME_WAIT for ~12 s (longer than 3 FIN retries) so it can re-ACK a repeated FIN if its last ACK was lost. The server frees its record as soon as the final ACK arrives.
- Closing one connection never touches the listener or other records.

## Preparing for Project 4:
- Our `TCP` interface (listen, connect, write, read, close, plus connectDone / accepted / closed events) already matches the socket operations. In Project 4 a socket number can just be the record's index, and `Transport.nc` can wrap these calls.
- `write` already returns how many bytes fit, and `read` returns whatever is available, which is exactly the socket write/read behavior.
- Records already work independently (our two-connection test), which Project 4's overlapping connections need.