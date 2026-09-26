Here's the same material again, slower and with everyday comparisons. Read it top to bottom once, then go back to the code.

---

# Part 0: The setting

Picture **19 people standing in a dark field**. Nobody can see anyone. Each person can only **shout**, and only the people standing right next to them can hear.

- Each person is a **node** (a tiny sensor).
- Shouting is a **broadcast**: everyone within earshot hears it. The code calls this `AM_BROADCAST_ADDR`, which means "send to everyone who can hear me."
- The people next to you are your **neighbors**.

The two problems the project solves:
1. **Flooding:** how does person 1 get a message to person 10, who is far away and can't hear them?
2. **Neighbor discovery:** how does each person figure out who is standing next to them?

---

# Part 1: The packet (the envelope)

Every message is an **envelope** with information written on the outside. This is the `pack` struct in `includes/packet.h`:

| Field | Plain meaning | Example |
|---|---|---|
| `src` | Who **originally** wrote the message | 1 |
| `dest` | Who it's **for** | 10 |
| `seq` | The writer's message number: their 1st, 2nd, 3rd message... | 1 |
| `TTL` | "Hops left." Goes down by 1 each time someone passes it on. | 15 |
| `protocol` | What kind of message: `PING` ("hello?") or `PINGREPLY` ("hello back!") | PING |
| `payload` | The actual message inside | "Hi!" |

Keep this table in mind; everything below reads and writes these fields.

---

# Part 2: Flooding, explained like a rumor

Person 1 wants to tell person 10 "Hi!", but can only shout to person 2. So the rule is:

> **"If you hear a message that isn't for you, shout it again so your neighbors hear it."**

The message spreads outward like a rumor until it reaches person 10. That's all flooding is.

### Problem 1: the rumor goes in circles
Suppose persons 1, 2, and 3 all stand next to each other in a triangle:
- 1 shouts, and 2 and 3 hear it.
- 2 re-shouts, and 1 and 3 hear it again.
- 3 re-shouts, and 1 and 2 hear it again.
- Everyone re-shouts again, and again, forever.

**The fix is a notebook (the "seen table").** Every person keeps a notebook that says, for each person, the highest message number heard from them.

> "From person 1, I've already heard up to message #1."

When a message arrives, check the notebook:
- If you've **already seen** that message (same `src`, and a `seq` you've already recorded), **ignore it**. The log prints `Duplicate ... dropping`.
- If it's **new**, write it in the notebook and keep going.

Now every person re-shouts each message **only once**, and the circle stops.

**Why use both `src` and `seq`?** Person 1's "message #1" and person 15's "message #1" are different messages. You need both the writer and the number to know exactly which message it is.

### Problem 2: a message for someone who doesn't exist
If person 1 sends a message to person 50, and there is no person 50, the rumor spreads through the entire field before dying out. The fix is TTL, the **"hops left" counter**:
- It starts at 15.
- Each time someone re-shouts, they subtract 1.
- If a message arrives with only 1 hop left, you **don't pass it on**. The log prints `TTL expired`.

So a message can't travel more than 15 hops, no matter what.

**Why have both?** They catch different problems:
- The **notebook** stops messages going in **circles**.
- **TTL** stops messages traveling **too far**.
- Either one alone leaves a gap.

### The reply
When person 10 gets the message:
- It's addressed to them, so they **don't re-shout it**, because it has arrived.
- They write a **new** envelope: `src=10, dest=1, protocol=PINGREPLY`, and flood it back the same way.
- When person 1 gets the reply, they **stop**. You never reply to a reply; otherwise two people would say "hello back!" to each other forever.

---

# Part 3: Reading a real trace (your cycle test)

This is from your `test_output/cycle.txt`. Person 1 sends to person 9 in the network with circles. `DEBUG (3)` means "this line was printed by node 3."

```
DEBUG (1): Sent PING to 9 (seq 1)
```
Node 1 writes the envelope (`src=1, dest=9, seq=1, TTL=15`), notes "seq 1 from me" in its own notebook, and shouts.

```
DEBUG (3): Received from 1 (src 1, dest 9, seq 1, TTL: 15)
DEBUG (3): Forwarded (src 1, seq 1, TTL now 14)
DEBUG (2): Received from 1 (src 1, dest 9, seq 1, TTL: 15)
DEBUG (2): Forwarded (src 1, seq 1, TTL now 14)
```
Nodes 2 and 3 are next to node 1, so they heard it. For each of them:
- It's new, so they write it in their notebook.
- It's not for them, so they subtract 1 from TTL (15 → 14) and re-shout.

```
DEBUG (2): Received from 3 (src 1, dest 9, seq 1, TTL: 14)
DEBUG (2): Duplicate (src 1, seq 1), dropping
DEBUG (1): Received from 3 (src 1, dest 9, seq 1, TTL: 14)
DEBUG (1): Duplicate (src 1, seq 1), dropping
```
When node 3 re-shouted, nodes 2 and 1 heard it too, because they're next to node 3. **Their notebooks already have it**, so they ignore it. **This is the circle being stopped.**

```
DEBUG (4): Received from 3 ... Forwarded (TTL now 13)
DEBUG (8): Received from 4 ... Forwarded (TTL now 12)
... eventually ...
DEBUG (9): PING from 1 arrived. Payload: cycles
DEBUG (9): Sent PINGREPLY to 1 (seq 1)
DEBUG (1): PINGREPLY from 9 arrived
```
The message moves outward (3 → 4 → 8 → 9) with TTL dropping by 1 each hop. Node 9 sees it's addressed to itself and sends a reply, and the reply floods back to node 1.

**"Received from"** shows the **neighbor who just shouted it** (the previous hop), which is different from `src`, the **original writer**. That's why the line reads `Received from 3 (src 1 ...)`: node 3 passed it on, but node 1 wrote it.

---

# Part 4: The code in Node.nc, in plain English

### When you type `ping(1, 10, "Hi!")`: `CommandHandler.ping`, [Node.nc:120](Node.nc#L120)
- **Line 121:** "Is this ping for myself?" If so, print it and stop; there's no need to shout.
- **Line 126:** Write the envelope: `src=me, dest=10, TTL=15, PING, seq = my next number`.
- **Line 127:** Write **my own message in my own notebook**. Otherwise, when my neighbor re-shouts it, I'd hear it and think it's new.
- **Line 128:** Shout it to everyone nearby.

### When any message arrives: `Receive.receive`, [Node.nc:67](Node.nc#L67)
It's a checklist, top to bottom. As soon as one step says stop, the function ends.

| Line | Question | If yes |
|---|---|---|
| [71](Node.nc#L71) | Is the envelope the wrong size? | Ignore it (garbage). |
| [77](Node.nc#L77) | *(no question)* Record which neighbor just shouted it. | Used for the "Received from" print. |
| [80](Node.nc#L80) | Is `dest` = "everyone"? | It's a **neighbor discovery** message, so hand it to the neighbor module (Part 5) and stop. |
| [88](Node.nc#L88) | Is it already in my notebook? | Print "Duplicate" and stop. |
| [94](Node.nc#L94) | Is it addressed **to me**? | If PING: send a PINGREPLY back. If PINGREPLY: print "arrived!" Either way, stop. |
| [108](Node.nc#L108) | Is TTL 1 or less? | Print "TTL expired" and stop. |
| [113](Node.nc#L113)–[114](Node.nc#L114) | *(if none of the above)* | Subtract 1 from TTL and re-shout it. |

### The notebook check: `alreadySeen`, [Node.nc:41](Node.nc#L41)
In plain English:
> "Do I have a notebook entry for this writer, **and** is this message number at or below what I've already recorded? If yes, it's old, so return TRUE. Otherwise, write this number down and return FALSE."

---

# Part 5: Neighbor discovery, explained like roll call

Every few seconds, each person in the dark field shouts:
> **"Who's next to me?"**

Everyone who hears it answers **only that person**:
> **"I'm here!"**

Whoever answers is a **neighbor**, so they go on your list.

### Why these messages don't flood
These messages have **TTL = 1** and are **never re-shouted**. You only want to reach the people right next to you, not the whole field.

### How the code tells roll call apart from normal messages
Roll-call envelopes are addressed to **"everyone"** (`dest = AM_BROADCAST_ADDR`). A normal ping is always addressed to a real person, like 10. So [Node.nc:80](Node.nc#L80) checks: "addressed to everyone? Then it's roll call," and hands it to the neighbor module.

### Handling people who leave (the strikes system)
Each neighbor on your list has a **strike count** for how many roll calls in a row they haven't answered.

Every roll call (`neighborTimer.fired`, [NeighborDiscoveryP.nc:62](lib/modules/NeighborDiscoveryP.nc#L62)):
1. **Give everyone on the list +1 strike** (`ageNeighbors`, [line 37](lib/modules/NeighborDiscoveryP.nc#L37)). If anyone now has more than 3 strikes, **remove them** and print "Neighbor X dropped."
2. **Shout "Who's next to me?"**

When a reply arrives ("I'm here!"), that neighbor's strikes **reset to 0** ([line 67](lib/modules/NeighborDiscoveryP.nc#L67), `handle`).

So:
- **A neighbor who's still there** gets a strike, then replies right away and goes back to 0. They never build up strikes.
- **A neighbor who left** never replies, so their strikes go 1, 2, 3, 4, and then they're removed.

**Your proof:** you turned off node 5, and about 15 seconds later nodes 4 and 6 both said "Neighbor 5 dropped."

### Why the timer is "3 seconds + a random bit" ([line 59](lib/modules/NeighborDiscoveryP.nc#L59))
- **If everyone shouted at exactly the same moment,** the shouts would collide and nobody would hear anything. The random extra time spreads the shouts out.
- **Every 3 seconds, not every 0.01 seconds,** because constant roll calls would jam the network. The assignment warns about this.

### `handle`, [line 67](lib/modules/NeighborDiscoveryP.nc#L67), in plain English
> - "If someone asked 'who's there?' (PING), answer them directly with 'I'm here!' (PINGREPLY)."
> - "If someone answered 'I'm here!' (PINGREPLY), put them on my list, or reset their strikes to 0."

---

# Part 6: Cheat sheet for the TA

Memorize these one-liners:

- **What's flooding?** "Every node re-broadcasts each new packet once, so it spreads to everyone until it reaches the destination."
- **How do you stop loops?** "Each node keeps a table of the highest sequence number it's seen from each source. If a packet's already in the table, it's dropped."
- **What does TTL do?** "It's a hop limit. It goes down by one each forward, and at 1 the packet is dropped. It's a backup that also stops packets to unreachable nodes."
- **How does the reply get back?** "The destination makes a new packet addressed to the original source and floods it back the same way."
- **How does neighbor discovery work?** "A timer fires every few seconds and sends a one-hop ping. Neighbors reply, and anyone who replies goes on my list."
- **How do you detect a neighbor leaving?** "Each neighbor gets a strike every round. Replying resets it to 0. After 3 missed rounds, it's removed."
- **Why the random timer?** "So nodes don't all transmit at the same moment and collide."
- **Why not add a new packet type?** "The assignment said not to, so I reused PING and PINGREPLY with TTL 1, and marked them with dest = broadcast."

---

**A good way to practice:** open [test_output/cycle.txt](test_output/cycle.txt) and read each line out loud, saying what the node is doing and why (e.g. "node 2 dropped it because it's already in its notebook"). If you can do that for 10 lines, you understand flooding.

I can also turn this into a web page with diagrams of the dark field, the notebook, and the roll call, if pictures would help.