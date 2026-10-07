namespace IronBook.Application.CheckIns;

public sealed record CheckInValidationDto(
    int CheckInId,
    DateTime CheckedInAt,
    int MembershipId,
    int CenterId,
    string CenterName,
    string MemberName,
    string AccessResult);
