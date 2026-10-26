using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace IronBook.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddWorkflowIntegrity : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "CoachingRequestStatusHistory",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    TrainingRequestId = table.Column<int>(type: "int", nullable: false),
                    FromStatus = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    ToStatus = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    ChangedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ChangedByAccountId = table.Column<int>(type: "int", nullable: true),
                    Reason = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    FromTrainerProfileId = table.Column<int>(type: "int", nullable: false),
                    ToTrainerProfileId = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CoachingRequestStatusHistory", x => x.Id);
                    table.ForeignKey(
                        name: "FK_CoachingRequestStatusHistory_Accounts_ChangedByAccountId",
                        column: x => x.ChangedByAccountId,
                        principalTable: "Accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_CoachingRequestStatusHistory_TrainerProfiles_FromTrainerProfileId",
                        column: x => x.FromTrainerProfileId,
                        principalTable: "TrainerProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_CoachingRequestStatusHistory_TrainerProfiles_ToTrainerProfileId",
                        column: x => x.ToTrainerProfileId,
                        principalTable: "TrainerProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_CoachingRequestStatusHistory_TrainingRequests_TrainingRequestId",
                        column: x => x.TrainingRequestId,
                        principalTable: "TrainingRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_TrainingRequests_TrainerProfileId_Status_RequestedStartAt",
                table: "TrainingRequests",
                columns: new[] { "TrainerProfileId", "Status", "RequestedStartAt" });

            migrationBuilder.CreateIndex(
                name: "IX_Memberships_MemberProfileId_CenterId_MembershipPlanId",
                table: "Memberships",
                columns: new[] { "MemberProfileId", "CenterId", "MembershipPlanId" },
                unique: true,
                filter: "[Status] IN ('Active', 'Pending')");

            migrationBuilder.CreateIndex(
                name: "IX_CoachingRequestStatusHistory_ChangedByAccountId",
                table: "CoachingRequestStatusHistory",
                column: "ChangedByAccountId");

            migrationBuilder.CreateIndex(
                name: "IX_CoachingRequestStatusHistory_FromTrainerProfileId",
                table: "CoachingRequestStatusHistory",
                column: "FromTrainerProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_CoachingRequestStatusHistory_ToTrainerProfileId",
                table: "CoachingRequestStatusHistory",
                column: "ToTrainerProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_CoachingRequestStatusHistory_TrainingRequestId_ChangedAt",
                table: "CoachingRequestStatusHistory",
                columns: new[] { "TrainingRequestId", "ChangedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "CoachingRequestStatusHistory");

            migrationBuilder.DropIndex(
                name: "IX_TrainingRequests_TrainerProfileId_Status_RequestedStartAt",
                table: "TrainingRequests");

            migrationBuilder.DropIndex(
                name: "IX_Memberships_MemberProfileId_CenterId_MembershipPlanId",
                table: "Memberships");
        }
    }
}
