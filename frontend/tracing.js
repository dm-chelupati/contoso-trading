// tracing.js — OpenTelemetry OTLP export to Dynatrace: traces + metrics + logs
const endpoint = process.env.DT_OTLP_ENDPOINT;
const token = process.env.DT_OTLP_TOKEN;

if (endpoint) {
  const { NodeSDK } = require('@opentelemetry/sdk-node');
  const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
  const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
  const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
  const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
  const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
  const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
  const { ExpressInstrumentation } = require('@opentelemetry/instrumentation-express');

  const base = endpoint.replace(/\/$/, '');
  const headers = { Authorization: `Api-Token ${token}` };

  const sdk = new NodeSDK({
    serviceName: 'frontend',
    traceExporter: new OTLPTraceExporter({ url: `${base}/v1/traces`, headers }),
    metricReader: new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter({ url: `${base}/v1/metrics`, headers }),
      exportIntervalMillis: 60000,
    }),
    logRecordProcessor: new BatchLogRecordProcessor(
      new OTLPLogExporter({ url: `${base}/v1/logs`, headers })
    ),
    instrumentations: [new HttpInstrumentation(), new ExpressInstrumentation()],
  });

  sdk.start();
  console.log(`OTEL: exporting traces+metrics+logs to ${endpoint}`);
} else {
  console.log('OTEL: DT_OTLP_ENDPOINT not set, skipping Dynatrace export');
}
