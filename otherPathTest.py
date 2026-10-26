from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("ex5.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)

    print "=== Phase 1: startup, wait 60s. Expect 1->4 via 2, cost 2 ==="
    s.runSeconds(60)
    s.routeDMP(1)
    s.runSeconds(1)
    s.ping(1, 4, "before")
    s.runSeconds(5)

    print "=== Phase 2: remove link 2-4 (node 2 stays on), wait 90s. Expect 1->4 via 3, cost 3 ==="
    s.linkOff(2, 4)
    s.runSeconds(90)
    s.routeDMP(1)
    s.runSeconds(1)
    s.ping(1, 4, "after")
    s.runSeconds(5)

    print "=== Phase 3: restore link 2-4, wait 60s. Expect 1->4 via 2, cost 2 again ==="
    s.linkOn(2, 4)
    s.runSeconds(60)
    s.routeDMP(1)
    s.runSeconds(1)
    s.ping(1, 4, "restored")
    s.runSeconds(5)

if __name__ == '__main__':
    main()