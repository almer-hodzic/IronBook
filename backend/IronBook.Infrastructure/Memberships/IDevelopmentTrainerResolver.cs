using IronBook.Domain.Entities;

namespace IronBook.Infrastructure.Memberships;

public interface IDevelopmentTrainerResolver
{
    Task<TrainerProfile?> ResolveAsync(
        int? trainerProfileId = null,
        CancellationToken cancellationToken = default);
}
