using System.Security.Cryptography;
using IronBook.Api.Notifications;
using IronBook.Domain.Entities;
using IronBook.Domain.Security;
using IronBook.Infrastructure.Auth;
using IronBook.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

namespace IronBook.Api.Tests;

public sealed class AuthFactory : WebApplicationFactory<Program>
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    public string SigningKey { get; } = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
    public const string Issuer = "IronBookAuthTests";
    public const string Audience = "IronBookAuthTestClients";

    public AuthFactory()
    {
        _connection.Open();
        _connection.CreateCollation("Latin1_General_100_CI_AS", (left, right) =>
            string.Compare(left, right, StringComparison.OrdinalIgnoreCase));
        _connection.CreateCollation("Latin1_General_100_BIN2", (left, right) =>
            string.Compare(left, right, StringComparison.Ordinal));
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<IronBookDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<IronBookDbContext>>();
            services.AddDbContext<IronBookDbContext>(options => options.UseSqlite(_connection));
            var dispatcher = services.Single(descriptor => descriptor.ServiceType == typeof(IHostedService)
                && descriptor.ImplementationType == typeof(NotificationOutboxDispatcher));
            services.Remove(dispatcher);
            services.PostConfigure<JwtOptions>(options =>
            {
                options.Issuer = Issuer;
                options.Audience = Audience;
                options.SigningKey = SigningKey;
                options.ExpirationMinutes = 30;
            });
        });
    }

    public async Task SeedAsync()
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IronBookDbContext>();
        await db.Database.EnsureCreatedAsync();
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Account>>();
        var member = new MemberProfile { FirstName = "Seed", LastName = "Member", Email = "member@example.invalid" };
        var trainer = new TrainerProfile { FirstName = "Seed", LastName = "Trainer", Email = "trainer@example.invalid" };
        Account[] accounts =
        [
            new() { Username = "admin", Role = AppRoles.Admin },
            new() { Username = "member", Role = AppRoles.Member, MemberProfile = member },
            new() { Username = "trainer", Role = AppRoles.Trainer, TrainerProfile = trainer }
        ];
        foreach (var account in accounts)
        {
            account.PasswordHash = hasher.HashPassword(account, "test");
            db.Accounts.Add(account);
        }
        await db.SaveChangesAsync();
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) _connection.Dispose();
    }
}
