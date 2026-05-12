using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using Azure.Messaging.ServiceBus;
using Npgsql;

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
        .ConfigureResource(r => r.AddService("order-service"))
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

var app = builder.Build();
var logger = app.Logger;

var sbConn = Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION") ?? "";

// Read DATABASE_URL per-request so a container restart after secret update takes effect immediately.
string GetDatabaseUrl() => Environment.GetEnvironmentVariable("DATABASE_URL") ?? "";

// Open a Npgsql connection with retry + exponential back-off.
async Task<NpgsqlConnection> OpenConnectionWithRetryAsync(string connectionString, int maxRetries = 3)
{
    for (int attempt = 1; attempt <= maxRetries; attempt++)
    {
        try
        {
            var conn = new NpgsqlConnection(connectionString);
            await conn.OpenAsync();
            return conn;
        }
        catch (NpgsqlException ex) when (attempt < maxRetries)
        {
            var delay = attempt * 500;
            logger.LogWarning(ex,
                "Database connection attempt {Attempt}/{MaxRetries} failed (SqlState={SqlState}): {Error}. Retrying in {Delay}ms...",
                attempt, maxRetries, ex.SqlState, ex.Message, delay);
            await Task.Delay(delay);
        }
    }
    // Final attempt — let the exception propagate.
    var final = new NpgsqlConnection(connectionString);
    await final.OpenAsync();
    return final;
}

app.MapGet("/health", async () =>
{
    var dbUrl = GetDatabaseUrl();
    if (string.IsNullOrEmpty(dbUrl))
        return Results.Ok(new { status = "healthy", service = "order-service", database = "not-configured" });

    try
    {
        await using var conn = new NpgsqlConnection(dbUrl);
        await conn.OpenAsync();
        return Results.Ok(new { status = "healthy", service = "order-service", database = "connected" });
    }
    catch (Exception ex)
    {
        logger.LogWarning(ex, "Health check: database connectivity failed: {ErrorMessage}", ex.Message);
        return Results.Json(
            new { status = "degraded", service = "order-service", database = "disconnected", error = ex.Message },
            statusCode: 503);
    }
});

app.MapGet("/orders", async () =>
{
    try
    {
        var dbUrl = GetDatabaseUrl();
        if (string.IsNullOrEmpty(dbUrl))
            return Results.Ok(new { orders = new[] { new { id = 1, item = "Mock Order", status = "pending" } }, source = "mock" });

        await using var conn = await OpenConnectionWithRetryAsync(dbUrl);
        return Results.Ok(new { orders = new[] { new { id = 1, item = "DB Order", status = "active" } }, source = "database" });
    }
    catch (NpgsqlException ex) when (ex.SqlState == "28P01" || ex.SqlState == "28000")
    {
        logger.LogError(ex,
            "Database authentication failed on GET /orders. "
            + "This typically occurs after a password rotation when the container app secret has not been updated. "
            + "SqlState={SqlState}, Error={ErrorMessage}",
            ex.SqlState, ex.Message);
        return Results.Problem(
            "Database authentication failed. The database credential may be stale after a recent password rotation.",
            statusCode: 500);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Database error on GET /orders: {ErrorMessage}", ex.Message);
        return Results.Problem($"Database error: {ex.Message}", statusCode: 500);
    }
});

app.MapPost("/orders", async () =>
{
    try
    {
        // Publish to Service Bus queue
        if (!string.IsNullOrEmpty(sbConn))
        {
            await using var client = new ServiceBusClient(sbConn);
            var sender = client.CreateSender("orders");
            await sender.SendMessageAsync(new ServiceBusMessage($"{{\"orderId\": \"{Guid.NewGuid()}\"}}"));
        }
        return Results.Ok(new { status = "created", message = "Order queued for processing" });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Queue error on POST /orders: {ErrorMessage}", ex.Message);
        return Results.Problem($"Queue error: {ex.Message}", statusCode: 500);
    }
});

app.Run();
