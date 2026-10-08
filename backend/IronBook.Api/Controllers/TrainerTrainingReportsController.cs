using IronBook.Application.TrainingReports;
using Microsoft.AspNetCore.Mvc;

namespace IronBook.Api.Controllers;

[ApiController]
[Route("api/trainer")]
public sealed class TrainerTrainingReportsController : ControllerBase
{
    private readonly ITrainerTrainingReportService _trainingReportService;

    public TrainerTrainingReportsController(
        ITrainerTrainingReportService trainingReportService)
    {
        _trainingReportService = trainingReportService;
    }

    [HttpPost("training-reports")]
    public async Task<ActionResult<TrainingReportDto>> CreateTrainingReport(
        [FromBody] TrainingReportCreateRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _trainingReportService.CreateAsync(
            request,
            cancellationToken);

        if (result.Succeeded)
        {
            return Created(string.Empty, result.Report);
        }

        foreach (var error in result.Errors)
        {
            ModelState.AddModelError(error.Field, error.Message);
        }

        if (result.NotFound)
        {
            return NotFound(new ValidationProblemDetails(ModelState));
        }

        if (result.Conflict)
        {
            return Conflict(new ValidationProblemDetails(ModelState));
        }

        return ValidationProblem(ModelState);
    }
}
