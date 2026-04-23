using OpenTelemetry;
using OpenTelemetry.Trace;
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
// Dynatrace OTLP export (active when DT_OTLP_ENDPOINT is set)
var dtEndpoint = Environment.GetEnvironmentVariable("DT_OTLP_ENDPOINT");
var dtToken = Environment.GetEnvironmentVariable("DT_OTLP_TOKEN");
if (!string.IsNullOrEmpty(dtEndpoint))
{
    builder.Services.AddOpenTelemetry()
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(o =>
            {
                o.Endpoint = new Uri(dtEndpoint);
                o.Headers = $"Authorization=Api-Token {dtToken}";
                o.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.HttpProtobuf;
            }));
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
