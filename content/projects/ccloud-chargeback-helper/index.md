---
title: "CCloud Chargeback Helper"
date: 2024-01-01
description: "A helper tool for Confluent Cloud cost allocation and showback."
tags: ["kafka", "finops", "observability", "open-source"]
weight: 10
---

When multiple teams share a Confluent Cloud environment but a single CoE team manages everything, the billing question comes up fast: who's actually using what, and how much does it cost?

This tool correlates Confluent Cloud Billing, Metrics, and Core Objects APIs to produce hourly, identity-level chargeback and showback datasets. Cost attribution goes all the way down to service accounts, users, API keys, and individual resources.

This project has since been superseded by [Chitragupta](/projects/chitragupta/), a complete rewrite with a plugin architecture and support for additional ecosystems beyond Confluent Cloud.

- [Source Code](https://github.com/waliaabhishek/chitragupta)