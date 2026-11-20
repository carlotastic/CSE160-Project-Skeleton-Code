# CSE160 Project 3: Reliable Transport

## How to run
Run these inside the TinyOS Docker container, in the project folder:

```bash
make micaz sim                         # build (after changing any .nc or .h file)
python <testname>.py > test_output/<name>.txt
```

## What we added
- **Transport** (`TransportC.nc`, `TransportP.nc`, `TCP.nc`, `includes/tcp.h`): connections, handshake, sliding window, ACKs, retransmission, flow control, close
- **Node.nc**: the test app. The client writes bytes, the server reads and checks them
- **IP (IPP.nc)**: a test-only drop hook for the loss tests (off unless a test turns it on)
- **Commands**: test server, test client, client close, pause/resume consumer, drop rule
- Transport packets use `PROTOCOL_TCP` and go through our Project 2 IP routing. Transport never floods or touches the radio.

## Packet format and sizes
`TOSH_DATA_LENGTH = 28` bytes per packet (the AM header is outside this).

| Header | Fields | Size |
|---|---|---|
| IP (`pack`) | dest 2, src 2, seq 2, TTL 1, protocol 1 | 8 bytes |
| Transport (`tcpSegment`) | srcPort 1, destPort 1, flags 1, seq 2, ack 2, window 1, len 1 | 9 bytes |
| **Total overhead** | | **17 bytes** |
| **Data per segment** | | **11 bytes** |

- Flags are bits: SYN = 1, ACK = 2, FIN = 4, DATA = 8 (SYN-ACK = 3)
- Every segment carries the current ack number (next byte expected) and window (free receive space)
- `nx_` types, so byte order is fixed and there's no padding

## Constants
| Constant | Value | Why |
|---|---|---|
| Send / receive buffer | 128 bytes each, per connection | spec |
| `MAX_CONNECTIONS` | 4 per node | listener + at least 2 connections + 1 spare |
| `TCP_SEND_WINDOW` | 44 bytes (4 full segments) | more than 1 in flight without flooding the radio queues |
| `TCP_RTO_MS` | 3000 (≈2.93 s, TinyOS ms are 1/1024 s) | a 3-hop round trip can take over 1 s |
| `TCP_MAX_RETRIES` | 8 in a row | then fail and free the record (~24 s) |
| `TCP_TICK_MS` | 250 | one timer checks every connection's deadline |
| `TCP_TIME_WAIT_MS` | 12000 (≈11.7 s) | longer than 3 FIN retries (3 × 3 s) |
| Starting seq numbers | client 100, server 500 | fixed |
| Sequence numbers | 16-bit, **no wraparound** | transfers up to 60,000 bytes are supported |

## How it works (short)
- **Handshake:** SYN → SYN-ACK → ACK. SYN and FIN each use one sequence number. A repeated SYN finds the existing record, so it never makes a second connection.
- **Sending:** sliding window. The sender keeps sending while bytes in flight < the smaller of 44 and the receiver's window.
- **Receiving:** only keeps the next in-order segment. Anything else is discarded. Every data segment gets an ACK, even discarded ones. ACKs are cumulative.
- **Timeout:** Go-Back-N. Resend everything from the oldest unACKed byte.
- **Flow control:** when the window is 0, the sender stops and sends a 1-byte probe every timeout. When the app reads and frees space, the receiver sends a window update. If that update is lost, the next probe finds the open window.
- **Failure:** any valid ACK resets the retry count (the peer is alive). 8 timeouts in a row with no answer means failure, and the record is freed.
- **Close:** the client sends FIN only after all its data is ACKed. The server sends its FIN only after its app has read everything. The client waits in TIME_WAIT (~12 s) so it can re-ACK a repeated FIN.

## Test commands (Python, in TestSim.py)
| Function | What it does |
|---|---|
| `cmdTestServer(serverAddress, listenPort)` | server listens on that port |
| `cmdTestClient(clientAddress, serverAddress, srcPort, destPort, transferBytes)` | client connects, then sends that many bytes and closes |
| `cmdClientClose(clientAddress, serverAddress, srcPort, destPort)` | graceful close of that connection |
| `pauseConsumer(node)` / `resumeConsumer(node)` | **test only:** stop/start reading on every server connection at that node |
| `setDrop(node, flags, value, src=0, count=1)` | **test only:** at a middle node, drop the next matching TCP packet. `value` = seq (DATA/SYN/FIN) or ack (pure ACK). `flags=128` = a window-reopening ACK |
| `runSeconds(s)` | run for s **simulated** seconds |
| `linkOff(a,b)` / `linkOn(a,b)` | cut / restore a link |

**Test data:** byte k = k mod 256. The server checks every byte it reads. We count bytes **accepted** (client transport took them), **acknowledged**, and **consumed** (server app read them) separately.

**Debug channels:** `transport` = state changes, timeouts, resends, discards, test results. `tcpdetail` = every segment sent and received (turn on when needed).

**Note:** `TestSim` reuses one packet object for commands, so two commands sent in the same tick overwrite each other. Our scripts wait 1 s between commands.

## Tests
All on `line4.topo` (1-2-3-4, both directions, gain -54), `no_noise.txt` unless noted, seed 1. Each waits 60 s for routing and pings 1 → 4 first.

| Test | Command | Output |
|---|---|---|
| 1 Baseline | `python p3Baseline.py` | `p3_test1_baseline.txt` |
| 2 Data loss | `python p3DataLoss.py` | `p3_test2_dataloss.txt` |
| 3 ACK loss | `python p3AckLoss.py` | `p3_test3_ackloss.txt` |
| 4 Flow control | `python p3FlowControl.py` | `p3_test4_flowcontrol.txt` |
| 5 Control loss | `python p3ControlLoss.py syn` (also `synack`, `ack`, `closeack`) | `p3_test5_<case>.txt` |
| 6 Failure | `python p3Failure.py` | `p3_test6_failure.txt` |
| Noisy | `python p3Noisy.py` (`meyer-heavy.txt`) | `p3_noisy.txt` |
| Two connections | `python p3TwoConn.py` | `p3_twoconn.txt` |

### 1. Baseline
1030 bytes from 1:10 to 4:20 (1030 = 93 × 11 + 7, so the last segment is short). Up to 4 segments in flight:
```
DATA_TX seq=101 len=11 outstanding=11
DATA_TX seq=112 len=11 outstanding=22
DATA_TX seq=123 len=11 outstanding=33
DATA_TX seq=134 len=11 outstanding=44
Test server: conn=1 read 7 bytes [255..5], total 1030, mismatches 0
Test server: conn=1 closed OK, consumed 1030 bytes, 0 mismatches
```
Some segments were lost to radio collisions even with no noise (sending several at once on a line). Go-Back-N resent them, and the result was still exact.

### 2. Data loss
Node 2 drops the DATA segment with seq 134. Node 4 discards what comes after the gap and its ACK stays at 134. Node 1 times out and resends from 134.
```
TEST DROP at node 2: discarding TCP from 1 to 4 flags=8 seq=134
conn=1 DATA seq=145 but expected 134: discarding
TX ACK seq=501 ack=134 ...
conn=0 TIMEOUT #1 in ESTABLISHED / resending from seq 134
consumed 300 bytes, 0 mismatches
```

### 3. ACK loss
Node 3 drops the ACK with ack 145. The next ACK (156) covers it, so no timeout is needed.
```
TEST DROP at node 3: discarding TCP from 4 to 1 flags=2 ack=145
conn=0 ACK 156 accepted
consumed 300 bytes, 0 mismatches
```

### 4. Flow control
The consumer is paused, so the 128-byte buffer fills (ack 229 = 101 + 128) and the window goes to 0. The sender stops and probes every ~3 s. After resuming, node 3 drops the first window update. The next probe finds the open window and the transfer finishes.
```
TX ACK ... ack=229 ... wnd=0
peer window is 0: no new data, probe timer started
ZERO WINDOW: sending 1-byte probe seq=229
DATA seq=229 len=1 doesn't fit (free 0): discarding
consumer RESUMED / window reopened to 64, sending update
TEST DROP at node 3: ... ack=229
consumed 400 bytes, 0 mismatches
```

### 5. Control loss (4 separate runs)
| Case | Dropped | What happens |
|---|---|---|
| syn | SYN (seq 100) at node 2 | client times out and resends the SYN |
| synack | SYN-ACK (seq 500) at node 3 | server gets a duplicate SYN and resends the SYN-ACK, no new record |
| ack | final handshake ACK (ack 501) at node 2 | server resends SYN-ACK, client re-ACKs it |
| closeack | final close ACK (ack 502) at node 2 | server resends FIN, client (in TIME_WAIT) re-ACKs it, both close |

In every run node 4 allocates only one connection record, and the transfer ends with 0 mismatches.

### 6. Failure
- Port 99 (no listener): 8 timeouts, then `FAILED to connect` and the record is freed
- Node 9 (no route): `send failed (no route …)` on each try, 8 timeouts, `FAILED to connect`
- A normal connection right after gets record 0 again, so the records were really freed
- Node 4 turned off mid-transfer: 8 timeouts, `closed FAILED, 282 of 1000 bytes accepted`

### Noisy run
`meyer-heavy.txt` noise: several timeouts and resends, still `consumed 1030 bytes, 0 mismatches`.

### Two connections
Nodes 1 and 2 both send 500 bytes to 4:20 at the same time. Node 4 keeps the listener on conn 0 and gives them conn 1 and conn 2. Both finish with 0 mismatches and close independently.