using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace IronBook.Infrastructure.Persistence;

public static class SqlServerConfiguration
{
    public static string RequireConnectionString(IConfiguration configuration)
    {
        var value = configuration.GetConnectionString("DefaultConnection");
        if (!string.IsNullOrWhiteSpace(value))
        {
            try
            {
                var parsed = new SqlConnectionStringBuilder(value);
                if (!string.IsNullOrWhiteSpace(parsed.DataSource) && !string.IsNullOrWhiteSpace(parsed.InitialCatalog))
                    return value;
            }
            catch (ArgumentException) { }
        }

        // Supplied strings and parser exceptions can contain credentials; never include either.
        throw new InvalidOperationException(
            "Configure ConnectionStrings:DefaultConnection with a valid SQL Server connection string containing Server and Database.");
    }
}
