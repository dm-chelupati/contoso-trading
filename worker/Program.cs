using OpenTelemetry;
using OpenTelemetry.Trace;
using Azure.Messaging.ServiceBus;

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

var sbConn = Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION") ?? "";
var isWorker = Environment.GetEnvironmentVariable("WORKER_MODE") == "true";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "worker", processing = isWorker }));

// Start background queue processing
if (isWorker && !string.IsNullOrEmpty(sbConn))
{
    _ = Task.Run(async () =>
    {
        var client = new ServiceBusClient(sbConn);
        var processor = client.CreateProcessor("orders", new ServiceBusProcessorOptions { MaxConcurrentCalls = 5 });

        processor.ProcessMessageAsync += async args =>
        {
            var body = args.Message.Body.ToString();
            Console.WriteLine($"Processing order: {body}");
            await Task.Delay(Random.Shared.Next(500, 2000)); // Simulate work
            await args.CompleteMessageAsync(args.Message);
            Console.WriteLine($"Order completed: {body}");
        };

        processor.ProcessErrorAsync += args =>
        {
            Console.Error.WriteLine($"Queue error: {args.Exception.Message}");
            return Task.CompletedTask;
        };

        await processor.StartProcessingAsync();
        Console.WriteLine("Worker started processing orders queue");
        await Task.Delay(Timeout.Infinite);
    });
}

app.Run();
