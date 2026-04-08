---
title: "JMX Monitoring Stacks"
date: 2022-05-01
description: "Reference monitoring stacks standardizing JMX-to-telemetry pipelines for Confluent Platform and Cloud."
tags: ["kafka", "observability", "prometheus", "grafana", "open-source"]
weight: 20
---

Most monitoring setups for Kafka require long and lengthy parsing configurations to get JMX metrics into your telemetry system. This project standardizes that pipeline across Prometheus/Grafana, New Relic, Elastic/Kibana, Datadog, and OpenTelemetry.

I've been one of the contributors on this project at Confluent. We built and maintained these stacks over several years, and they became the canonical observability quickstart for Confluent Platform and Cloud.

- [Source Code](https://github.com/confluentinc/jmx-monitoring-stacks)
