namespace IronBook.Application.Trainers;

public sealed record AdminTrainerCenterAssignmentDto(
    int CenterId,
    string CenterName,
    string Location);
