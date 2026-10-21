using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace IronBook.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAccountsAndAuthSessions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Accounts",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    Username = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false, collation: "Latin1_General_100_CI_AS"),
                    PasswordHash = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false),
                    Role = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false, collation: "Latin1_General_100_BIN2"),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    MemberProfileId = table.Column<int>(type: "int", nullable: true),
                    TrainerProfileId = table.Column<int>(type: "int", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Accounts", x => x.Id);
                    table.CheckConstraint("CK_Accounts_RoleProfile", "([Role] = 'Admin' AND [MemberProfileId] IS NULL AND [TrainerProfileId] IS NULL) OR ([Role] = 'Member' AND [MemberProfileId] IS NOT NULL AND [TrainerProfileId] IS NULL) OR ([Role] = 'Trainer' AND [TrainerProfileId] IS NOT NULL AND [MemberProfileId] IS NULL)");
                    table.ForeignKey(
                        name: "FK_Accounts_MemberProfiles_MemberProfileId",
                        column: x => x.MemberProfileId,
                        principalTable: "MemberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_Accounts_TrainerProfiles_TrainerProfileId",
                        column: x => x.TrainerProfileId,
                        principalTable: "TrainerProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "AuthSessions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    AccountId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    RevokedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AuthSessions", x => x.Id);
                    table.CheckConstraint("CK_AuthSessions_ExpiresAt", "[ExpiresAt] > [CreatedAt]");
                    table.ForeignKey(
                        name: "FK_AuthSessions_Accounts_AccountId",
                        column: x => x.AccountId,
                        principalTable: "Accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Accounts_MemberProfileId",
                table: "Accounts",
                column: "MemberProfileId",
                unique: true,
                filter: "[MemberProfileId] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Accounts_TrainerProfileId",
                table: "Accounts",
                column: "TrainerProfileId",
                unique: true,
                filter: "[TrainerProfileId] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Accounts_Username",
                table: "Accounts",
                column: "Username",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_AuthSessions_AccountId_RevokedAt",
                table: "AuthSessions",
                columns: new[] { "AccountId", "RevokedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AuthSessions");

            migrationBuilder.DropTable(
                name: "Accounts");
        }
    }
}
