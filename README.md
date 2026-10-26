# CSE160 Project 2: Distance-Vector Routing

## How to run
Run these inside the TinyOS Docker container, in the project folder:

```bash
make micaz sim          # build (do this after changing any .nc or .h file)
python <testname>.py    # run a test
```
To save a test's output: `python <testname>.py > test_output/<name>.txt`

## What we added
- **DistanceVector** (`DistanceVectorC/P.nc`): keeps the routing table and sends our table to our neighbors
- **IP** (`IPC/P.nc`): sends packets to the next hop using the routing table
- **dv.h**: our constants and the advertisement packet format
- **LinkLayer**: we added two new AM types (DV = 11, IP = 12) so DV and IP packets don't get mixed up with flooding
- **Neighbor Discovery**: now tells DV when a neighbor is added or lost
- **Node.nc**: ping now uses IP instead of flooding
- **TestSim.py**: added `runSeconds()`, `linkOff()`, `linkOn()`, and `pingTTL()` for our tests

## Constants
- INFINITY = 16 (means unreachable)
- Routing table holds 32 routes
- 9 routes fit in one advertisement packet
- Advertisements every 5 seconds (+ a random bit)
- A route expires if it isn't refreshed for 6 rounds (~30 s)
- Dead routes are advertised as 16 for 6 rounds, then deleted
- TTL starts at 15
- Neighbor discovery runs every 10 seconds. A neighbor is dropped after ~40 s with no reply.
- Up to 20 neighbors, node IDs 1–255
- `USE_LQ_METRIC` in `dv.h` should be **0** (1 is only for extra credit)

## Test setup
- **Boot order:** `bootAll()` turns on node N at 1333 × N ticks, so all nodes boot within the first fraction of a second, in order of their ID
- **Links:** every topology file lists both directions of each link (for example `1 2` and `2 1`)
- **Noise:** all tests use `no_noise.txt` except the loss test, which uses `meyer-heavy.txt`
- **Times:** all waits use `runSeconds()`, so they are real simulated seconds

## Why we wait the times we do
- **60 s after boot:** neighbor discovery takes ~10 s, then routes spread about one hop every 6 s
- **90 s after cutting a link:** it takes ~40 s to notice a dead neighbor, then a bit longer for the news to spread
- **60 s after fixing a link:** the neighbor is found again in ~10 s, then routes update
- **120 s for the 12-node line:** it's 11 hops, so it takes longer to spread

## Tests
| Test | Command | Topology | Output file |
|---|---|---|---|
| Line | `python pingRouteTest.py` | `line4.topo` | `line_test.txt` |
| Alternative path | `python otherPathTest.py` | `ex5.topo` | `otherpath_test.txt` |
| Partition | `python partitionTest.py` | `line4.topo` | `partition_test.txt` |
| Poison reverse | `python poisonTest.py` | `line4.topo` | `poison_test.txt` |
| Packet capacity | `python capacityTest.py` | `line12.topo` | `capacity_test.txt` |
| TTL | `python ttlTest.py` | `line4.topo` | `ttl_test.txt` |
| Loss | `python lossTest.py` | `line4_weak.topo` | `loss_test.txt` |

All output files are in `test_output/`.

### Line (1-2-3-4)
Node 1 reaches 4 through 2 at cost 3, and node 4 reaches 1 through 3 at cost 3. The ping goes 1→2→3→4 and the reply comes back, with no flooding.
```
DEBUG (1): 4	2	3	VALID
DEBUG (4): 1	3	3	VALID
DEBUG (1): Routing Packet - src: 1, dest: 4, seq: 1, next hop: 2, cost: 3
DEBUG (4): PING from 1 arrived. Payload: hello
DEBUG (1): PINGREPLY from 4 arrived
```

### Alternative path (1-2, 2-4, 1-3, 3-5, 5-4)
We cut link 2-4 (node 2 stays on), then put it back. Node 1's route to 4 went from cost 2 (through 2), to cost 3 (through 3), then back to cost 2. The ping worked every time.
```
DEBUG (1): 4	2	2	VALID     (before)
DEBUG (1): 4	3	3	VALID     (after cut)
DEBUG (1): 4	2	2	VALID     (after fix)
```

### Partition (1-2-3-4, cut 2-3)
Nodes 3 and 4 became unreachable, and the ping was dropped instead of flooded. Everything came back after we fixed the link.
```
DEBUG (1): 3	-	INF	WITHDRAWN
DEBUG (1): 4	-	INF	WITHDRAWN
DEBUG (1): No route to 4, dropping (src 1, seq 1)
DEBUG (1): PINGREPLY from 4 arrived     (after fixing the link)
```

### Poison reverse (1-2-3-4)
Node 2 reaches 4 through 3, so it tells 3 "16" and tells 1 the real cost. When we cut 3-4, node 3 did not try to go through node 2. It just marked 4 as unreachable.
```
DEBUG (2): Adv to 1: dest 4 cost 2
DEBUG (2): Adv to 3: dest 4 cost 16
DEBUG (3): Route withdrawn: dest 4 now unreachable
```

### Packet capacity (12-node line)
Each table has 12 routes, so it gets split into 2 packets (9 + 3). Node 1 still learned about node 12 and pinged it across 11 hops.
```
DEBUG (1): Sent DV packet to 2 with 9 entries
DEBUG (1): Sent DV packet to 2 with 3 entries
DEBUG (1): 12	2	11	VALID
DEBUG (1): PINGREPLY from 12 arrived
```

### TTL (1-2-3-4)
A ping with TTL 2 died at node 3 with no reply. A ping with TTL 3 made it.
```
DEBUG (3): TTL expired, dropping (src 1, dest 4, seq 1)
DEBUG (4): PING from 1 arrived. Payload: exact
```

### Loss (1-2-3-4, weak links + meyer-heavy noise)
We used weak links (gain -75) and the `meyer-heavy.txt` noise file, then made the links strong halfway through with `linkOn`.
- Weak links: 9/10 pings came back. Lost replies made neighbors get dropped 3 times, but each one came back on its own (for example node 3 dropped node 2 at 1:42.89 and re-added it at 1:43.19, 0.3 s later), and the routes recovered every time.
- Strong links: 8/10 pings came back. The 2 lost pings were dropped by noise, not because of routing (the tables were correct).
```
DEBUG (3): Neighbor 2 dropped (no reply in 3 rounds)
DEBUG (3): New neighbor: 2
```

## Extra credit
See `extra_credit.pdf`. To try it, set `USE_LQ_METRIC` to 1 in `dv.h`, then:
```bash
make micaz sim
python lqTest.py 1     # 1 = random seed, so runs can be repeated
```
Set it back to 0 afterward!