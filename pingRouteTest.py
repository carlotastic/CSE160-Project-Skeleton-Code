from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)
    s.addChannel(s.FLOODING_CHANNEL)   # should stay SILENT -> proves no flooding

    # let routes converge
    s.runTime(60)

    s.routeDMP(1)
    s.runTime(2)

    s.ping(1, 4, "hello")
    s.runTime(10)

if __name__ == '__main__':
    main()