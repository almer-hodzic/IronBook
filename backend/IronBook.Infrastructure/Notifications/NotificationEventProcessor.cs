using IronBook.Application.Notifications;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Persistence;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Notifications;

public sealed class NotificationEventProcessor
{
    private readonly IronBookDbContext _dbContext;

    public NotificationEventProcessor(IronBookDbContext dbContext) => _dbContext = dbContext;

    public async Task ProcessAsync(CoachingRequestNotificationEvent message, CancellationToken cancellationToken)
    {
        if (message.EventId == Guid.Empty || message.MemberProfileId <= 0 || message.TrainingRequestId <= 0 ||
            string.IsNullOrWhiteSpace(message.TrainerName) || message.TrainerName.Length > 201 ||
            string.IsNullOrWhiteSpace(message.CenterName) || message.CenterName.Length > 200 ||
            message.OccurredAt == default || message.RequestedStartAt == default)
        {
            throw new InvalidDataException("Invalid coaching request notification event.");
        }

        var action = message.Action switch
        {
            "Approved" => "approved",
            "Rejected" => "rejected",
            "Cancelled" => "cancelled",
            "Reassigned" => "reassigned",
            _ => throw new InvalidDataException("Unknown coaching request notification action.")
        };

        if (await _dbContext.Notifications.AnyAsync(notification => notification.EventId == message.EventId, cancellationToken))
            return;

        if (!await _dbContext.TrainingRequests.AnyAsync(request =>
                request.Id == message.TrainingRequestId && request.MemberProfileId == message.MemberProfileId, cancellationToken))
            throw new InvalidDataException("The event does not identify an existing member coaching request.");

        _dbContext.Notifications.Add(new Notification
        {
            EventId = message.EventId,
            MemberProfileId = message.MemberProfileId,
            TrainingRequestId = message.TrainingRequestId,
            Title = $"Coaching request {action}",
            Message = $"Your coaching request #{message.TrainingRequestId} at {message.CenterName} " +
                $"for {message.RequestedStartAt:yyyy-MM-dd HH:mm} UTC with {message.TrainerName} was {action}.",
            CreatedAt = message.OccurredAt,
            IsRead = false
        });
        try
        {
            await _dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (exception.InnerException is SqlException { Number: 2601 or 2627 })
        {
            // Another consumer may have saved this delivery first.
            if (!await _dbContext.Notifications.AsNoTracking().AnyAsync(
                    notification => notification.EventId == message.EventId, cancellationToken)) throw;
        }
    }
}
