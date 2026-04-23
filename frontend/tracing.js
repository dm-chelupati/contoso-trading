// tracing.js — OpenTelemetry OTLP export to Dynatrace (active when DT_OTLP_ENDPOINT is set)
const endpoint = process.env.DT_OTLP_ENDPOINT;
const token = process.env.DT_OTLP_TOKEN;

if (endpoint) {
  const { NodeSDK } = require('@opentelemetry/sdk-node');
  const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
  const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
  const { ExpressInstrumentation } = require('@opentelemetry/instrumentation-express');

  const sdk = new NodeSDK({
    traceExporter: new OTLPTraceExporter({
      url: endpoint,
      headers: { Authorization: `Api-Token ${token}` },
    }),
    instrumentations: [new HttpInstrumentation(), new ExpressInstrumentation()],
    serviceName: 'frontend',
  });

  sdk.start();
  console.log(`OTEL: exporting traces to ${endpoint}`);
} else {
  console.log('OTEL: DT_OTLP_ENDPOINT not set, skipping Dynatrace export');
}
