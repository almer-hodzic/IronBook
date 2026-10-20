namespace IronBook.Application.MemberProfiles;

public interface IMemberProfileService
{
    Task<MemberProfileDto?> GetAsync(CancellationToken cancellationToken = default);
    Task<MemberProfileUpdateResult> UpdateAsync(MemberProfileUpdateRequest request, CancellationToken cancellationToken = default);
}
