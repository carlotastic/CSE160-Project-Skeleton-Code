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

    print "=== TEST 4 flow control: server consumer paused, buffer fills, window goes to 0 ==="
    s.cmdTestServer(4, 20)
    s.runSeconds(1)
    s.pauseConsumer(4)
    s.runSeconds(1)
    # node 3 drops the FIRST ACK from node 4 that reopens the window (ack 229 = 101 + 128)
    s.setDrop(3, s.WNDUPDATE, 229, src=4)
    s.runSeconds(1)
    s.addChannel(s.TCP_DETAIL_CHANNEL)
    s.cmdTestClient(1, 4, 10, 20, 400)
    s.runSeconds(25)

    print "=== resume the consumer: its first window update will be dropped ==="
    s.resumeConsumer(4)
    s.runSeconds(120)

if __name__ == '__main__':
    main()