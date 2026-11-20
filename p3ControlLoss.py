import sys
from TestSim import TestSim

# which control message to drop:  name: (node, flags, value, src)
CASES = {
    "syn":      (2, 1, 100, 1),   # client's SYN (seq 100)
    "synack":   (3, 3, 500, 4),   # server's SYN+ACK (seq 500)
    "ack":      (2, 2, 501, 1),   # client's final handshake ACK (ack 501)
    "closeack": (2, 2, 502, 1),   # client's final close ACK (ack 502)
}

def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "syn"
    node, flags, value, src = CASES[which]

    s = TestSim()
    s.t.randomSeed(1)               # same seed every run = repeatable
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

    print "=== TEST 5 control loss (%s): node %d drops flags=%d value=%d from node %d ===" % (which, node, flags, value, src)
    s.cmdTestServer(4, 20)
    s.runSeconds(1)
    s.setDrop(node, flags, value, src=src)
    s.runSeconds(1)
    s.cmdTestClient(1, 4, 10, 20, 100)
    s.runSeconds(90)

if __name__ == '__main__':
    main()