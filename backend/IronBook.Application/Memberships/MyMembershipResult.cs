namespace IronBook.Application.Memberships;

public sealed class MyMembershipResult
{
    private MyMembershipResult(MyMembershipDto? membership, string? message)
    {
        Membership = membership;
        Message = message;
    }

    public MyMembershipDto? Membership { get; }

    public string? Message { get; }

    public bool Found => Membership is not null;

    public static MyMembershipResult Success(MyMembershipDto membership) => new(membership, null);

    public static MyMembershipResult Missing(string message) => new(null, message);
}
