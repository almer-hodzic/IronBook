using IronBook.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace IronBook.Infrastructure.Persistence;

public class IronBookDbContext : DbContext
{
    public IronBookDbContext(DbContextOptions<IronBookDbContext> options)
        : base(options)
    {
    }

    public DbSet<Center> Centers => Set<Center>();
}
