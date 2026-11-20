import sys
from TestSim import TestSim

def main():
    s = TestSim()
    s.t.randomSeed(1)                 # repeatable noise
    s.runTime(1)
    s.loadTopo("line4.topo")          # 1-2-3-4, gain -54
    s.loadNoise("meyer-heavy.txt")    # heavy noise: random packet loss
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    print "=== routes converge (90s), check with a ping ==="
    s.runSeconds(90)
    s.addChannel(s.ROUTING_CHANNEL)
    s.ping(1, 4, "check")
    s.runSeconds(5)
    s.t.removeChannel(s.ROUTING_CHANNEL, sys.stdout)

    print "=== NOISY RUN: 1030 bytes 1:10 -> 4:20 over meyer-heavy noise ==="
    s.cmdTestServer(4, 20)
    s.runSeconds(1)
    s.cmdTestClient(1, 4, 10, 20, 1030)
    s.runSeconds(300)

if __name__ == '__main__':
    main()