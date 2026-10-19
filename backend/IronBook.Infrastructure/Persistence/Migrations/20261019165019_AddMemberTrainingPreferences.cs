using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace IronBook.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddMemberTrainingPreferences : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "TrainingPreferences",
                columns: table => new
                {
                    MemberProfileId = table.Column<int>(type: "int", nullable: false),
                    PrimaryGoal = table.Column<string>(type: "nvarchar(30)", maxLength: 30, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingPreferences", x => x.MemberProfileId);
                    table.ForeignKey(
                        name: "FK_TrainingPreferences_MemberProfiles_MemberProfileId",
                        column: x => x.MemberProfileId,
                        principalTable: "MemberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TrainingPreferenceInterests",
                columns: table => new
                {
                    MemberProfileId = table.Column<int>(type: "int", nullable: false),
                    Category = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingPreferenceInterests", x => new { x.MemberProfileId, x.Category });
                    table.ForeignKey(
                        name: "FK_TrainingPreferenceInterests_TrainingPreferences_MemberProfileId",
                        column: x => x.MemberProfileId,
                        principalTable: "TrainingPreferences",
                        principalColumn: "MemberProfileId",
                        onDelete: ReferentialAction.Cascade);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TrainingPreferenceInterests");

            migrationBuilder.DropTable(
                name: "TrainingPreferences");
        }
    }
}
