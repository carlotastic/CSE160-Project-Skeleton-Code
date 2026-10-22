import sys
from TestSim import TestSim

# run with: python2 floodTest.py [scenario]
# no scenario = multihop, "list" shows all of them


# boots every node in the topology and turns on the debug channels we want to see
def setup(topo, channels):
    s = TestSim()

    # let the simulator settle before anything turns on
    s.runTime(1)

    s.loadTopo(topo)
    s.loadNoise("no_noise.txt")
    s.bootAll()

    for c in channels:
        s.addChannel(c)

    # give room before first ping (lets neighbor discovery run a few rounds)
    s.runTime(30)
    return s


# prints a banner to help separate sections
def banner(text):
    print
    print "=" * 70
    print "  " + text
    print "=" * 70
    print


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

# 2 -> 3 are neighbors so it should always work.
# 1 -> 10 only works once flooding forwards packets.
# FLOODING_CHANNEL is off here so the output stays short
def baseline():
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL])

    banner("2 -> 3 (adjacent, should work even before flooding)")
    s.ping(2, 3, "Hello, World")
    s.runTime(10)

    banner("1 -> 10 (9 hops, silent until forwarding exists)")
    s.ping(1, 10, "Hi!")
    s.runTime(20)


# main test. 1 -> 10 on a straight line, 9 hops there and 9 back.
# should see PING arrive at 10 and PINGREPLY arrive at 1
def multihop():
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 10 over long_line (9 hops; expect a PINGREPLY back at node 1)")
    s.ping(1, 10, "Hi!")
    s.runTime(40)


# tests the duplicate cache. (1-2-3-1, 4-5-7-8-4),
# so without SeenMap packets would circle forever.
# should see lots of "Duplicate, dropping" and each node forwarding only once
def cycle():
    s = setup("example.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 9 across a cyclic mesh (count the forwards!)")
    s.ping(1, 9, "cycles")
    s.runTime(40)


# tests TTL. 1 -> 19 is 18 hops but MAX_TTL is 15,
# so the packet should die partway and never reach 19
def ttl():
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 19 (18 hops vs MAX_TTL=15; packet must die in transit)")
    print "Expect: TTL-drop messages around nodes 15-16, no delivery at 19,"
    print "        and no PINGREPLY at node 1."
    s.ping(1, 19, "too far")
    s.runTime(40)


# turns off node 8 so there's no path from 1 to 12.
# the flood should just stop at node 7, no loops or crashes
def unreachable():
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("Cutting the line: powering off mote 8")
    s.moteOff(8)
    s.runTime(5)

    banner("1 -> 12 with the chain severed at 8 (expect a clean die-out)")
    s.ping(1, 12, "no path")
    s.runTime(40)


# node pings itself. Node.nc handles this locally,
# so should see "Ping to self, delivered locally" and nothing sent
def selfping():
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 1 (self-ping; decide deliberately what this should do)")
    s.ping(1, 1, "me")
    s.runTime(20)


# two floods at the same time from different sources.
# SeenMap is keyed by src, so both should get through.
# if one blocks the other, the cache is keyed wrong
def concurrent():
    s = setup("long_line.topo",
              [TestSim.COMMAND_CHANNEL, TestSim.GENERAL_CHANNEL,
               TestSim.FLOODING_CHANNEL])

    banner("1 -> 8 and 15 -> 5 back to back (both must complete)")
    s.ping(1, 8, "first")
    s.runTime(1)
    s.ping(15, 5, "second")
    s.runTime(40)


# name you type, function it runs, description shown in usage()
SCENARIOS = [
    ("baseline",    baseline,    "Step 1: pre-flooding sanity check"),
    ("multihop",    multihop,    "Steps 3-5: 1->10 multi-hop ping and reply"),
    ("cycle",       cycle,       "Step 4: cyclic mesh, duplicate suppression"),
    ("ttl",         ttl,         "Step 6: TTL exhaustion at 18 hops"),
    ("unreachable", unreachable, "Step 6: severed chain, clean die-out"),
    ("selfping",    selfping,    "Step 6: node pings itself"),
    ("concurrent",  concurrent,  "Step 6: two simultaneous floods"),
]


# prints the list of scenarios
def usage():
    print "Usage: python2 floodTest.py [scenario]"
    print
    print "Scenarios:"
    for name, _, desc in SCENARIOS:
        print "  %-12s %s" % (name, desc)
    print
    print "Default: multihop"


# picks the scenario from the command line and runs it
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
