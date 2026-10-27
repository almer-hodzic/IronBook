using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace IronBook.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddStripeCardPayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "StripeCheckoutKey",
                table: "Payments",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StripePaymentIntentId",
                table: "Payments",
                type: "nvarchar(255)",
                maxLength: 255,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Payments_StripeCheckoutKey",
                table: "Payments",
                column: "StripeCheckoutKey",
                unique: true,
                filter: "[StripeCheckoutKey] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Payments_StripePaymentIntentId",
                table: "Payments",
                column: "StripePaymentIntentId",
                unique: true,
                filter: "[StripePaymentIntentId] IS NOT NULL");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Payments_StripeCard",
                table: "Payments",
                sql: "([StripeCheckoutKey] IS NULL AND [StripePaymentIntentId] IS NULL) OR ([PaymentMethod] = 'Card' AND [StripeCheckoutKey] IS NOT NULL)");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Payments_StripeCheckoutKey",
                table: "Payments");

            migrationBuilder.DropIndex(
                name: "IX_Payments_StripePaymentIntentId",
                table: "Payments");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Payments_StripeCard",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "StripeCheckoutKey",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "StripePaymentIntentId",
                table: "Payments");
        }
    }
}
