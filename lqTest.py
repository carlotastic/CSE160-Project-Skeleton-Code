import sys
from TestSim import TestSim

def dumpEnds(s):
    s.routeDMP(1)
    s.runSeconds(1)
    s.routeDMP(4)
    s.runSeconds(1)

def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    s = TestSim()
    s.t.randomSeed(seed)   # same seed = same noise = reproducible run
    print "=== seed %d ===" % seed
    s.runTime(1)

    s.loadTopo("lq.topo")
    s.loadNoise("meyer-heavy.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)
    s.addChannel(s.NEIGHBOR_CHANNEL)   # shows "Link cost to X" measurements

    # 16 ND rounds (~165s) to fill the window + 3 rounds to confirm + DV convergence
    print "=== Phase 1: converge and measure links (300s) ==="
    s.runSeconds(300)
    dumpEnds(s)

    print "=== Phase 2: 50 pings 1->4, 5s apart ==="
    for i in range(50):
        s.ping(1, 4, "q%d" % i)
        s.runSeconds(5)

    print "=== Phase 3: final tables ==="
    dumpEnds(s)

if __name__ == '__main__':
    main()