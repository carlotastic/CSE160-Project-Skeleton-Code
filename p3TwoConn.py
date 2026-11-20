import sys
from TestSim import TestSim

def main():
    s = TestSim()
    s.t.randomSeed(1)
    s.runTime(1)
    s.loadTopo("line4.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    print "=== routes converge (60s), check with a ping ==="
    s.runSeconds(60)
    s.addChannel(s.ROUTING_CHANNEL)
    s.ping(1, 4, "check")
    s.runSeconds(5)
    s.t.removeChannel(s.ROUTING_CHANNEL, sys.stdout)

    print "=== TWO CONNECTIONS: 1:10 -> 4:20 and 2:12 -> 4:20 at the same time ==="
    s.cmdTestServer(4, 20)
    s.runSeconds(1)
    s.cmdTestClient(1, 4, 10, 20, 500)
    s.runSeconds(1)
    s.cmdTestClient(2, 4, 12, 20, 500)
    s.runSeconds(150)
    s.runSeconds(150)

if __name__ == '__main__':
    main()