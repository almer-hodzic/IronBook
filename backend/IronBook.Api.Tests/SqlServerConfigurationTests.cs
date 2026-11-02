using IronBook.Infrastructure.Persistence;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace IronBook.Api.Tests;

public class SqlServerConfigurationTests
{
    [Theory]
    [InlineData(null)]
    [InlineData(" ")]
    [InlineData("Database=190027;Integrated Security=true")]
    [InlineData("Server=localhost;Integrated Security=true")]
    [InlineData("not-a-connection-string")]
    public void Missing_or_incomplete_database_configuration_fails_safely(string? connection)
    {
        var error = Assert.Throws<InvalidOperationException>(() => SqlServerConfiguration.RequireConnectionString(Config(connection)));
        Assert.Contains("ConnectionStrings:DefaultConnection", error.Message);
        Assert.Null(error.InnerException);
    }

    [Fact]
    public void Explicit_server_and_database_are_preserved_without_opening_a_connection()
    {
        const string connection = "Server=localhost,1433;Database=190027;Integrated Security=true;TrustServerCertificate=true";
        Assert.Equal(connection, SqlServerConfiguration.RequireConnectionString(Config(connection)));
    }

    [Fact]
    public void Malformed_connection_error_does_not_disclose_supplied_credentials()
    {
        var error = Assert.Throws<InvalidOperationException>(() => SqlServerConfiguration.RequireConnectionString(
            Config("Server=localhost;Database=190027;Password=\"test-only-private-marker")));
        Assert.DoesNotContain("test-only-private-marker", error.ToString());
        Assert.Null(error.InnerException);
    }

    private static IConfiguration Config(string? connection) => new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:DefaultConnection"] = connection }).Build();
}
