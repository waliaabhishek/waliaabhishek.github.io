---
title: "Sizing a Kafka Cluster from First Principles"
date: 2026-04-14
draft: false
tags: ["kafka", "capacity-planning", "sizing", "infrastructure", "kafka_broker_sizing"]
categories: ["kafka"]
description: "The six constraints that bound any Kafka cluster size, the math behind each, and a worked example you can plug your own numbers into. No magic, no vendor decks, just formulas."
---

Most Kafka sizing advice is hand-wavy. "Start with 3 brokers." "Scale when you hit a bottleneck." "Talk to your vendor." I have spent years on both ends of that conversation, as the engineer asking and the person being asked, and the answer is almost always some version of "it depends, let's just see how it goes." That isn't sizing. Its the easiest way to say "I don't know.".

Sizing a Kafka cluster is not magic. It is a constraint-satisfaction problem with exactly six knobs. Once you know the six, you can work out a broker count on a napkin and defend it to anyone who asks. The math is not hard. It's just not written down in most places.

This post walks through the six constraints, the per-topic math that feeds them, and a worked example you can plug your own numbers into. The next time a vendor or an SRE tells you "you probably need five brokers," you will be able to say why, or tell them they're wrong.

## The six constraints

Every Kafka cluster has to satisfy all six of these at once. Your broker count is the smallest integer that clears every one of them:

1. Network ingress capacity. Can the NICs absorb the producer traffic, including replication-in from peer brokers?
2. Network egress capacity. Can the NICs push out consumer fetches and replication-out to followers?
3. Disk write throughput. Can the disks keep up with producer writes plus replication writes?
4. Disk capacity. Does the retained data fit on disk?
5. Replication factor floor. Do you have at least RF brokers to hold the replicas at all?
6. Replicas per broker. Are you within the partition-count ceiling your metadata layer can handle?

Whichever constraint is binding tells you *why* your cluster is that size, and which knob moves if you want it smaller. If disk capacity is binding, retention is your lever. If network egress is binding, you have a fan-out problem, not a Kafka problem. That visibility matters more than the number itself.

Let's build the formulas.

## The per-topic building blocks

Every broker-level number starts as a per-topic number, summed across topics. For each topic, you need four things: ingress throughput, egress throughput, storage footprint, and partition count.

**Ingress throughput** is message size times message rate:

```
ingress_per_topic (bytes/sec) = avg_message_size * messages_per_sec
```

A topic doing 10,000 messages/sec at 1 KB per message is pushing 10 MB/s into the cluster. Apply a growth buffer on top. I've used 20 to 30 percent for a 6-month horizon, but pick yours based on your actual growth rate. You size for the cluster you'll have in some 'x' months horizon, not the one you have today.

**Egress throughput** scales with consumer groups. Each consumer group reads the full topic independently:

```
egress_per_topic = ingress_per_topic * consumer_group_count
```

A topic with 10 MB/s ingress and four consumer groups pushes 40 MB/s of egress. This is the number that surprises people the most. A "small" topic with ten consumers on it can out-egress a "large" topic with one.

**Storage footprint** is throughput times retention times replication factor:

```
storage_per_topic = ingress_per_topic * retention_seconds * RF
```

RF sneaks in because you're storing every byte on every replica. A 10 MB/s topic with 7-day retention and RF=3 pins down `10 MB/s * 604800 s * 3` = about 18 TB before compression.

**Partition count** is the most over-debated number in Kafka, and it's really just four sub-constraints max'd together:

```
partitions = max(
  min_floor,                             // never fewer than this, 3 is common
  ingress / per_partition_ingress_cap,   // producer side
  egress / per_partition_egress_cap,     // consumer side
  consumer_parallelism                   // how many consumer instances per group
)
```

The per-partition caps are operational choices, not physics. The 5 MB/s ingress and 15 MB/s egress defaults in my sizing spreadsheet are my opinion. Pick your own, but pick them explicitly. A partition is a unit of parallelism, not a unit of throughput, so you size it for whichever dimension is tightest. This will definitely change with Queues for Kafka but for order-guaranteed workloads, this still stands true.

Sum those four numbers across every topic and you have cluster-level ingress, egress, storage, and partition count. Those are the inputs to the six constraints.

## Constraints 1 and 2: network

I'm collapsing the two network constraints into one section because they most likely will share a NIC. Under uniform partition distribution, every broker carries `1/N` of the leader load and some follower load. Per broker, the network traffic looks like:

```
net_in_per_broker  = (cluster_ingress / N) * RF
net_out_per_broker = (cluster_ingress / N) * (RF - 1 + consumer_groups)
```

The `RF` multiplier on `net_in` catches people off guard. It's not just that producers push data in. The broker also receives replication traffic from every other leader for partitions where this broker is a follower. Under uniform distribution, that replication-in equals `(ingress/N) * (RF-1)`, which added to the `ingress/N` of producer traffic gives `(ingress/N) * RF`. Every byte you ingest lands on every broker that holds a replica, and every one of those lands via the network first.

The `net_out` side has two components. `(RF-1)` for replication out to followers, plus `consumer_groups` for fetches. Leader brokers push their data out to followers once per replica, and once per consumer group.

The constraint is that both sides have to stay under NIC capacity at a utilization watermark. I use 80 percent (leaves room for other traffic and network activity on the systems if needed):

```
net_in_per_broker  <= nic_capacity_in  * 0.80
net_out_per_broker <= nic_capacity_out * 0.80
```

Modern NICs are full-duplex, so a 10 Gbps NIC gives you roughly 1250 MB/s in each direction simultaneously. A 25 Gbps NIC gives you roughly 3125 MB/s. You do not get 2500 MB/s "bidirectional" out of a 10 Gbps NIC in the way marketing decks imply. Ingress and egress live on separate pipes that you bill separately.

## Constraint 3: disk write throughput

Disk writes look almost exactly like `net_in`, because every byte that comes in over the network has to hit the disk:

```
disk_write_per_broker = (cluster_ingress / N) * RF
```

Cluster ingress divided by broker count, times RF. The constraint is sustained disk write throughput, again with a watermark:

```
disk_write_per_broker <= disk_write_capacity * 0.65
```

The 0.65 is looser than network because disks misbehave in messier ways. Sequential writes are what Kafka does best, but compaction cycles, segment rolls, and the occasional log truncation all compete for the same IO budget. Feel free to run it tighter if you believe that this much head room is not needed.

## Constraint 4: disk capacity

This is the one everyone gets roughly right, and I'd bet it's the constraint that's currently deciding your broker count.

```
storage_per_broker = (cluster_ingress / N) * retention_seconds * RF
storage_per_broker <= disk_size * 0.65
```

Same 65 percent watermark. Running disks at 100 is how you get the 3am page that says "cluster unwritable, disk full, also the __consumer_offsets topic can't compact because there's no space to write the new segment." Been there, would not recommend.

`N` and `retention` are both levers, and they pull in opposite directions. Doubling retention doubles your broker count. Halving retention halves it. Tiered storage moves part of this problem off the Kafka brokers entirely, which is a whole separate post, but if you're hitting disk capacity as your binding constraint and your retention is over a day, tiered storage is almost certainly your answer.

## Constraint 5: the replication factor floor

The simplest of the six, and the one I see forgotten most often:

```
N >= max(RF across all topics)
```

If any topic has RF=3, you need at least 3 brokers. If you set RF=5 anywhere in the cluster (and you probably shouldn't unless you know exactly why), you need at least 5. This isn't really math, it's a hard topology requirement. Kafka will refuse to create the topic otherwise.

I've watched teams set a topic to RF=3 on a 2-broker test cluster and then spend an hour wondering why `kafka-topics --create` was failing. The error message tells you. Read it.

## Constraint 6: replicas per broker

This is the constraint that used to be hard and has gotten much easier.

In the ZooKeeper era, Jun Rao's [2015 Confluent post](https://www.confluent.io/blog/how-choose-number-topics-partitions-kafka-cluster/) pinned the soft limit at 2,000 to 4,000 partitions per broker for clusters that cared about availability during unclean failures, and suggested keeping the cluster-wide total in the "low tens of thousand." The bottleneck was metadata. On controller failover, the new controller had to reload every partition's state from ZooKeeper, and the illustrations put that at roughly 2 ms per partition, so a 10,000-partition cluster tacked about 20 seconds onto the unavailability window.

KRaft (KIP-500) changed the shape of that constraint. The controller is now a Raft-replicated metadata log inside Kafka itself, not ZooKeeper, so partition state doesn't have to be round-tripped through an external store. Confluent's [KRaft overview](https://developer.confluent.io/learn/kraft/) states the design has "the potential to scale up to millions of partitions." The old 4,000 per broker ceiling is dead, but "unlimited partitions" is not the right takeaway either. Partitions still cost memory, file handles, producer batching efficiency, and controller recovery time.

My pragmatic defaults: 4,000 per broker is still a fine soft limit if you're on ZooKeeper, and if you are, you should be planning the KRaft migration anyway. On KRaft, I'd probably still keep it at 4,000 per broker, but push to 5,000-7,000 per broker before it makes me nervous, and only higher if you've actually benchmarked your workload. That's just my preference though. Pick your poison based on what you've measured.

The constraint itself is straightforward:

```
N >= total_replicas / replicas_per_broker_limit
```

where `total_replicas = sum(partitions_per_topic * RF)` across all topics.

## Watermarks: why not 100 percent

The 80 percent network and 65 percent disk numbers aren't physics. They're operational headroom. You leave the slack because:

- **Failure domains.** If you plan for `N` brokers at 90 percent utilization and one dies, the remaining `N-1` brokers are now at `90% * N/(N-1)` utilization. For N=3 that's 135 percent. Game over.
- **Rebalancing.** A partition reassignment streams data between brokers. That traffic competes with everything else on the same NIC and same disk. You want headroom to absorb it without impacting producers.
- **Bursts.** Producer traffic is almost never steady. Your sizing input is an average. Your cluster has to survive the peak.
- **Segment rolls and compaction.** Not free. They compete with normal writes and reads.

80 on network and 65 on disk are where I've landed after enough incidents to have an opinion. Tune them if you have the instrumentation to know you can, but never run either dimension to 100. That's how you get outages that look, in the postmortem, like "the cluster was running fine and then it wasn't."

## A worked example

Let's plug numbers in. The scenario:

- Cluster ingress: 50 MB/s total across all topics (already includes the growth buffer).
- Retention: 3 days (259,200 seconds).
- Replication factor: 3.
- Consumer groups: 2 on average.
- Broker hardware: 10 Gbps NIC (1250 MB/s each direction), 8 TB usable disk per broker at 500 MB/s sustained write.
- Watermarks: 80 percent network, 65 percent disk.
- Target replicas per broker: 4,000 (KRaft, being conservative).
- Total replicas across the cluster: 3,000.

Walk the six.

**1. Network ingress.** Per-broker in = `(50/N) * 3 = 150/N` MB/s. Capacity = `1250 * 0.8 = 1000` MB/s. `150/N <= 1000` means `N >= 0.15`. Not binding.

**2. Network egress.** Per-broker out = `(50/N) * (3-1+2) = 200/N` MB/s. Same 1000 cap. `N >= 0.2`. Not binding.

**3. Disk write.** Per-broker write = `(50/N) * 3 = 150/N` MB/s. Capacity = `500 * 0.65 = 325` MB/s. `N >= 0.46`. Not binding.

**4. Disk capacity.** Per-broker storage = `(50/N) * 259200 * 3` MB = `38.88/N` TB. Capacity per broker = `8 * 0.65 = 5.2` TB. `N >= 38.88 / 5.2 = 7.48`. Round up. Binding at 8 brokers.

**5. RF floor.** `N >= 3`. Satisfied.

**6. Replicas per broker.** `N >= 3000 / 4000 = 0.75`. Round up to 1. Not binding.

Answer: 8 brokers, bound by disk capacity.

Now flip one variable. Cut retention from 3 days to 1 hour, but push ingress from 50 MB/s to 500 MB/s. Same everything else. Re-walk just the two that move:

Disk capacity becomes `(500/N) * 3600 * 3` MB = `5.4/N` TB. Needs `N >= 5.4/5.2 = 1.04`. Falls out as not binding.

Disk write becomes `(500/N) * 3 = 1500/N` MB/s. Needs `1500/N <= 325`, so `N >= 4.62`. Round up. Binding at 5 brokers.

Same hardware, same RF, one variable changed, and the binding constraint moved from disk capacity to disk write throughput. That is the whole point of the six-constraint model. The number isn't what matters. **The constraint that produces it is.**

## What the formulas don't catch

The six constraints give you a floor, not a guarantee. Things they don't model:

- **Uneven partition distribution.** Kafka's partition placement is not perfectly balanced, especially after broker additions or failures. Hot brokers hit limits before the average does.
- **Leader skew.** Producer traffic only hits leaders. A cluster with bad leader balance can be at 50 percent average NIC and 95 percent on one broker.
- **Compaction bursts.** Log-compacted topics do periodic cleanup that spikes disk IO. Not continuous, but not rare.
- **Cross-AZ replication cost.** If your RF=3 is split across availability zones, replication traffic is also egress on your cloud bill. Sizing for throughput is one question, sizing for cost is a different one.
- **Tiered storage.** Flips constraint 4 entirely. If you're on a platform with tiered storage enabled, disk capacity stops binding and something else takes over.
- **Client count.** Lots of idle consumer clients still cost file descriptors, connection state, and heartbeat overhead. Not captured in the throughput model.

None of this invalidates the six constraints. They just mean the floor the math gives you is the *minimum* broker count that might work. The right broker count is usually one or two above the floor, with the extra headroom earmarked for the stuff the formulas can't see.

## Close

Kafka sizing is not magic. It's six constraints, a handful of formulas, and the discipline to run the numbers before picking an answer. The spreadsheet I've used for years lives at [waliaabhishek/kafka_broker_sizing](https://github.com/waliaabhishek/kafka_broker_sizing) and automates all of this, but the math inside it is what's in this post. If you've read this far, you don't need the spreadsheet. You need a pen.

The next time someone hands you a broker count without showing you which constraint bound it, ask them. If they can't tell you, the number is a guess.

Feel free to reach out if you want to talk sizing or argue about watermarks.
