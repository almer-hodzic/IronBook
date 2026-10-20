using System.ComponentModel.DataAnnotations;
using IronBook.Application.MemberProfiles;
using IronBook.Domain.Entities;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.MemberProfiles;

public sealed class MemberProfileService : IMemberProfileService
{
    private readonly IronBookDbContext _dbContext;
    private readonly IDevelopmentMemberResolver _memberResolver;

    public MemberProfileService(IronBookDbContext dbContext, IDevelopmentMemberResolver memberResolver)
    {
        _dbContext = dbContext;
        _memberResolver = memberResolver;
    }

    public async Task<MemberProfileDto?> GetAsync(CancellationToken cancellationToken = default)
    {
        var member = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        return member is null ? null : ToDto(member);
    }

    public async Task<MemberProfileUpdateResult> UpdateAsync(
        MemberProfileUpdateRequest request, CancellationToken cancellationToken = default)
    {
        var firstName = request.FirstName?.Trim();
        var lastName = request.LastName?.Trim();
        var email = request.Email?.Trim();
        var phoneNumber = request.PhoneNumber?.Trim();
        var errors = new Dictionary<string, string[]>();

        ValidateRequired(firstName, "FirstName", "First name", 100, errors);
        ValidateRequired(lastName, "LastName", "Last name", 100, errors);
        ValidateRequired(email, "Email", "Email", 200, errors);
        if (!string.IsNullOrEmpty(email) && !errors.ContainsKey("Email") &&
            (!new EmailAddressAttribute().IsValid(email) || email.Any(char.IsWhiteSpace)))
        {
            errors["Email"] = ["Enter a valid email address."];
        }
        if (phoneNumber is { Length: > 50 })
            errors["PhoneNumber"] = ["Phone number must be 50 characters or fewer."];
        if (errors.Count > 0) return MemberProfileUpdateResult.Invalid(errors);

        var resolvedMember = await _memberResolver.ResolveAsync(cancellationToken: cancellationToken);
        if (resolvedMember is null) return MemberProfileUpdateResult.Missing();

        var member = await _dbContext.MemberProfiles.AsTracking()
            .SingleOrDefaultAsync(member => member.Id == resolvedMember.Id, cancellationToken);
        if (member is null) return MemberProfileUpdateResult.Missing();

        member.FirstName = firstName!;
        member.LastName = lastName!;
        member.Email = email!;
        member.PhoneNumber = string.IsNullOrEmpty(phoneNumber) ? null : phoneNumber;
        await _dbContext.SaveChangesAsync(cancellationToken);
        return MemberProfileUpdateResult.Success(ToDto(member));
    }

    private static void ValidateRequired(string? value, string field, string label, int maxLength,
        Dictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(value)) errors[field] = [$"{label} is required."];
        else if (value.Length > maxLength) errors[field] = [$"{label} must be {maxLength} characters or fewer."];
    }

    private static MemberProfileDto ToDto(MemberProfile member) => new(
        member.Id, member.FirstName, member.LastName, member.Email,
        member.PhoneNumber, member.IsActive, member.CreatedAt);
}
