using System.Text;
using IronBook.Application.Auth;
using IronBook.Infrastructure.Auth;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace IronBook.Api.Auth;

public static class JwtAuthenticationExtensions
{
    public static IServiceCollection AddIronBookJwtAuthentication(this IServiceCollection services)
    {
        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
        services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
            .Configure<IOptions<JwtOptions>>((options, settings) =>
            {
                var jwt = settings.Value;
                options.MapInboundClaims = false;
                options.IncludeErrorDetails = false;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true,
                    RequireSignedTokens = true,
                    IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
                    ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                    ValidateIssuer = true,
                    ValidIssuer = jwt.Issuer,
                    ValidateAudience = true,
                    ValidAudience = jwt.Audience,
                    ValidateLifetime = true,
                    RequireExpirationTime = true,
                    ClockSkew = TimeSpan.Zero,
                    NameClaimType = "unique_name",
                    RoleClaimType = "role"
                };
                options.Events = new JwtBearerEvents
                {
                    OnTokenValidated = async context =>
                    {
                        var validator = context.HttpContext.RequestServices.GetRequiredService<IAuthSessionValidator>();
                        if (context.Principal is null
                            || !await validator.IsValidAsync(context.Principal, context.HttpContext.RequestAborted))
                            context.Fail("Invalid authentication session.");
                    }
                };
            });
        // No fallback policy: only explicitly attributed Admin controllers are protected.
        services.AddAuthorization();
        return services;
    }
}
