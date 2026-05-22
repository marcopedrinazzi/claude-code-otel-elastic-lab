# Claude Code Elastic OTel Lab

This is a local lab I built to test Claude Code OpenTelemetry export with Elasticsearch/Kibana and to explore ideas for security detections and monitoring. I've documented the ideas I came up with [here](https://github.com/marcopedrinazzi/detection-rules/blob/main/ideas/otel-claude-code/otel-claude-code.md)

It is not production hardened. It is meant for local experimentation, schema inspection, and detection brainstorming.

## What It Runs

```text
Claude Code
  -> OpenTelemetry Collector
  -> Elasticsearch logs data stream
  -> Kibana Discover
```

Published ports bind to `127.0.0.1`.

| Service | Port | Purpose |
|---|---:|---|
| Elasticsearch | 9200 | Stores telemetry |
| Kibana | 5601 | Search and investigation |
| OTel Collector HTTP | 14318 | OTLP/HTTP logs endpoint |

## What This Lab Collects

The current profile is logs/events only:

- Claude Code OTel events through `OTEL_LOGS_EXPORTER=otlp`
- user prompt text with `OTEL_LOG_USER_PROMPTS=1`
- tool details with `OTEL_LOG_TOOL_DETAILS=1`
- no metrics
- no traces

Elastic stores the data with the OTel mapping shape, so most Claude Code fields are under `attributes.*`.

Useful fields:

```text
body.text
attributes.event.name
attributes.session.id
attributes.prompt.id
attributes.prompt
attributes.model
attributes.cost_usd
attributes.duration_ms
attributes.tool_name
attributes.tool_parameters
attributes.tool_input
tool_parameters_flattened
tool_input_flattened
```

The setup script also adds a small Elasticsearch ingest pipeline. It keeps raw OTel fields intact, maps common numeric fields for aggregation, and parses JSON tool payloads into `tool_parameters_flattened` and `tool_input_flattened`.

The Elasticsearch mapping and ingest-pipeline pieces follow the same idea described in Elastic Security Labs' [Monitoring Claude Code/Cowork at scale with OTel in Elastic](https://www.elastic.co/security-labs/claude-code-cowork-monitoring-otel-elastic): keep the OTel event stream, add numeric mappings for aggregation, and parse JSON tool payloads into searchable helper fields.

## Start

Create the local env file:

```bash
cp .env.example .env
```

Edit `.env` and set passwords.

Start the stack:

```bash
docker compose up -d
```

The `setup` container runs once to create the Elastic templates, ingest pipeline, logs data stream, and Kibana data view. To inspect the logs, do:

```bash
docker compose logs setup
```

Open Kibana:

```text
http://localhost:5601
```

Log in as `elastic` with `ELASTIC_PASSWORD` from `.env`.

## Send Claude Code Telemetry

Source the lab profile before starting Claude Code:

```bash
source setup/claude-code-env-otel.sh
claude
```

## Data View

Use the Kibana data view:

```text
Claude Code OTel
```

Backing data stream:

```text
logs-claude_code.otel-*
```

Claude Code event identity appears in two places:

```text
body.text: "claude_code.tool_result"
attributes.event.name: "tool_result"
```

Use `body.text` when you want the full Claude Code event name. Use `attributes.event.name` when the short event type is enough.
