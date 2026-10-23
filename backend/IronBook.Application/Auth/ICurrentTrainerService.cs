using IronBook.Domain.Entities;

namespace IronBook.Application.Auth;

public interface ICurrentTrainerService
{
    Task<TrainerProfile?> ResolveAsync(CancellationToken cancellationToken = default);
}
