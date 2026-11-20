#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    moteids=[]
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_ROUTE_DUMP=3
    CMD_TTL_PING = 7
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5
    CMD_CLIENT_CLOSE = 8
    CMD_DROP_RULE = 10
    CMD_PAUSE = 11
    CMD_RESUME = 12
    WNDUPDATE = 128 

    # TCP flag values (same as tcp.h), for drop rules
    SYN = 1
    ACK = 2
    FIN = 4
    DATA = 8

    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";
    TCP_DETAIL_CHANNEL="tcpdetail";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))
                if not int(s[0]) in self.moteids:
                    self.moteids=self.moteids+[int(s[0])]
                if not int(s[1]) in self.moteids:
                    self.moteids=self.moteids+[int(s[1])]

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in self.moteids:
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in self.moteids:
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in self.moteids:
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();
    
     # run until `secs` seconds of SIMULATED time have passed
    def runSeconds(self, secs):
        end = self.t.time() + secs * self.t.ticksPerSecond()
        while self.t.time() < end:
            self.t.runNextEvent()

    # cut both radio directions of a link (both nodes stay ON)
    def linkOff(self, a, b):
        self.r.remove(a, b)
        self.r.remove(b, a)

    # restore both radio directions of a link
    def linkOn(self, a, b, gain=-54.0):
        self.r.add(a, b, gain)
        self.r.add(b, a, gain)

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));
    
    def pingTTL(self, source, dest, ttl, msg):
        self.sendCMD(self.CMD_TTL_PING, source, "{0}{1}{2}".format(chr(dest), chr(ttl), msg))

    def cmdTestServer(self, serverAddress, listenPort):
        self.sendCMD(self.CMD_TEST_SERVER, serverAddress, chr(listenPort))

    # at clientAddress: connect srcPort -> (serverAddress, destPort), then send transferBytes
    def cmdTestClient(self, clientAddress, serverAddress, srcPort, destPort, transferBytes):
        self.sendCMD(self.CMD_TEST_CLIENT, clientAddress,
                     chr(serverAddress) + chr(srcPort) + chr(destPort) +
                     chr(transferBytes >> 8) + chr(transferBytes & 0xFF))

    # at clientAddress: gracefully close that connection
    def cmdClientClose(self, clientAddress, serverAddress, srcPort, destPort):
        self.sendCMD(self.CMD_CLIENT_CLOSE, clientAddress,
                     chr(serverAddress) + chr(srcPort) + chr(destPort))
        
    # ---- wrappers for the course-provided scripts (testA.py, testB.py) ----
    # They only pass node addresses, so the rest uses documented defaults:
    # server at node 1, well-known port 123, client port 10, 1030 bytes.
    DEFAULT_SERVER = 1
    DEFAULT_PORT = 123
    DEFAULT_SRC_PORT = 10
    DEFAULT_BYTES = 1030

    def testServer(self, serverAddress):
        self.cmdTestServer(serverAddress, self.DEFAULT_PORT)

    def testClient(self, clientAddress):
        self.cmdTestClient(clientAddress, self.DEFAULT_SERVER, self.DEFAULT_SRC_PORT,
                           self.DEFAULT_PORT, self.DEFAULT_BYTES)
        
    # TEST ONLY: at `node`, drop the next `count` forwarded TCP packets with these flags.
    # value = seq for DATA/SYN/FIN, or the ack number for a pure ACK. src = 0 means any sender.
    def setDrop(self, node, flags, value, src=0, count=1):
        self.sendCMD(self.CMD_DROP_RULE, node,
                     chr(src) + chr(flags) + chr(value >> 8) + chr(value & 0xFF) + chr(count))

    def pauseConsumer(self, node):
        self.sendCMD(self.CMD_PAUSE, node, "p")

    def resumeConsumer(self, node):
        self.sendCMD(self.CMD_RESUME, node, "r")

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);

def main():
    s = TestSim();
    s.runTime(10);
    s.loadTopo("long_line.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);

    s.runTime(20);
    s.ping(1, 2, "Hello, World");
    s.runTime(10);
    s.ping(1, 3, "Hi!");
    s.runTime(20);

if __name__ == '__main__':
    main()
