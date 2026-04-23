using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
// Dynatrace OTLP export — traces + metrics + logs (active when DT_OTLP_ENDPOINT is set)
var dtEndpoint = Environment.GetEnvironmentVariable("DT_OTLP_ENDPOINT");
var dtToken = Environment.GetEnvironmentVariable("DT_OTLP_TOKEN");
if (!string.IsNullOrEmpty(dtEndpoint))
{
    var baseOtlp = dtEndpoint.TrimEnd('/');
    Action<OpenTelemetry.Exporter.OtlpExporterOptions> configureOtlp(string signal) => o =>
    {
        o.Endpoint = new Uri($"{baseOtlp}/v1/{signal}");
        o.Headers = $"Authorization=Api-Token {dtToken}";
        o.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.HttpProtobuf;
    };

    builder.Services.AddOpenTelemetry()
        .ConfigureResource(r => r.AddService("gateway"))
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(configureOtlp("traces")))
        .WithMetrics(metrics => metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(configureOtlp("metrics")));

    builder.Logging.AddOpenTelemetry(logging =>
    {
        logging.IncludeScopes = true;
        logging.IncludeFormattedMessage = true;
        logging.AddOtlpExporter(configureOtlp("logs"));
    });
}

builder.Services.AddHttpClient();
var app = builder.Build();

var orderUrl = Environment.GetEnvironmentVariable("ORDER_SERVICE_URL") ?? "http://localhost:8081";
var paymentUrl = Environment.GetEnvironmentVariable("PAYMENT_SERVICE_URL") ?? "http://localhost:8082";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "gateway" }));

app.MapGet("/api/orders", async (IHttpClientFactory http) =>
{
    try
    {
        var client = http.CreateClient();
        var response = await client.GetAsync($"{orderUrl}/orders");
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadAsStringAsync();
        return Results.Content(body, "application/json");
    }
    catch (Exception ex)
    {
        return Results.Problem($"Order service error: {ex.Message}", statusCode: 502);
    }
});

app.MapGet("/api/payments", async (IHttpClientFactory http) =>
{
    try
    {
        var client = http.CreateClient();
        var response = await client.GetAsync($"{paymentUrl}/payments");
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadAsStringAsync();
        return Results.Content(body, "application/json");
    }
    catch (Exception ex)
    {
        return Results.Problem($"Payment service error: {ex.Message}", statusCode: 502);
    }
});

app.Run();
