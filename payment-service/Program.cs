using OpenTelemetry;
using OpenTelemetry.Trace;
using Npgsql;

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

var app = builder.Build();

var dbConn = Environment.GetEnvironmentVariable("DATABASE_URL") ?? "";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "payment-service" }));

app.MapGet("/payments", async () =>
{
    try
    {
        if (string.IsNullOrEmpty(dbConn))
            return Results.Ok(new { payments = new[] { new { id = 1, amount = 99.99, status = "completed" } }, source = "mock" });

        await using var conn = new NpgsqlConnection(dbConn);
        await conn.OpenAsync();
        return Results.Ok(new { payments = new[] { new { id = 1, amount = 99.99, status = "completed" } }, source = "database" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Database error: {ex.Message}", statusCode: 500);
    }
});

app.MapPost("/payments/process", async () =>
{
    // Simulate payment processing with occasional failures
    await Task.Delay(Random.Shared.Next(100, 500));
    if (Random.Shared.Next(100) < 5) // 5% failure rate
        return Results.Problem("Payment gateway timeout", statusCode: 504);
    return Results.Ok(new { status = "processed", transactionId = Guid.NewGuid() });
});

app.Run();
