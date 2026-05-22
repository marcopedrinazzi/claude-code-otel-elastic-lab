export CLAUDE_CODE_ENABLE_TELEMETRY=1 # Enables telemetry collection 

export OTEL_LOGS_EXPORTER=otlp
export OTEL_LOGS_EXPORT_INTERVAL=1000
export OTEL_LOG_USER_PROMPTS=1 # Enable logging of user prompt content 
export OTEL_LOG_TOOL_DETAILS=1 # Enable logging of tool parameters and input arguments in tool events and trace span attributes: Bash commands, MCP server and tool names, skill names, and tool input. Also enables custom, plugin, and MCP command names on user_prompt events

export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
export OTEL_EXPORTER_OTLP_LOGS_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://localhost:14318/v1/logs
