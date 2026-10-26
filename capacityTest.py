from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line12.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)

    # 11 hops x ~6s per DV round + ~10s for ND = ~76s. Wait 120s to be safe.
    print "=== Phase 1: converge (120s) ==="
    s.runSeconds(120)

    print "=== Phase 2: one round of advertisements, showing packet sizes ==="
    s.addChannel("dvadv")
    s.runSeconds(7)

    print "=== Phase 3: tables + end-to-end ping ==="
    s.routeDMP(1)
    s.runSeconds(1)
    s.routeDMP(12)
    s.runSeconds(1)
    s.ping(1, 12, "far")
    s.runSeconds(10)

if __name__ == '__main__':
    main()