using System.Security.Claims;
using IronBook.Application.Auth;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Memberships;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace IronBook.Api.Tests;

public class CurrentTrainerIdentityTests
{
    [Fact]
    public async Task Trainer_resolves_only_persistent_linked_profile_without_tracking_or_creating_sessions()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.AsNoTracking().SingleAsync(row => row.Username == "trainer");
        var service = new CurrentTrainerService(db, new AccountContext(account.Id, AppRoles.Trainer));
        var profile = await service.ResolveAsync();
        Assert.NotNull(profile);
        Assert.Equal(account.TrainerProfileId, profile.Id);
        Assert.True(profile.IsActive);
        Assert.Empty(db.ChangeTracker.Entries());
        Assert.Empty(await db.AuthSessions.ToListAsync());
    }

    [Theory]
    [InlineData("no-account")]
    [InlineData("zero-account")]
    [InlineData("negative-account")]
    [InlineData("missing-account")]
    [InlineData("admin")]
    [InlineData("member")]
    [InlineData("missing-role")]
    [InlineData("wrong-context-role")]
    [InlineData("stored-role-mismatch")]
    [InlineData("inactive-account")]
    [InlineData("missing-link")]
    [InlineData("invalid-link")]
    [InlineData("inactive-profile")]
    public async Task Invalid_current_Trainer_states_return_null_safely(string scenario)
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.Include(row => row.TrainerProfile).SingleAsync(row => row.Username == "trainer");
        int? accountId = account.Id;
        string? role = AppRoles.Trainer;
        switch (scenario)
        {
            case "no-account": accountId = null; break;
            case "zero-account": accountId = 0; break;
            case "negative-account": accountId = -1; break;
            case "missing-account": accountId = int.MaxValue; break;
            case "admin":
                accountId = (await db.Accounts.SingleAsync(row => row.Username == "admin")).Id;
                role = AppRoles.Admin;
                break;
            case "member":
                accountId = (await db.Accounts.SingleAsync(row => row.Username == "member")).Id;
                role = AppRoles.Member;
                break;
            case "missing-role": role = null; break;
            case "wrong-context-role": role = AppRoles.Member; break;
            case "stored-role-mismatch":
                accountId = (await db.Accounts.SingleAsync(row => row.Username == "admin")).Id;
                break;
            case "inactive-account": account.IsActive = false; break;
            case "inactive-profile": account.TrainerProfile!.IsActive = false; break;
        }
        if (scenario is "missing-link" or "invalid-link")
        {
            // SQL constraints normally prevent these states. Relax them only on this
            // isolated in-memory SQLite database to exercise defensive resolution.
            await db.Database.ExecuteSqlRawAsync("PRAGMA foreign_keys = OFF; PRAGMA ignore_check_constraints = ON;");
            try
            {
                account.TrainerProfile = null;
                account.TrainerProfileId = scenario == "missing-link" ? null : int.MaxValue;
                await db.SaveChangesAsync();
            }
            finally
            {
                await db.Database.ExecuteSqlRawAsync("PRAGMA foreign_keys = ON; PRAGMA ignore_check_constraints = OFF;");
            }
        }
        else
        {
            await db.SaveChangesAsync();
        }
        var service = new CurrentTrainerService(db, new AccountContext(accountId, role));
        Assert.Null(await service.ResolveAsync());
        Assert.Empty(await db.AuthSessions.ToListAsync());
    }

    [Fact]
    public async Task Editable_email_names_phone_and_biography_do_not_change_identity()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.Include(row => row.TrainerProfile).SingleAsync(row => row.Username == "trainer");
        var service = new CurrentTrainerService(db, new AccountContext(account.Id, AppRoles.Trainer));
        var originalId = (await service.ResolveAsync())!.Id;
        var profile = account.TrainerProfile!;
        profile.Email = "changed@example.invalid";
        profile.FirstName = "Edited";
        profile.LastName = "Trainer";
        profile.PhoneNumber = "123456";
        profile.Biography = "Edited biography";
        // A different profile now has the development email, but is not this Account's profile.
        db.TrainerProfiles.Add(new TrainerProfile
            { FirstName = "Other", LastName = "Trainer", Email = "trainer@ironbook.local" });
        await db.SaveChangesAsync();
        var resolved = (await service.ResolveAsync())!;
        Assert.Equal(originalId, resolved.Id);
        Assert.Equal(profile.Email, resolved.Email);
        Assert.Equal(profile.FirstName, resolved.FirstName);
        Assert.Equal(profile.LastName, resolved.LastName);
        Assert.Equal(profile.PhoneNumber, resolved.PhoneNumber);
        Assert.Equal(profile.Biography, resolved.Biography);
    }

    [Fact]
    public async Task Resolution_follows_persistent_Account_link_instead_of_cached_profile_or_names()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.Include(row => row.TrainerProfile).SingleAsync(row => row.Username == "trainer");
        var service = new CurrentTrainerService(db, new AccountContext(account.Id, AppRoles.Trainer));
        var before = (await service.ResolveAsync())!.Id;
        var linked = new TrainerProfile { FirstName = "New", LastName = "Linked", Email = "linked@example.invalid" };
        account.TrainerProfile = linked;
        account.Username = "renamed-trainer";
        await db.SaveChangesAsync();
        var resolved = (await service.ResolveAsync())!;
        Assert.Equal(linked.Id, resolved.Id);
        Assert.NotEqual(before, resolved.Id);
    }

    [Fact]
    public async Task Scoped_DI_uses_existing_authenticated_current_Account_context()
    {
        using var factory = new AuthFactory();
        await factory.SeedAsync();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        var account = await db.Accounts.AsNoTracking().SingleAsync(row => row.Username == "trainer");
        var accessor = scope.ServiceProvider.GetRequiredService<IHttpContextAccessor>();
        var context = new DefaultHttpContext();
        accessor.HttpContext = context;
        try
        {
            var service = scope.ServiceProvider.GetRequiredService<ICurrentTrainerService>();
            Assert.IsType<CurrentTrainerService>(service);
            Assert.Same(service, scope.ServiceProvider.GetRequiredService<ICurrentTrainerService>());
            Assert.Null(await service.ResolveAsync());
            context.User = new ClaimsPrincipal(new ClaimsIdentity(
                [new Claim("sub", account.Id.ToString()), new Claim("role", AppRoles.Trainer)], "Test"));
            Assert.Equal(account.TrainerProfileId, (await service.ResolveAsync())!.Id);
            // Claims without an authenticated identity do not establish a current Account.
            context.User = new ClaimsPrincipal(new ClaimsIdentity(context.User.Claims));
            Assert.Null(await service.ResolveAsync());
        }
        finally
        {
            accessor.HttpContext = null;
        }
    }

    [Fact]
    public void Current_Trainer_service_has_no_development_resolver_or_client_profile_ID_dependency()
    {
        var parameters = Assert.Single(typeof(CurrentTrainerService).GetConstructors()).GetParameters();
        Assert.Contains(parameters, parameter => parameter.ParameterType == typeof(ICurrentAccountContext));
        Assert.DoesNotContain(parameters, parameter => parameter.ParameterType == typeof(IDevelopmentTrainerResolver));
        var method = typeof(ICurrentTrainerService).GetMethod("ResolveAsync")!;
        Assert.Equal(typeof(CancellationToken), Assert.Single(method.GetParameters()).ParameterType);
    }

    private sealed record AccountContext(int? AccountId, string? Role) : ICurrentAccountContext;
}
