---
title: "Kafka Broker Sizing Calculator"
date: 2019-09-20
description: "An open-source Apache Kafka broker and topic sizing calculator for capacity planning and cluster right-sizing."
tags: ["kafka", "capacity-planning", "open-source"]
weight: 30
---

Starting a Kafka cluster is easy. Sizing it correctly is where things get interesting. Most teams start with 3 brokers because that's the minimum, and then hope it's enough. This tool replaces the hope with math.

It takes your expected throughput, retention, replication factor, and consumer count, then calculates disk, network, and partition requirements so you know your choke points before you hit them.

- [Source Code](https://github.com/waliaabhishek/kafka_broker_sizing)
