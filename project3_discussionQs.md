# Project 3 Discussion Questions:

### 1. What are the tradeoffs between fixed and varying initial sequence numbers? How could delayed segments from an earlier connection interfere with a new instance of the same tuple?
- We used fixed starting numbers (client 100, server 500). It's simple, and the logs are easy to read and the same every run.
- The downside: if a connection closes and a new one opens with the exact same ports and addresses, both use the same sequence numbers. A delayed segment from the old connection (for example DATA seq=145 still floating around) could arrive at the new connection right when it's expecting 145, and the receiver would accept old data as new.
- Varying starting numbers (random, or based on a clock) make it very unlikely that an old segment's number lands where the new connection is expecting. The cost is that they're harder to debug.
- What protects us: TIME_WAIT keeps the old connection around for ~12 s, and the TTL limits how long any packet can survive. In our tests each new connection also uses a different client port, so the tuple is never reused right away.

### 2. For the required 128-byte receive buffer, how does the advertised window change as data arrives and the application consumes it? What determines a useful buffer size if the fixed limit were relaxed?
- The window is 128 minus the bytes stored but not read yet. It goes down when data arrives and back up when the app reads.
- Example from our tests: after one 11-byte segment arrived, the ACK said wnd=117. In the flow-control test the app was paused, so the buffer filled up and the ACK said ack=229, wnd=0 (101 + 128 = 229). After resuming, the app read 64 bytes, so the window went back up to 64.
- A useful size depends on how fast the app reads and how much data can be "in the air" during one round trip (sending rate × round trip time). It needs to be big enough that the sender doesn't have to stop while waiting for ACKs. Making it bigger than that just wastes memory, which matters on a small sensor node.

### 3. What happens when a data segment arrives twice because its ACK was lost? Explain how the receiver prevents duplicate delivery while helping the sender make progress.
- If the ACK is lost, the sender times out and resends the segment, so the receiver gets it a second time.
- The receiver only keeps a segment if its seq is exactly the next byte it expects (`rcvNxt`). The duplicate has a lower seq, so it's thrown away ("discarding (duplicate or out of order)") and never reaches the app.
- It still sends an ACK with its current cumulative number, so the sender learns those bytes already arrived and moves on.
- Often a resend isn't even needed. In our ACK-loss test the ACK for 145 was dropped, but the next ACK (156) covered it, so the sender kept going with no timeout.

### 4. Why must a receiver advertise newly available space after its application reads data? What happens if that update is lost, and how does your implementation recover?
- When the window is 0, the sender stops sending. If the receiver didn't announce the free space after its app reads, the sender would never find out and the transfer would stall.
- When our app reads and the window was smaller than one segment, the receiver sends a window update.
- If that update is lost, the sender would wait forever, so while the window is 0 our sender sends a 1-byte probe every ~3 s. The receiver answers every probe with its current window. If it has room now, it keeps the byte and the sender starts sending again.
- In our flow-control test we dropped the first window update on purpose, and the probe found the open window and the transfer finished with 0 mismatches.
- A zero window isn't a failure: every answer to a probe resets the retry count, so the connection stays open as long as the receiver keeps answering.

### 5. How could repeated incomplete connection handshakes exhaust your static connection table? Describe your current timeout policy and one possible improvement.
- Every SYN that reaches a listener creates a new record in SYN_RCVD. We only have 4 records per node, and one is the listener. If clients keep sending SYNs and never finish the handshake, these half-open records fill the table, and real clients can't connect.
- Our current policy: a SYN_RCVD record resends its SYN-ACK every ~3 s, up to 8 times (~26 s), then it's freed. If the table is full, new SYNs are ignored and the client has to retry.
- One improvement: give half-open records a much shorter limit (for example 2 tries) or a maximum number per listener. Another is SYN cookies, where the server doesn't create a record at all until the final ACK arrives. The limitation is that a shorter limit could drop a real client on a slow, lossy path.

### 6. What happens if a peer establishes a connection and remains idle indefinitely? Discuss the tradeoff between reclaiming resources and preserving a legitimate long-lived connection.
- In our design an idle connection with nothing in flight has no timer running, so it stays open forever and keeps its record. If the other side died, we wouldn't notice until we tried to send something and hit 8 timeouts.
- If we closed idle connections after some time, we'd get the memory back. But a real connection that's just quiet (like a chat in Project 4 where nobody types for a while) would get cut off.
- A middle ground is keepalive: after a long idle time, send a small probe, and only close the connection if the other side doesn't answer after several tries. That keeps quiet but alive connections and frees ones whose peer is gone. The cost is some extra traffic, and choosing how long to wait is a tradeoff between saving memory and false alarms.