namespace IronBook.Application.MemberProfiles;

public sealed record MemberProfileUpdateResult(
    MemberProfileDto? Profile,
    bool NotFound,
    IReadOnlyDictionary<string, string[]> Errors)
{
    public static MemberProfileUpdateResult Success(MemberProfileDto profile) => new(profile, false, new Dictionary<string, string[]>());
    public static MemberProfileUpdateResult Missing() => new(null, true, new Dictionary<string, string[]>());
    public static MemberProfileUpdateResult Invalid(IReadOnlyDictionary<string, string[]> errors) => new(null, false, errors);
}
