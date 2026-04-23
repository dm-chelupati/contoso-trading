using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using Azure.Messaging.ServiceBus;

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
        .ConfigureResource(r => r.AddService("worker"))
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
