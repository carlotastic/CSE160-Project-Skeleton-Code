from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")       # our topology instead of tuna-melt
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    s.runTime(300)
    s.testServer(1)                # node 1 listens on port 123
    s.runTime(60)

    s.testClient(4)                # node 4 connects to node 1:123, sends 1030 bytes
    s.runTime(1)
    s.runTime(1000)

if __name__ == '__main__':
    main()