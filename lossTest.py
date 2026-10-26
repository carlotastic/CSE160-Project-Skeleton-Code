from TestSim import TestSim

LINKS = [(1, 2), (2, 3), (3, 4)]

# send n pings from 1 to 4, 10 seconds apart
def pingBurst(s, n, label):
    print "=== %s: %d pings 1->4, 10s apart ===" % (label, n)
    for i in range(n):
        s.ping(1, 4, "p%d" % i)
        s.runSeconds(10)

def dumpEnds(s):
    s.routeDMP(1)
    s.runSeconds(1)
    s.routeDMP(4)
    s.runSeconds(1)

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4_weak.topo")
    s.loadNoise("meyer-heavy.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)
    s.addChannel(s.NEIGHBOR_CHANNEL)   # shows neighbors being dropped/re-added under loss

    print "=== Phase 1: lossy links (gain -75, meyer-heavy noise), run 120s ==="
    s.runSeconds(120)
    dumpEnds(s)

    pingBurst(s, 10, "Phase 2 (lossy)")

    print "=== Phase 3: links become good again (gain -54), wait 60s ==="
    for (a, b) in LINKS:
        s.linkOn(a, b, -54.0)
    s.runSeconds(60)
    dumpEnds(s)

    pingBurst(s, 10, "Phase 4 (recovered)")

if __name__ == '__main__':
    main()
