from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)

    print "=== Phase 1: converge (60s) ==="
    s.runSeconds(60)
    s.routeDMP(2)
    s.runSeconds(1)

    print "=== Phase 2: log ONE round of advertisements (7s) ==="
    s.addChannel("dvadv")
    s.runSeconds(7)

    print "=== Phase 3: cut link 3-4. Node 3 must NOT pick node 2 as a way to 4 ==="
    s.linkOff(3, 4)
    s.runSeconds(90)
    s.routeDMP(3)
    s.runSeconds(1)
    s.routeDMP(2)
    s.runSeconds(1)

if __name__ == '__main__':
    main()