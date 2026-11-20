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

    s.cmdTestServer(4, 20)            # the only listener is on port 20
    s.runSeconds(1)

    print "=== TEST 6a: unavailable listener: 1:11 -> 4:99 (nobody listens on 99) ==="
    s.cmdTestClient(1, 4, 11, 99, 100)
    s.runSeconds(35)

    print "=== TEST 6b: unreachable peer: 1:12 -> node 9 (not in the network) ==="
    s.cmdTestClient(1, 9, 12, 20, 100)
    s.runSeconds(35)

    print "=== resources released: a normal connection still works (1:13 -> 4:20) ==="
    s.cmdTestClient(1, 4, 13, 20, 100)
    s.runSeconds(45)

    print "=== TEST 6c: peer dies mid-transfer: node 4 turned off ==="
    s.cmdTestClient(1, 4, 14, 20, 1000)
    s.runSeconds(10)
    s.moteOff(4)
    s.runSeconds(60)

if __name__ == '__main__':
    main()