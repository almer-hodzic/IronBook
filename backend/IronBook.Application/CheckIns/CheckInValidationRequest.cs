namespace IronBook.Application.CheckIns;

public sealed record CheckInValidationRequest(string? QrAccessToken, int CenterId);
