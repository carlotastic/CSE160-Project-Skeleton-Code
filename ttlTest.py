from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)
    s.addChannel(s.FLOODING_CHANNEL) # must stay silent

    print "=== Phase 1: converge (60s). Path 1->4 is 3 hops ==="
    s.runSeconds(60)

    print "=== Phase 2: TTL 2 < 3 hops. Expect drop at node 3, NO reply ==="
    s.pingTTL(1, 4, 2, "short")
    s.runSeconds(10)

    print "=== Phase 3: TTL 3 = 3 hops. Expect it to arrive (TTL H allows H links) ==="
    s.pingTTL(1, 4, 3, "exact")
    s.runSeconds(10)

if __name__ == '__main__':
    main()