#! /usr/bin/python
# Flooding test driver for CSE 160 Project 1 (Receive and Rebroadcast).
#
# Run one scenario per invocation:
#     python2 floodTest.py baseline
#     python2 floodTest.py multihop
#     python2 floodTest.py cycle
#     python2 floodTest.py ttl
#     python2 floodTest.py unreachable
#     python2 floodTest.py selfping
#     python2 floodTest.py concurrent
#
# With no argument it runs 'multihop'. Run `python2 floodTest.py list` to see
# the scenarios with their descriptions.
#
# One scenario per process on purpose: TestSim.moteids is a CLASS attribute,
# so it is shared and never cleared between TestSim() instances. Building two
# topologies in a single process leaves stale mote IDs in the list and the
# second run behaves strangely. Separate processes keep each run clean.

import sys
from TestSim import TestSim


def setup(topo, channels):
    """Boot a network and enable debug channels. Returns the TestSim."""
    s = TestSim()

    # Let the simulator settle before anything is powered on.
    s.runTime(1)

    s.loadTopo(topo)
    s.loadNoise("no_noise.txt")
    s.bootAll()

    for c in channels:
        s.addChannel(c)

    # Motes boot at 1333*nodeID, so a 19-mote topology needs ~25s of sim time
    # before the last one is up. Give everything room before the first ping.
    s.runTime(30)
    return s


def banner(text):
    print
    print "=" * 70
    print "  " + text
    print "=" * 70
    print


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

def baseline():
    """Step 1: pre-flooding baseline. 2->3 should work, 1->10 should not."""
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL])

    banner("2 -> 3 (adjacent, should work even before flooding)")
    s.ping(2, 3, "Hello, World")
    s.runTime(10)

    banner("1 -> 10 (9 hops, silent until forwarding exists)")
    s.ping(1, 10, "Hi!")
    s.runTime(20)


def multihop():
    """Steps 3-5: the main event. 1->10 over a 19-mote line, 9 hops each way."""
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 10 over long_line (9 hops; expect a PINGREPLY back at node 1)")
    s.ping(1, 10, "Hi!")
    s.runTime(40)


def cycle():
    """Step 4: the topology that punishes missing duplicate suppression.

    example.topo is a 9-mote mesh full of cycles (1-2-3-1, 4-5-7-8-4).
    1 -> 9 is about 4 hops (1-3-4-8-9). Without a seen-packet cache this
    produces a transmission storm; with one it should be nearly silent.
    """
    s = setup("example.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 9 across a cyclic mesh (count the forwards!)")
    s.ping(1, 9, "cycles")
    s.runTime(40)


def ttl():
    """Step 6: TTL exhaustion. 1->19 needs 18 hops; MAX_TTL is 15."""
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 19 (18 hops vs MAX_TTL=15; packet must die in transit)")
    print "Expect: TTL-drop messages around nodes 15-16, no delivery at 19,"
    print "        and no PINGREPLY at node 1."
    s.ping(1, 19, "too far")
    s.runTime(40)


def unreachable():
    """Step 6: no path at all. Flood must die out cleanly, not spin."""
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("Cutting the line: powering off mote 8")
    s.moteOff(8)
    s.runTime(5)

    banner("1 -> 12 with the chain severed at 8 (expect a clean die-out)")
    s.ping(1, 12, "no path")
    s.runTime(40)


def selfping():
    """Step 6: node pinging itself. Should not wedge or storm."""
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 1 (self-ping; decide deliberately what this should do)")
    s.ping(1, 1, "me")
    s.runTime(20)


def concurrent():
    """Step 6: two floods in flight at once, from different sources.

    Different src keys, so a per-source sequence cache should handle both
    independently. If one ping kills the other, the cache is keyed wrong.
    """
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 8 and 15 -> 5 back to back (both must complete)")
    s.ping(1, 8, "first")
    s.ping(15, 5, "second")
    s.runTime(40)


SCENARIOS = [
    ("baseline",    baseline,    "Step 1: pre-flooding sanity check"),
    ("multihop",    multihop,    "Steps 3-5: 1->10 multi-hop ping and reply"),
    ("cycle",       cycle,       "Step 4: cyclic mesh, duplicate suppression"),
    ("ttl",         ttl,         "Step 6: TTL exhaustion at 18 hops"),
    ("unreachable", unreachable, "Step 6: severed chain, clean die-out"),
    ("selfping",    selfping,    "Step 6: node pings itself"),
    ("concurrent",  concurrent,  "Step 6: two simultaneous floods"),
]


def usage():
    print "Usage: python2 floodTest.py [scenario]"
    print
    print "Scenarios:"
    for name, _, desc in SCENARIOS:
        print "  %-12s %s" % (name, desc)
    print
    print "Default: multihop"


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "multihop"

    if name in ("list", "help", "-h", "--help"):
        usage()
        return

    for scenario, fn, _ in SCENARIOS:
        if scenario == name:
            fn()
            return

    print "Unknown scenario: %s" % name
    print
    usage()
    sys.exit(1)


if __name__ == '__main__':
    main()
