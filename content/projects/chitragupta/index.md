---
title: "Chitragupta"
date: 2026-03-26
description: "A multi-ecosystem infrastructure cost chargeback engine for Confluent Cloud, self-managed Kafka, and Prometheus-instrumented systems."
tags: ["kafka", "finops", "observability", "open-source"]
weight: 10
---

In Hindu tradition, Chitragupta is the deity who maintains a complete record of every being's actions. The divine accountant. Fitting name for a system that tracks exactly who used what and how much it cost.

This is a ground-up rewrite of the [CCloud Chargeback Helper](/projects/ccloud-chargeback-helper/), rebuilt with a full plugin architecture so I can add new ecosystems without touching the core engine every time. It correlates Confluent Cloud Billing, Metrics, and Core Objects APIs to produce hourly, identity-level cost attribution down to service accounts, users, API keys, and individual resources.

The v2 is essentially an entirely new system with a lot more features and a much better performance profile.

- [Documentation](https://waliaabhishek.github.io/chitragupta/)
- [Source Code](https://github.com/waliaabhishek/chitragupta)
