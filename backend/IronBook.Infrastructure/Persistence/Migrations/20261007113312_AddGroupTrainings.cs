using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace IronBook.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddGroupTrainings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "GroupTrainings",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CenterId = table.Column<int>(type: "int", nullable: false),
                    TrainerProfileId = table.Column<int>(type: "int", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(150)", maxLength: 150, nullable: false),
                    Description = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    Category = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    Difficulty = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    StartsAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    DurationMinutes = table.Column<int>(type: "int", nullable: false),
                    Capacity = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    Includes = table.Column<string>(type: "nvarchar(2000)", maxLength: 2000, nullable: true),
                    WhoFor = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_GroupTrainings", x => x.Id);
                    table.ForeignKey(
                        name: "FK_GroupTrainings_Centers_CenterId",
                        column: x => x.CenterId,
                        principalTable: "Centers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_GroupTrainings_TrainerProfiles_TrainerProfileId",
                        column: x => x.TrainerProfileId,
                        principalTable: "TrainerProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "GroupTrainingEnrollments",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    GroupTrainingId = table.Column<int>(type: "int", nullable: false),
                    MemberProfileId = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    EnrolledAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_GroupTrainingEnrollments", x => x.Id);
                    table.ForeignKey(
                        name: "FK_GroupTrainingEnrollments_GroupTrainings_GroupTrainingId",
                        column: x => x.GroupTrainingId,
                        principalTable: "GroupTrainings",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_GroupTrainingEnrollments_MemberProfiles_MemberProfileId",
                        column: x => x.MemberProfileId,
                        principalTable: "MemberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_GroupTrainingEnrollments_GroupTrainingId",
                table: "GroupTrainingEnrollments",
                column: "GroupTrainingId");

            migrationBuilder.CreateIndex(
                name: "IX_GroupTrainingEnrollments_GroupTrainingId_MemberProfileId",
                table: "GroupTrainingEnrollments",
                columns: new[] { "GroupTrainingId", "MemberProfileId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_GroupTrainingEnrollments_MemberProfileId",
                table: "GroupTrainingEnrollments",
                column: "MemberProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_GroupTrainings_CenterId",
                table: "GroupTrainings",
                column: "CenterId");

            migrationBuilder.CreateIndex(
                name: "IX_GroupTrainings_StartsAt",
                table: "GroupTrainings",
                column: "StartsAt");

            migrationBuilder.CreateIndex(
                name: "IX_GroupTrainings_Status",
                table: "GroupTrainings",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_GroupTrainings_TrainerProfileId",
                table: "GroupTrainings",
                column: "TrainerProfileId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "GroupTrainingEnrollments");

            migrationBuilder.DropTable(
                name: "GroupTrainings");
        }
    }
}
