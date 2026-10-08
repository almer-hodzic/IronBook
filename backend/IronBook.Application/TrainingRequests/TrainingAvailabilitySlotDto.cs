namespace IronBook.Application.TrainingRequests;

public sealed record TrainingAvailabilitySlotDto(
    DateTime StartsAt,
    string Date,
    string Time,
    string Period,
    bool IsAvailable,
    string Status);
