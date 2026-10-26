using System.ComponentModel.DataAnnotations;

namespace IronBook.Application.TrainingRequests;

// Existing clients may continue to send {} or no body.
public sealed record CoachingRequestActionRequest([MaxLength(1000)] string? Reason = null);
