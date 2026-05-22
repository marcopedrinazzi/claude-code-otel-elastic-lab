#!/bin/sh
set -eu

ES_URL="${ES_URL:-http://elasticsearch:9200}"
KIBANA_URL="${KIBANA_URL:-http://kibana:5601}"
ELASTIC_USER="${ELASTIC_USER:-elastic}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-changeme}"
KIBANA_SYSTEM_PASSWORD="${KIBANA_SYSTEM_PASSWORD:-changeme_kibana}"
MAX_WAIT_ATTEMPTS="${MAX_WAIT_ATTEMPTS:-60}"
WAIT_SLEEP_SECONDS="${WAIT_SLEEP_SECONDS:-2}"

JSON_HEADER="Content-Type: application/json"
KBN_HEADER="kbn-xsrf: true"

validate_secret() {
  name="$1"
  value="$2"

  case "${value}" in
    ""|*[!A-Za-z0-9_.@%+=:-]*)
      echo "Invalid ${name}: use only characters A-Z, a-z, 0-9, underscore, dot, at, percent, plus, equals, colon, or dash." >&2
      exit 1
      ;;
  esac
}

validate_positive_integer() {
  name="$1"
  value="$2"

  case "${value}" in
    ""|*[!0-9]*)
      echo "Invalid ${name}: use a positive integer." >&2
      exit 1
      ;;
  esac

  if [ "${value}" -eq 0 ]; then
    echo "Invalid ${name}: use a positive integer." >&2
    exit 1
  fi
}

curl_es() {
  curl -fsS -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" "$@"
}

curl_kibana() {
  curl -fsS -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" "$@"
}

ensure_data_stream() {
  name="$1"

  status=$(curl -sS -o /dev/null -w "%{http_code}" -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" "${ES_URL}/_data_stream/${name}")
  if [ "${status}" = "200" ]; then
    return 0
  fi

  curl_es -X PUT "${ES_URL}/_data_stream/${name}" >/dev/null
}

set_data_stream_default_pipeline() {
  name="$1"
  pipeline="$2"

  curl_es -X PUT "${ES_URL}/${name}/_settings" \
    -H "${JSON_HEADER}" \
    -d "{\"index\":{\"default_pipeline\":\"${pipeline}\"}}" >/dev/null
}

delete_es_if_exists() {
  path="$1"

  status=$(curl -sS -o /dev/null -w "%{http_code}" -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" -X DELETE "${ES_URL}${path}")
  case "${status}" in
    200|404)
      return 0
      ;;
    400)
      echo "Warning: ${path} is still in use; leaving it in place." >&2
      return 0
      ;;
    *)
      echo "Error: failed deleting ${path}; Elasticsearch returned HTTP ${status}." >&2
      return 1
      ;;
  esac
}

delete_kibana_data_view_if_exists() {
  id="$1"

  status=$(curl -sS -o /dev/null -w "%{http_code}" -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
    -X DELETE "${KIBANA_URL}/api/data_views/data_view/${id}" \
    -H "${KBN_HEADER}")
  case "${status}" in
    200|204|404)
      return 0
      ;;
    *)
      echo "Error: failed deleting Kibana data view ${id}; Kibana returned HTTP ${status}." >&2
      return 1
      ;;
  esac
}

wait_until() {
  name="$1"
  shift
  attempt=1

  while [ "${attempt}" -le "${MAX_WAIT_ATTEMPTS}" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi

    if [ "${attempt}" -eq "${MAX_WAIT_ATTEMPTS}" ]; then
      echo "Error: timed out waiting for ${name} after ${MAX_WAIT_ATTEMPTS} attempts." >&2
      return 1
    fi

    sleep "${WAIT_SLEEP_SECONDS}"
    attempt=$((attempt + 1))
  done
}

validate_secret "ELASTIC_PASSWORD" "${ELASTIC_PASSWORD}"
validate_secret "KIBANA_SYSTEM_PASSWORD" "${KIBANA_SYSTEM_PASSWORD}"
validate_positive_integer "MAX_WAIT_ATTEMPTS" "${MAX_WAIT_ATTEMPTS}"
validate_positive_integer "WAIT_SLEEP_SECONDS" "${WAIT_SLEEP_SECONDS}"

echo "Waiting for Elasticsearch at ${ES_URL}"
wait_until "Elasticsearch health at ${ES_URL}" curl_es "${ES_URL}/_cluster/health?wait_for_status=yellow&timeout=5s"

echo "Setting kibana_system password"
curl_es -X POST "${ES_URL}/_security/user/kibana_system/_password" \
  -H "${JSON_HEADER}" \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}" >/dev/null

echo "Removing stale Claude Code traces templates"
delete_es_if_exists "/_index_template/traces-claude_code.otel"
delete_es_if_exists "/_component_template/traces-claude_code.otel@custom"

echo "Installing Claude Code logs ingest pipeline"
curl_es -X PUT "${ES_URL}/_ingest/pipeline/logs-claude_code.otel@custom" \
  -H "${JSON_HEADER}" \
  -d '{
    "description": "Parse JSON string fields in Claude Code OTel telemetry",
    "processors": [
      {
        "json": {
          "field": "attributes.tool_parameters",
          "target_field": "tool_parameters_flattened",
          "if": "ctx.attributes != null && ctx.attributes.tool_parameters instanceof String && ctx.attributes.tool_parameters.startsWith(\"{\")",
          "ignore_failure": true
        }
      },
      {
        "json": {
          "field": "attributes.tool_input",
          "target_field": "tool_input_flattened",
          "if": "ctx.attributes != null && ctx.attributes.tool_input instanceof String && ctx.attributes.tool_input.startsWith(\"{\")",
          "ignore_failure": true
        }
      }
    ]
  }' >/dev/null

echo "Installing Claude Code logs component template"
curl_es -X PUT "${ES_URL}/_component_template/logs-claude_code.otel@custom" \
  -H "${JSON_HEADER}" \
  -d '{
    "template": {
      "mappings": {
        "properties": {
          "attributes": {
            "type": "object",
            "subobjects": false,
            "properties": {
              "attempt": { "type": "long" },
              "cache_creation_tokens": { "type": "long" },
              "cache_read_tokens": { "type": "long" },
              "cost_usd": { "type": "float" },
              "duration_ms": { "type": "long" },
              "event.sequence": { "type": "long" },
              "input_tokens": { "type": "long" },
              "output_tokens": { "type": "long" },
              "prompt_length": { "type": "long" },
              "status_code": { "type": "long" },
              "success": { "type": "boolean" },
              "tool_input_size_bytes": { "type": "long" },
              "tool_result_size_bytes": { "type": "long" }
            }
          },
          "resource": {
            "properties": {
              "attributes": { "type": "object", "subobjects": false }
            }
          },
          "scope": {
            "properties": {
              "attributes": { "type": "object", "subobjects": false }
            }
          },
          "tool_input_flattened": { "type": "flattened" },
          "tool_parameters_flattened": { "type": "flattened" }
        }
      }
    }
  }' >/dev/null

echo "Installing Claude Code logs index template"
curl_es -X PUT "${ES_URL}/_index_template/logs-claude_code.otel" \
  -H "${JSON_HEADER}" \
  -d '{
    "index_patterns": [ "logs-claude_code.otel-*" ],
    "priority": 150,
    "data_stream": {},
    "allow_auto_create": true,
    "template": {
      "settings": {
        "index.default_pipeline": "logs-claude_code.otel@custom"
      }
    },
    "composed_of": [ "logs-claude_code.otel@custom" ]
  }' >/dev/null

echo "Ensuring Claude Code data streams exist"
ensure_data_stream "logs-claude_code.otel-default"
set_data_stream_default_pipeline "logs-claude_code.otel-default" "logs-claude_code.otel@custom"

echo "Waiting for Kibana at ${KIBANA_URL}"
wait_until "Kibana status at ${KIBANA_URL}" curl -fsS "${KIBANA_URL}/api/status"

echo "Removing stale Claude Code traces data view"
delete_kibana_data_view_if_exists "claude-code-traces"

echo "Creating Claude Code OTel logs data view"
curl_kibana -X POST "${KIBANA_URL}/api/data_views/data_view" \
  -H "${KBN_HEADER}" \
  -H "${JSON_HEADER}" \
  -d '{
    "data_view": {
      "id": "claude-code-otel",
      "title": "logs-claude_code.otel-*",
      "name": "Claude Code OTel",
      "timeFieldName": "@timestamp"
    },
    "override": true
  }' >/dev/null

echo "Elastic setup complete"
