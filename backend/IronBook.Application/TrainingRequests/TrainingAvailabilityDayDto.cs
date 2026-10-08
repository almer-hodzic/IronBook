namespace IronBook.Application.TrainingRequests;

public sealed record TrainingAvailabilityDayDto(
    string Date,
    string DayLabel,
    string DateLabel,
    string MonthLabel,
    IReadOnlyList<TrainingAvailabilitySlotDto> Slots);
