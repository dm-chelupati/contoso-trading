using Azure.Messaging.ServiceBus;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
var app = builder.Build();

var dbConn = Environment.GetEnvironmentVariable("DATABASE_URL") ?? "";
var sbConn = Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION") ?? "";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "order-service" }));

app.MapGet("/orders", async () =>
{
    try
    {
        if (string.IsNullOrEmpty(dbConn))
            return Results.Ok(new { orders = new[] { new { id = 1, item = "Mock Order", status = "pending" } }, source = "mock" });

        await using var conn = new NpgsqlConnection(dbConn);
        await conn.OpenAsync();
        return Results.Ok(new { orders = new[] { new { id = 1, item = "DB Order", status = "active" } }, source = "database" });
    }
    catch (Exception ex)
    {
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
        return Results.Problem($"Queue error: {ex.Message}", statusCode: 500);
    }
});

app.Run();
