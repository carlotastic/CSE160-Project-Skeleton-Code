from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("long_line.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.NEIGHBOR_CHANNEL)

    # let everyone boot and run a few discovery rounds
    s.runTime(40)
    s.neighborDMP(4)
    s.runTime(2)
    s.neighborDMP(5)
    s.runTime(2)

    # kill node 5 and after around 4 rounds, nodes 4 and 6 should drop it
    s.moteOff(5)
    s.runTime(25)
    s.neighborDMP(4)
    s.runTime(2)
    s.neighborDMP(6)
    s.runTime(2)

if __name__ == '__main__':
    main()