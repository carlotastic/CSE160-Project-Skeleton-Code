import sys
from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")          # 1-2-3-4: multi-hop
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

    print "=== TEST 1 baseline: 1030 bytes from 1:10 to 4:20, then close ==="
    s.cmdTestServer(4, 20)
    s.runSeconds(1)
    s.addChannel("tcpdetail")          # show DATA_TX with 'outstanding'
    s.cmdTestClient(1, 4, 10, 20, 1030)
    s.runSeconds(150)

if __name__ == '__main__':
    main()