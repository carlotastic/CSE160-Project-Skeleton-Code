from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)
    s.addChannel(s.FLOODING_CHANNEL)   # must stay silent: no flooding fallback

    print "=== Phase 1: startup, wait 60s ==="
    s.runSeconds(60)
    s.routeDMP(1)
    s.runSeconds(1)

    print "=== Phase 2: remove link 2-3. Network splits into {1,2} and {3,4} ==="
    s.linkOff(2, 3)
    s.runSeconds(40)
    s.routeDMP(1)          # 3 and 4 should show as INF / WITHDRAWN
    s.runSeconds(50)
    s.ping(1, 4, "cut")    # expect: "No route to 4, dropping"
    s.runSeconds(5)
    s.routeDMP(1)
    s.runSeconds(1)

    print "=== Phase 3: restore link 2-3, wait 60s ==="
    s.linkOn(2, 3)
    s.runSeconds(60)
    s.routeDMP(1)
    s.runSeconds(1)
    s.ping(1, 4, "back")   # should be routed again
    s.runSeconds(5)

if __name__ == '__main__':
    main()