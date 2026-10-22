## The big picture

Think of your node as an **office building**:

- **The radio** is the mailroom where letters come in and go out.
- **Flooding** is one department. It passes letters along until they reach the right person.
- **Neighbor Discovery** is another department. It shouts "who's nearby?" and writes down who answers.
- **Node.nc** is the boss, who only cares about "I got a ping, so reply."

## Before (master)

The **boss did everything**. Node.nc:
- turned the radio on
- opened every incoming letter
- decided "this is a neighbor discovery letter" or "this is a flooding letter"
- did all the flooding work itself: checking duplicates, TTL and forwarding
- *and* handled pings

The Flooding module existed but was an unfinished draft that nothing used.

## After (floodingp-update)

A **mailroom (LinkLayer)** was added:

1. **It turns the radio on** and tells everyone "we're open, you can send now." That's the `ready()` event.
2. **It sorts incoming mail.** Letters addressed to "everyone" go to Neighbor Discovery. Letters addressed to a specific node go to Flooding.
3. **It sends mail out** for anyone who asks, using `broadcast()` or `unicast()`.

Each department now does only its own job:
- **Flooding** handles duplicates, TTL and forwarding. When a letter is actually for this node, it hands it to the boss.
- **Neighbor Discovery** starts itself when the mailroom opens and only sees its own letters.
- **Node.nc (the boss)** just says "send a ping to node 5" or "I got a ping, send a reply." It doesn't know how delivery works.

## Why the mailroom is needed at all

TinyOS only lets **one** component listen to the radio for a given message type. So Flooding and Neighbor Discovery can't both listen directly. Someone has to receive everything and hand it out. On master that was the boss. Now it's LinkLayer.

## Why this is better

1. **Each file has one job.** When flooding breaks, you look in FloodingP. When neighbor discovery breaks, you look in NeighborDiscoveryP. You no longer have one giant Node.nc to dig through.
2. **Project 2 gets easier.** You'll replace flooding with routing. Since the boss only calls `Flooding.send()` and listens for `Flooding.receive`, you can swap what's underneath without rewriting Node.nc.
3. **The departments stay out of each other's way.** On master, flooding and neighbor discovery could get mixed up. For example, neighbor discovery sequence numbers could end up in flooding's duplicate list. Now each one only sees its own packets.

## The two LinkLayer interfaces in one line each

- **[LinkLayer.nc](lib/interfaces/LinkLayer.nc)**: "Mailroom, please send this," plus "The mailroom is open."
- **[LinkReceive.nc](lib/interfaces/LinkReceive.nc)**: "Here's a letter for you, and here's the neighbor who handed it to us" (`prevHop`).