using IronBook.Domain.Enums;

namespace IronBook.Domain.Entities;

public class GroupTrainingEnrollment
{
    public int Id { get; set; }

    public int GroupTrainingId { get; set; }

    public int MemberProfileId { get; set; }

    public GroupTrainingEnrollmentStatus Status { get; set; } = GroupTrainingEnrollmentStatus.Enrolled;

    public DateTime EnrolledAt { get; set; } = DateTime.UtcNow;

    public GroupTraining GroupTraining { get; set; } = null!;

    public MemberProfile MemberProfile { get; set; } = null!;
}
