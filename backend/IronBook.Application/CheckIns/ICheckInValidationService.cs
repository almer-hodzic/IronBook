namespace IronBook.Application.CheckIns;

public interface ICheckInValidationService
{
    Task<CheckInValidationResult> ValidateAsync(
        CheckInValidationRequest request,
        CancellationToken cancellationToken = default);
}
