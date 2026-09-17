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
- `CommandMsg.h` —