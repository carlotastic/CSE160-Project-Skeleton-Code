from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("line4.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)

    # let neighbor discovery run a few rounds
    s.runTime(60)

    for node in [1, 2, 3, 4]:
        s.routeDMP(node)
        s.runTime(2)

if __name__ == '__main__':
    main()