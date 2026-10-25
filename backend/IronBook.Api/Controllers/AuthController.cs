using IronBook.Application.Auth;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/auth")]
public sealed class AuthController(IAuthService authService, ILogoutService logoutService,
    IChangePasswordService changePasswordService) : ControllerBase
{
    [HttpPost("change-password")]
    [Authorize]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest request, CancellationToken cancellationToken)
    {
        var result = await changePasswordService.ChangeAsync(request, cancellationToken);
        if (result.AccountMissing) return Unauthorized();
        if (result.Succeeded) return NoContent();
        foreach (var error in result.Errors)
            foreach (var message in error.Value)
                ModelState.AddModelError(error.Key, message);
        return ValidationProblem(ModelState);
    }

    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout(CancellationToken cancellationToken) =>
        await logoutService.LogoutAsync(cancellationToken) ? NoContent() : Unauthorized();

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<ActionResult<LoginResponse>> Login(LoginRequest request, CancellationToken cancellationToken)
    {
        var response = await authService.LoginAsync(request, cancellationToken);
        return response is null
            ? Unauthorized(new ProblemDetails { Status = 401, Title = "Invalid username or password." })
            : Ok(response);
    }
}
