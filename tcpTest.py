from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")          # 1-2-3-4, a multi-hop route
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    print "=== routes converge (60s), check with a ping ==="
    s.runSeconds(60)
    s.addChannel(s.ROUTING_CHANNEL)
    s.ping(1, 4, "check")
    s.runSeconds(5)

    print "=== node 4 listens on port 20 ==="
    s.cmdTestServer(4, 20)
    s.runSeconds(1)

    print "=== node 1 port 10 connects to node 4 port 20 ==="
    s.cmdTestClient(1, 4, 10, 20, 300)
    s.runSeconds(5)

if __name__ == '__main__':
    main()