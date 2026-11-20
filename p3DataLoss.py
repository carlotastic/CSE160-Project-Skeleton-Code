import sys
from TestSim import TestSim

def main():
    s = TestSim()
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

    print "=== TEST 2 data loss: node 2 drops the DATA segment seq=134 from node 1 ==="
    s.cmdTestServer(4, 20)
    s.runSeconds(1)
    s.setDrop(2, s.DATA, 134, src=1)
    s.runSeconds(1)
    s.addChannel(s.TCP_DETAIL_CHANNEL)   # to see the ACK numbers
    s.cmdTestClient(1, 4, 10, 20, 300)
    s.runSeconds(90)

if __name__ == '__main__':
    main()