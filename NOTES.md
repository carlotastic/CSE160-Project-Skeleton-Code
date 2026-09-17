# CSE160 Skeleton Code — Plain-English Guide

This project simulates a bunch of tiny wireless sensors ("motes") talking
to each other. You write the logic for one mote's brain; a simulator
called TOSSIM runs many copies of it on a fake map and lets you watch
them send messages. Everything below explains how the pieces actually
connect, using real lines from this project.

---

## 1. nesC vocabulary (the language this is written in)

TinyOS code is written in nesC, which looks like C but has extra
concepts. You'll see these words everywhere:

- **module** — a file with actual code/logic inside (like a normal .c file
  with functions). Example: `Node.nc`, `CommandHandlerP.nc`.
- **configuration** — a file with NO logic, only wiring. It says "connect
  part A to part B." Example: `NodeC.nc`, `CommandHandlerC.nc`,
  `SimpleSendC.nc`.
- **interface** — the "shape of a plug." It lists what commands/events
  exist, but not how they work. Example: `CommandHandler.nc`,
  `SimpleSend.nc`.
- **command** — a function you CALL (like `call Sender.send(...)`).
- **event** — a function that gets CALLED BACK at you when something
  happens (like `event void Boot.booted()`).
- **generic component** — a reusable part you can stamp out multiple
  copies of, each configured differently, e.g.
  `components new AMReceiverC(AM_PACK)` — the `(AM_PACK)` is a setting,
  like ordering a shirt in a specific size.
- **dbg(CHANNEL, "text")** — a print statement for debugging, but it only
  shows up if you've turned that channel on in your simulation script.

Naming convention you'll notice: `Foo` (interface) → `FooC` (the
public wiring/configuration you actually use) → `FooP` (the private
module with the real code, "P" for "private implementation").

---

## 2. The brain: `Node.nc` + `NodeC.nc`

`Node.nc` is a **module** — the real logic. Key parts:

```c
module Node{
   uses interface Boot;
   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;
}
```

This is Node declaring "I need these 4 abilities plugged into me: a
Boot signal, radio on/off control, a way to receive messages, a way to
send messages, and a way to receive commands." It doesn't say WHERE
those come from — that's `NodeC.nc`'s job.

Then the actual behavior:
```c
event void Boot.booted(){
   call AMControl.start();          // turn the radio on
}
event void AMControl.startDone(error_t err){
   if(err == SUCCESS){ ... }        // radio's on, ready to go
   else{ call AMControl.start(); }  // retry if it failed
}
event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
   makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
   call Sender.send(sendPackage, destination);   // actually send it
}
```

So the sequence when a mote boots is: **Boot.booted → AMControl.start()
→ AMControl.startDone() fires → radio is ready.** Later, when someone
tells this mote "ping node 5," `CommandHandler.ping` fires, it builds a
packet and calls `Sender.send`.

Now `NodeC.nc` — the **configuration** — has zero logic, just wiring:
```c
components MainC;
components Node;
components new AMReceiverC(AM_PACK) as GeneralReceive;
Node -> MainC.Boot;                 // Node's "Boot" plug <- MainC's real boot signal
Node.Receive -> GeneralReceive;     // Node's "Receive" plug <- a real receiver, tuned to AM_PACK
components ActiveMessageC;
Node.AMControl -> ActiveMessageC;   // Node's "AMControl" plug <- the real radio driver
components new SimpleSendC(AM_PACK);
Node.Sender -> SimpleSendC;         // Node's "Sender" plug <- a real sender, tuned to AM_PACK
components CommandHandlerC;
Node.CommandHandler -> CommandHandlerC;  // Node's "CommandHandler" plug <- the real command listener
```
Every `->` line is "plug the left thing into the right thing." That's
the entire file. This is why searching it for function calls goes
nowhere — there aren't any.

`AM_PACK` (defined in `packet.h` as `6`) tells `AMReceiverC` and
`SimpleSendC` "only handle messages tagged as packet-type-6." Same idea
as tuning a radio to a specific station.

---

## 3. The reusable parts: `lib/` and `dataStructures/`

- **CommandHandler** (`lib/interfaces/CommandHandler.nc` +
  `lib/modules/CommandHandlerC.nc` / `CommandHandlerP.nc`): listens on
  its own channel (`AM_COMMANDMSG = 99`) for incoming command messages
  (from your Python test script), figures out which command ID it is
  (`command.h` defines `CMD_PING=0`, `CMD_NEIGHBOR_DUMP=1`, etc.), and
  fires the matching event, e.g. `signal CommandHandler.ping(...)`.
  That's literally how your ping in a Python script turns into
  `Node.nc`'s `CommandHandler.ping` firing.
- **SimpleSend** (`lib/modules/SimpleSendC.nc`): a simplified send
  button with built-in queuing and small delays so messages don't
  collide. You're told not to change the delays, but you can duplicate
  it for a different AM type.
- **Transport** (`lib/interfaces/Transport.nc`): just an empty interface
  for a future assignment (Project 3) — ignore it for now.
- **Hashmap / List** (`dataStructures/`): generic storage helpers —
  Hashmap = lookup by key, List = pushfront/pushback list. Optional
  helpers, not required.

---

## 4. The shared rulebook: `includes/*.h`

Plain C headers, no logic — just numbers and data shapes everyone
agrees on:

- `packet.h` — defines the `pack` struct (what a network packet looks
  like: src, dest, seq, TTL, protocol, payload) and `AM_PACK = 6`.
- `CommandMsg.h` — defines the `CommandMsg` struct (dest, command id,
  payload) and `AM_COMMANDMSG = 99`.
- `command.h` — the list of command IDs: `CMD_PING=0`,
  `CMD_NEIGHBOR_DUMP=1`, `CMD_LINKSTATE_DUMP=2`, etc.
- `channels.h` — numbers for debug print channels, e.g.
  `GENERAL_CHANNEL`, `COMMAND_CHANNEL` — these are what you turn on/off
  in your Python test script to control what gets printed.
- `sendInfo.h`, `socket.h`, `am_types.h` — smaller support definitions
  used inside `SimpleSendC`/`Transport`.

---

## 5. The pretend world: `topo/` and `noise/`

- `topo/*.topo` — the fake map. Each line is `source dest gain`, e.g.
  `1 2 -54.0` means mote 1 can send to mote 2 with signal strength -54.
  It's one-directional unless you also add the reverse line
  (`2 1 -54.0`). `long_line.topo` = 19 motes in a line;
  `example.topo` = a more tangled map.
- `noise/no_noise.txt` — a long list of noise readings (all `-98` here,
  meaning basically silent/no interference). Swap this file for a
  noisier one to test packet loss.

---

## 6. Running it: `TestSim.py`, `pingTest.py`, `CommandMsg.py`, `packet.py`

`TestSim.py` is the remote control for the whole simulation. A typical
script (like `pingTest.py`) does, in order:
```python
s = TestSim()                       # start the simulator
s.runTime(1)                        # let time pass with everything off
s.loadTopo("long_line.topo")        # load the fake map
s.loadNoise("no_noise.txt")         # load the fake interference
s.bootAll()                         # boot every mote (fires Boot.booted on each)
s.addChannel(s.COMMAND_CHANNEL)     # turn on this debug channel's prints
s.addChannel(s.GENERAL_CHANNEL)
s.runTime(1)
s.ping(2, 3, "Hello, World")        # tell mote 2 to ping mote 3
s.runTime(1)
```
`s.ping(2, 3, "Hello, World")` sends a `CommandMsg` (command id =
`CMD_PING`) to mote 2. That triggers `CommandHandlerP.nc`'s
`Receive.receive`, which decodes it and fires
`signal CommandHandler.ping(3, "Hello, World")`, which lands in your
`Node.nc`'s `CommandHandler.ping` event, which builds a packet and
sends it toward mote 3 — following whatever path the `.topo` file
allows.

`CommandMsg.py` and `packet.py` are auto-generated (see the Makefile
rules below) — they're Python versions of the `CommandMsg` and `pack`
C structs, so `TestSim.py` can build messages that your C code will
understand.

---

## 7. Building it: `Makefile`

```make
COMPONENT=NodeC          # the top-level configuration to build
INCLUDE=-IdataStructures -Ilib/interfaces -Ilib/modules ...
include $(TINYOS_ROOT_DIR)/Makefile.include   # the real TinyOS build magic

CommandMsg.py: CommandMsg.h
    nescc-mig python ... CommandMsg.h CommandMsg -o $@   # regenerate CommandMsg.py from the .h

packet.py: packet.h
    nescc-mig python ... packet.h pack -o packet.py      # regenerate packet.py from the .h
```
Running `make micaz sim` (or similar, per your course instructions)
compiles `NodeC` and everything it's wired to. The last two rules are
how `CommandMsg.py`/`packet.py` get (re)created automatically whenever
you change the matching `.h` file.

---

## 8. The full flow, start to finish

1. You edit `Node.nc` (the logic) — this is most of your actual work.
2. `NodeC.nc` wires that logic to the real radio, timer, and command
   listener.
3. `make` compiles everything into a simulation binary.
4. A Python script (`pingTest.py` style) loads a `.topo` map and a
   `noise` file, boots every mote, then sends test commands like pings.
5. Those commands travel in through `CommandHandlerC` → fire events in
   `Node.nc` → your logic sends real packets → `dbg()` prints show you
   what's happening on whichever channels you turned on.