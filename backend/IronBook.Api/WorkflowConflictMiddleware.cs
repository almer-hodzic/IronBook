using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Api;

// Convert SQL contention/unique-constraint failures only on the hardened mutation routes.
public sealed class WorkflowConflictMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try { await next(context); }
        catch (Exception error) when (!context.Response.HasStarted && IsWorkflowMutation(context)
            && (error as SqlException ?? (error as DbUpdateException)?.InnerException as SqlException)
                is { Number: 51000 or 1205 or 2601 or 2627 })
        {
            context.Response.Clear();
            context.Response.StatusCode = StatusCodes.Status409Conflict;
            await context.Response.WriteAsJsonAsync(new { message = "The operation conflicts with another change. Refresh and try again." });
        }
    }

    private static bool IsWorkflowMutation(HttpContext context) =>
        (HttpMethods.IsPut(context.Request.Method) && context.Request.Path.StartsWithSegments("/api/admin/group-trainings"))
        || (HttpMethods.IsPost(context.Request.Method)
        && (context.Request.Path.StartsWithSegments("/api/admin/coaching-requests")
            || context.Request.Path.StartsWithSegments("/api/member/my-trainings")
            || context.Request.Path == "/api/admin/group-trainings"
            || context.Request.Path == "/api/trainer/training-reports"
            || context.Request.Path == "/api/memberships/checkout"
            || context.Request.Path.Value?.EndsWith("/enroll", StringComparison.Ordinal) == true
            || context.Request.Path.Value?.EndsWith("/training-requests", StringComparison.Ordinal) == true));
}
